import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../api/ai_api.dart';
import '../../api/post_api.dart';
import '../../core/ai_media_targets.dart';
import '../../core/api_client.dart';
import '../../core/image_encoder.dart';
import '../../core/responsive.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/shadow.dart';
import '../../core/design/text_styles.dart';
import '../../core/media_picker.dart';
import '../../core/media_store.dart';
import '../../core/motion_photo.dart';
import '../../core/source_media_cleanup.dart';
import '../../models/media.dart';
import '../../models/post.dart';
import '../../widgets/album_thumb.dart';
import 'preview/image_preview_page.dart';
import 'preview/video_preview_page.dart';

class ComposePage extends StatefulWidget {
  /// 非空表示「编辑已发布动态」：文案编辑器和媒体选择都同一套，
  /// 媒体可以删、可以加、可以拖动排序，保存后发布时间不变。
  final Post? editPost;

  const ComposePage({super.key, this.editPost});

  /// 选图入口的测试注入点：桌面上 Platform.isAndroid 恒为 false，
  /// 走不到系统相册通道，单测用它喂固定的选中文件。
  @visibleForTesting
  static Future<PickedMediaResult> Function({int limit}) pickMediaFiles =
      pickMultipleMediaFiles;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final TextEditingController _textCtrl = TextEditingController();

  /// 发布模式下待上传的本地媒体。
  final List<_PickedMedia> _medias = [];

  /// 编辑模式下的媒体列表：已有的（服务端）和新选的（本地）混在一条列表里，
  /// 列表顺序就是保存后动态里的顺序。
  final List<_EditMedia> _editItems = [];

  /// 点过「保存」才上传；上传成功的 id 记在这里，重试时不会重复上传。
  final Map<_EditMedia, int> _uploadedIds = {};

  /// 编辑模式下有没有动过媒体（删/加/排序）。只改文案时不该提示「放弃编辑」。
  bool _editMediaTouched = false;

  bool _publishing = false;
  bool _processingUpload = false;
  bool _aiGenerating = false;

  /// null 表示表单还在组装、尚未收到上传进度。
  double? _uploadProgress = 0.0;

  static const int _maxMedias = 9;

  bool get _isEditing => widget.editPost != null;

  @override
  void initState() {
    super.initState();
    // 编辑：把原标题/正文填进同一个编辑器，光标落在末尾。
    final content = widget.editPost?.content;
    if (content != null && content.isNotEmpty) {
      _textCtrl.value = TextEditingValue(
        text: content,
        selection: TextSelection.collapsed(offset: content.length),
      );
    }
    // 编辑：已发布的媒体直接进可编辑列表，缩略图、顺序都用同一套 UI。
    final editMedias = widget.editPost?.medias ?? const <Media>[];
    for (final media in editMedias) {
      _editItems.add(_EditMedia.remote(media));
    }
  }

  bool get _hasContent =>
      _textCtrl.text.trim().isNotEmpty ||
      (_isEditing ? _editItems.isNotEmpty : _medias.isNotEmpty);

  bool get _canPublish => _hasContent && !_publishing;

  /// 没有选中媒体时不能点 AI 帮写（AI 必须看图）。
  bool get _canUseAi => _medias.isNotEmpty && !_aiGenerating && !_publishing;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  bool get _dirty {
    if (!_hasContent) return false;
    if (!_isEditing) return true;
    // 编辑模式下没改文案、也没动媒体就走，别拿「放弃编辑？」拦一个什么都没改的人。
    if (_editMediaTouched) return true;
    return _textCtrl.text.trim() != (widget.editPost?.content ?? '').trim();
  }

  Future<void> _onClose() async {
    if (_publishing) return;
    FocusScope.of(context).unfocus();
    if (!_dirty) {
      _cleanupUploads();
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_isEditing ? '放弃编辑？' : '放弃发布？',
              style: AppText.titleMedium),
          content: Text(
            _isEditing ? '已改动的文案和媒体将不会保存。' : '已填写的内容和选择的媒体将不会保留。',
            style: AppText.bodySmall,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('放弃'),
            ),
          ],
        );
      },
    );
    if (discard == true && mounted) {
      _cleanupUploads();
      Navigator.of(context).pop();
    }
  }

  /// 放弃编辑时，把「保存途中已经上传成功、但还没挂到动态上」的临时媒体删掉：
  /// 服务端只允许删这种未挂载的媒体，删不掉也只是一条不可见的残留，不会脏朋友圈。
  void _cleanupUploads() {
    if (_uploadedIds.isEmpty) return;
    final ids = _uploadedIds.values.toList(growable: false);
    _uploadedIds.clear();
    unawaited(PostApi.deleteUploadedMedia(ids));
  }

  /// 当前媒体数量：发布看 `_medias`，编辑看 `_editItems`，上限共用。
  int get _mediaCount => _isEditing ? _editItems.length : _medias.length;

  Future<void> _pickMedias() async {
    if (_publishing) return;
    if (_mediaCount >= _maxMedias) {
      _toast('最多选择 $_maxMedias 个媒体');
      return;
    }
    FocusScope.of(context).unfocus();
    try {
      final pickedResult = await ComposePage.pickMediaFiles(
        limit: _maxMedias - _mediaCount,
      );
      if (!mounted) return;
      if (pickedResult.failedCount > 0) {
        _toast('存储空间不足，${pickedResult.failedCount} 个文件没能读取');
      }
      final items = pickedResult.items;
      if (items.isEmpty) return;

      final picked = <_PickedMedia>[];
      for (final item in items) {
        if (_mediaCount + picked.length >= _maxMedias) break;
        final file = item.file;
        final type = _detectType(file.path, file.mimeType);
        if (type == null) continue;

        int? durationMs;
        var isMotion = false;
        if (type == 'video') {
          durationMs = await _getVideoDurationMs(file.path);
        } else {
          isMotion = await isMotionPhotoFile(file.path);
        }
        picked.add(
          _PickedMedia(
            path: file.path,
            // 系统相册 URI：发布成功后用它问用户要不要删手机里的原图。
            uri: item.uri,
            type: type,
            durationMs: durationMs,
            isMotion: isMotion,
          ),
        );
      }
      if (!mounted) return;
      if (picked.isEmpty) {
        _toast('未识别到支持的图片或视频');
        return;
      }
      setState(() {
        if (_isEditing) {
          // 新选的追加在末尾：用户随后还能拖动调整顺序。
          _editItems.addAll(picked.map(_EditMedia.local));
          _editMediaTouched = true;
        } else {
          _medias.addAll(picked);
        }
      });
    } on PlatformException {
      // 用户取消或权限被拒绝，静默返回。
    } catch (e) {
      if (mounted) _toast('选择失败：$e');
    }
  }

  void _moveMedia(int from, int to) {
    setState(() => _reorder(_medias, from, to));
  }

  void _moveEditMedia(int from, int to) {
    setState(() {
      _reorder(_editItems, from, to);
      _editMediaTouched = true;
    });
  }

  void _reorder<T>(List<T> list, int from, int to) {
    if (from == to || from < 0 || from >= list.length) return;
    final item = list.removeAt(from);
    list.insert(to.clamp(0, list.length), item);
  }

  /// 编辑模式删掉一项：已经从「保存」里上传过的话顺手清掉，不留孤儿文件。
  void _removeEditMedia(int index) {
    if (index < 0 || index >= _editItems.length) return;
    final item = _editItems[index];
    final uploadedId = _uploadedIds.remove(item);
    setState(() {
      _editItems.removeAt(index);
      _editMediaTouched = true;
    });
    if (uploadedId != null) {
      unawaited(PostApi.deleteUploadedMedia([uploadedId]));
    }
  }

  String? _detectType(String path, String? mimeType) {
    final ext = path.toLowerCase().split('.').last;
    const imageExts = {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'avif',
      'bmp'
    };
    const videoExts = {'mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv'};
    if (imageExts.contains(ext)) return 'image';
    if (videoExts.contains(ext)) return 'video';
    if (mimeType != null && mimeType.startsWith('image/')) return 'image';
    if (mimeType != null && mimeType.startsWith('video/')) return 'video';
    return null;
  }

  Future<int?> _getVideoDurationMs(String path) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      return controller.value.duration.inMilliseconds;
    } catch (_) {
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  Future<void> _previewMedia(int index) async {
    await _previewPicked(_medias[index]);
  }

  Future<void> _previewPicked(_PickedMedia media) async {
    if (media.isMotion) {
      final info = await motionPhotoInfoFile(media.path);
      final video =
          info == null ? null : await extractMotionVideoFile(media.path, info);
      if (!mounted) return;
      if (video != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPreviewPage(path: video),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    final route = media.type == 'image'
        ? MaterialPageRoute<void>(
            builder: (_) => ImagePreviewPage(path: media.path),
          )
        : MaterialPageRoute<void>(
            builder: (_) => VideoPreviewPage(path: media.path),
          );
    await Navigator.of(context).push(route);
  }

  /// 已选媒体里能交给 MediaStore 删掉的那些原图（相册 URI + 图片/视频）。
  ///
  /// uri 来自 [pickMultipleMediaFiles] 的 [PickedMediaFile.uri]：只有 Android 原生
  /// Photo Picker 通道会带回来；iOS 或退回 image_picker 时是 null，也就不提示。
  List<SourceTarget> _sourceMediaTargets() {
    final targets = <SourceTarget>[];
    for (final media in _medias) {
      final uri = media.uri;
      if (uri == null || uri.isEmpty) continue;
      // 和相册页一致：视频按媒体类型判断，删除时要带上 video 标记。
      targets.add((uri: uri, isVideo: media.type == 'video'));
    }
    return List<SourceTarget>.unmodifiable(targets);
  }

  /// 编辑模式：先上传新增媒体拿到 id，再把「最终媒体顺序 + 文案」一起 PUT 提交。
  ///
  /// 上传只发生在点「保存」之后：用户在编辑页里增删媒体、最后取消，都不会
  /// 产生任何上传，也就没有孤儿文件；只有「上传成功但 PUT 失败」这一种情况
  /// 会留下临时媒体，它由 [_cleanupUploads]（取消/关闭时）兜底删掉。
  Future<void> _saveEdit() async {
    if (_publishing || !_hasContent) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _publishing = true;
      _processingUpload = false;
      _uploadProgress = null;
    });
    try {
      final mediaIds = await _resolveEditMediaIds();
      if (!mounted) return;
      final updated = await PostApi.update(
        widget.editPost!.id,
        content: _textCtrl.text.trim(),
        mediaIds: mediaIds,
      );
      if (!mounted) return;
      // 已经挂到动态上了，不再是「待清理的临时媒体」。
      _uploadedIds.clear();
      Navigator.of(context).pop<Object?>(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _processingUpload = false;
        _uploadProgress = 0.0;
      });
      _toast(ApiClient.errorText(e));
    }
  }

  /// 上传还没传过的新增媒体，返回按当前编辑顺序排好的媒体 id 列表。
  Future<List<int>> _resolveEditMediaIds() async {
    final pending = _editItems
        .where((item) => item.local != null && !_uploadedIds.containsKey(item))
        .toList(growable: false);
    if (pending.isNotEmpty) {
      final files = pending
          .map((item) => XFile(item.local!.path, name: item.local!.filename))
          .toList(growable: false);
      final uploaded = await PostApi.uploadForEdit(
        files,
        onSendProgress: (sent, total) {
          if (!mounted) return;
          final progress = total > 0 ? sent / total : null;
          setState(() {
            _uploadProgress = progress;
            _processingUpload = progress != null && progress >= 0.999;
          });
        },
      );
      if (uploaded.isEmpty) {
        throw StateError('上传新媒体失败');
      }
      for (var i = 0; i < pending.length; i++) {
        // 服务端按顺序返回；数量对不上时后面的留空，重试会补传。
        if (i >= uploaded.length) break;
        _uploadedIds[pending[i]] = uploaded[i].id;
      }
    }
    final ids = <int>[];
    for (final item in _editItems) {
      final remote = item.remote;
      if (remote != null) {
        ids.add(remote.id);
        continue;
      }
      final uploadedId = _uploadedIds[item];
      if (uploadedId != null) ids.add(uploadedId);
    }
    return ids;
  }

  Future<void> _publish() async {
    if (_isEditing) {
      await _saveEdit();
      return;
    }
    if (_publishing || !_hasContent) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _publishing = true;
      _processingUpload = false;
      _uploadProgress = null;
    });

    try {
      final files = _medias
          .map((media) => XFile(media.path, name: media.filename))
          .toList(growable: false);
      await PostApi.create(
        content: _textCtrl.text.trim(),
        files: files,
        onSendProgress: (sent, total) {
          if (!mounted) return;
          final progress = total > 0 ? sent / total : null;
          setState(() {
            _uploadProgress = progress;
            _processingUpload = progress != null && progress >= 0.999;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _processingUpload = false;
      });
      // 发布成功后照相册页的做法问一次要不要删手机里的原图。
      // 先问再关：弹窗要挂在还活着的页面上（mounted），删除本身不挡着关闭。
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final targets = _sourceMediaTargets();
      final confirmed = await confirmDeleteSourceMedia(
        context,
        targets,
        targetLabel: '朋友圈',
        action: '发布到',
      );
      if (!mounted) return;
      navigator.pop(true);
      if (confirmed) {
        unawaited(deleteSourceMedia(targets, messenger: messenger));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _processingUpload = false;
        _uploadProgress = 0.0;
      });
      _toast(ApiClient.errorText(e));
    }
  }

  /// 图片压成 512px 后转 base64，体积小、token 也少。
  Future<Map<String, String>?> _imageToBase64Input(String path) async {
    final encoded = await ImageEncoder.encode(path);
    if (encoded == null) return null;
    return {'base64': base64Encode(encoded.bytes), 'mime': encoded.mime};
  }

  /// 视频不支持直接识别，抽 0.5s 处的一帧（避开纯黑首帧）。
  Future<Map<String, String>?> _videoToBase64Input(String path) async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 512,
        quality: 80,
        timeMs: 500,
      );
      if (bytes == null || bytes.isEmpty) return null;
      return {'base64': base64Encode(bytes), 'mime': 'image/jpeg'};
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, String>>> _collectAiInputs() async {
    final inputs = <Map<String, String>>[];
    // 选了 9 个文件时只取 3 张代表图（首/中/尾），token 不变但能概括整组。
    for (final media in pickAiTargets(_medias)) {
      final input = media.type == 'video'
          ? await _videoToBase64Input(media.path)
          : await _imageToBase64Input(media.path);
      if (input != null) inputs.add(input);
    }
    return inputs;
  }

  Future<void> _generateCaption() async {
    if (!_canUseAi) return;
    setState(() => _aiGenerating = true);
    try {
      final inputs = await _collectAiInputs();
      if (!mounted) return;
      if (inputs.isEmpty) {
        _toast('无法读取媒体内容');
        return;
      }
      final caption = await AiApi.suggestCaption(
        images: inputs,
        context: _textCtrl.text.trim(),
      );
      if (!mounted) return;
      if (caption.isEmpty) {
        _toast('AI 没有返回内容，请重试');
        return;
      }
      // 已有文字时追加，不覆盖用户写的内容。
      setState(() {
        final current = _textCtrl.text.trim();
        _textCtrl.text = current.isEmpty ? caption : '$current $caption';
        _textCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _textCtrl.text.length),
        );
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      final detail = data is Map && data['detail'] is String
          ? data['detail'] as String
          : ApiClient.errorText(e);
      _toast(detail);
    } catch (e) {
      if (mounted) _toast('AI 生成失败：${ApiClient.errorText(e)}');
    } finally {
      if (mounted) setState(() => _aiGenerating = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: PopScope(
        canPop: !_publishing,
        // 系统返回键也会离开页面：已经上传但还没挂上去的临时媒体在这里兜底清掉。
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) _cleanupUploads();
        },
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: _publishing,
              child: Scaffold(
                appBar: _buildAppBar(),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Column(
                    children: [
                      _buildTextField(),
                      // 编辑：媒体和发布时一样能加、能删、能拖动排序。
                      // AI 帮写只对本次新选的本地媒体生效，编辑页不提供。
                      if (_isEditing)
                        _buildEditableMediaGrid()
                      else ...[
                        _buildMediaGrid(),
                        _buildAiButton(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (_publishing) _buildPublishOverlay(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bgPage,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        onPressed: _publishing ? null : _onClose,
        tooltip: '关闭',
        icon: Icon(
          Icons.close,
          size: 24,
          color: AppColors.textPrimary,
        ),
      ),
      title: null,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton(
            onPressed: _canPublish ? _publish : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              _isEditing ? '保存' : '发表',
              style: AppText.button.copyWith(
                fontSize: 16,
                color: _canPublish ? AppColors.primary : AppColors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: _textCtrl,
        maxLines: null,
        minLines: 5,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: AppText.body.copyWith(fontSize: 16, height: 1.6),
        cursorColor: AppColors.primary,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          hintText: '这一刻的想法…',
          hintStyle: AppText.body.copyWith(
            fontSize: 16,
            color: AppColors.textTertiary,
            height: 1.6,
          ),
          contentPadding: EdgeInsets.zero,
          isDense: true,
          filled: false,
        ),
      ),
    );
  }

  /// 编辑模式下的媒体区：可删、可加、可拖动排序，尺寸/间距和发布时一致。
  Widget _buildEditableMediaGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: responsiveColumns(context, 3),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _editItems.length >= _maxMedias
            ? _editItems.length
            : _editItems.length + 1,
        itemBuilder: (context, index) {
          if (index == _editItems.length && _editItems.length < _maxMedias) {
            return _AddMediaTile(onTap: _pickMedias);
          }
          final item = _editItems[index];
          final remote = item.remote;
          final local = item.local;
          return LayoutBuilder(
            builder: (context, constraints) {
              final cacheWidth = (constraints.maxWidth *
                      MediaQuery.of(context).devicePixelRatio)
                  .round();
              final Widget tile = remote != null
                  ? _ExistingMediaTile(
                      key: ObjectKey(remote),
                      media: remote,
                      cacheWidth: cacheWidth,
                      onRemove: () => _removeEditMedia(index),
                    )
                  : _MediaPreviewTile(
                      key: ObjectKey(local),
                      media: local!,
                      onRemove: () => _removeEditMedia(index),
                      onTap: () => _previewPicked(local),
                    );
              return _DraggableMediaTile(
                index: index,
                feedback: remote != null
                    ? _DragExistingFeedback(media: remote)
                    : _DragMediaFeedback(media: local!),
                onMove: (from) => _moveEditMedia(from, index),
                child: tile,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMediaGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: responsiveColumns(context, 3),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount:
            _medias.length >= _maxMedias ? _medias.length : _medias.length + 1,
        itemBuilder: (context, index) {
          if (index == _medias.length && _medias.length < _maxMedias) {
            return _AddMediaTile(onTap: _pickMedias);
          }
          final media = _medias[index];
          return _DraggableMediaTile(
            index: index,
            feedback: _DragMediaFeedback(media: media),
            onMove: (from) => _moveMedia(from, index),
            child: _MediaPreviewTile(
              key: ObjectKey(media),
              media: media,
              onRemove: () => setState(() => _medias.removeAt(index)),
              onTap: () => _previewMedia(index),
            ),
          );
        },
      ),
    );
  }

  /// 媒体网格下方、页面最底部的「AI 帮写」入口。
  Widget _buildAiButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _canUseAi ? _generateCaption : null,
          icon: _aiGenerating
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textTertiary,
                  ),
                )
              : Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: _canUseAi ? AppColors.primary : AppColors.textTertiary,
                ),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _aiGenerating ? '生成中…' : 'AI 帮写',
                style: AppText.bodySmall.copyWith(
                  color: _canUseAi ? AppColors.primary : AppColors.textTertiary,
                ),
              ),
              if (_medias.length > 3 && !_aiGenerating)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '参考 3 张代表图',
                    style: AppText.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  Widget _buildPublishOverlay() {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: Container(
            width: 240,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadow.dialog,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _isEditing ? '正在保存…' : '正在发布…',
                  style: AppText.body.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
                // 发布、以及编辑时上传新增媒体，都有百分比可报；纯改文案没有。
                if (!_isEditing || _uploadProgress != null) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: _processingUpload ? null : _uploadProgress,
                      minHeight: 4,
                      backgroundColor: AppColors.primaryLight,
                      valueColor: AlwaysStoppedAnimation(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _processingUpload
                        ? '服务器处理中…'
                        : _uploadProgress == null
                            ? '准备中…'
                            : '${(_uploadProgress! * 100).toStringAsFixed(0)}%',
                    style: AppText.caption.copyWith(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DragMediaFeedback extends StatelessWidget {
  final _PickedMedia media;

  const _DragMediaFeedback({required this.media});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 8,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: AppColors.mediaPlaceholder),
              if (media.type == 'image')
                Image.file(
                  File(media.path),
                  fit: BoxFit.cover,
                  cacheWidth: 240,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: AppColors.textTertiary),
                  ),
                )
              else
                Center(
                  child: Icon(Icons.videocam_outlined,
                      size: 30, color: AppColors.textSecondary),
                ),
              const Positioned(
                left: 4,
                bottom: 4,
                child: _MediaBadge(
                  icon: Icons.drag_indicator,
                  label: '拖动排序',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 可拖动排序的媒体格子：发布和编辑共用同一套手势与落点高亮。
class _DraggableMediaTile extends StatelessWidget {
  final int index;
  final Widget feedback;
  final Widget child;
  final void Function(int from) onMove;

  const _DraggableMediaTile({
    required this.index,
    required this.feedback,
    required this.child,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onMove(details.data),
      builder: (context, candidates, rejected) {
        return LongPressDraggable<int>(
          data: index,
          feedback: feedback,
          childWhenDragging: Opacity(opacity: 0.25, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: candidates.isEmpty
                  ? null
                  : Border.all(
                      color: AppColors.primary,
                      width: 2,
                    ),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// 编辑模式下已经发布在动态里的媒体：缩略图 + 右上角移除角标，可拖动排序。
class _ExistingMediaTile extends StatelessWidget {
  final Media media;
  final int cacheWidth;
  final VoidCallback onRemove;

  const _ExistingMediaTile({
    super.key,
    required this.media,
    required this.cacheWidth,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AlbumThumb(
          media: media,
          radius: AppRadius.sm,
          cacheWidth: cacheWidth,
        ),
        if (media.isVideo)
          Positioned(
            left: 4,
            bottom: 4,
            child: _MediaBadge(
              icon: Icons.play_arrow_rounded,
              label: mediaDurationLabel(media.durationMs),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 14,
                color: AppColors.textInverse,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 拖动已发布媒体时的跟手浮层。
class _DragExistingFeedback extends StatelessWidget {
  final Media media;

  const _DragExistingFeedback({required this.media});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 8,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AlbumThumb(media: media, radius: AppRadius.sm, cacheWidth: 240),
              const Positioned(
                left: 4,
                bottom: 4,
                child: _MediaBadge(
                  icon: Icons.drag_indicator,
                  label: '拖动排序',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 编辑模式下的一项媒体：已发布的（remote）或本次新选的（local）。
///
/// 两种混在同一条列表里，列表顺序就是保存后动态里的媒体顺序。
class _EditMedia {
  final Media? remote;
  final _PickedMedia? local;

  const _EditMedia.remote(Media media)
      : remote = media,
        local = null;

  const _EditMedia.local(_PickedMedia media)
      : remote = null,
        local = media;
}

class _PickedMedia {
  final String path;
  final String type;
  final int? durationMs;
  final bool isMotion;

  /// 系统相册里的 URI（Android Photo Picker 才有），用来删除手机原图。
  final String? uri;

  const _PickedMedia({
    required this.path,
    required this.type,
    this.durationMs,
    this.isMotion = false,
    this.uri,
  });

  String get filename {
    final parts = path.split(RegExp(r'[/\\]'));
    final name = parts.isEmpty ? path : parts.last;
    return name.isEmpty ? 'upload' : name;
  }

  String get durationLabel => mediaDurationLabel(durationMs);
}

/// 视频时长文案：3:07 / 1:02:03；时长缺失时退回 0:00。
String mediaDurationLabel(int? durationMs) {
  final ms = durationMs;
  if (ms == null || ms <= 0) return '0:00';
  final total = (ms / 1000).round();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

class _AddMediaTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddMediaTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.borderLight, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Center(
          child: Icon(Icons.add, size: 32, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

class _MediaPreviewTile extends StatelessWidget {
  final _PickedMedia media;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const _MediaPreviewTile({
    super.key,
    required this.media,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: AppColors.mediaPlaceholder),
            if (media.type == 'image')
              Image.file(
                File(media.path),
                fit: BoxFit.cover,
                cacheWidth: 400,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textTertiary,
                  ),
                ),
              )
            else
              _VideoThumbnail(path: media.path),
            if (media.type == 'video')
              Positioned(
                left: 4,
                bottom: 4,
                child: _MediaBadge(
                  icon: Icons.play_arrow_rounded,
                  label: media.durationLabel,
                ),
              ),
            if (media.type == 'image' && media.isMotion)
              const Positioned(
                left: 4,
                bottom: 4,
                child: _MediaBadge(
                  icon: Icons.motion_photos_on_outlined,
                  label: '动态',
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: AppColors.textInverse,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MediaBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: AppColors.textInverse),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textInverse,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoThumbnail extends StatefulWidget {
  final String path;

  const _VideoThumbnail({required this.path});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _bytes = null;
      _failed = false;
      _generate();
    }
  }

  Future<void> _generate() async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        quality: 75,
      );
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _failed = true);
      } else {
        setState(() => _bytes = bytes);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: BoxFit.cover);
    }
    if (_failed) {
      return Container(
        color: AppColors.mediaPlaceholder,
        child: Center(
          child: Icon(
            Icons.play_circle_outline,
            size: 32,
            color: AppColors.textTertiary,
          ),
        ),
      );
    }
    return Container(
      color: AppColors.mediaPlaceholder,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
