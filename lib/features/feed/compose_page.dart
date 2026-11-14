import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
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
import 'preview/image_preview_page.dart';
import 'preview/video_preview_page.dart';

class ComposePage extends StatefulWidget {
  const ComposePage({super.key});

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final TextEditingController _textCtrl = TextEditingController();
  final List<_PickedMedia> _medias = [];

  bool _publishing = false;
  bool _processingUpload = false;
  bool _aiGenerating = false;

  /// null 表示表单还在组装、尚未收到上传进度。
  double? _uploadProgress = 0.0;

  static const int _maxMedias = 9;

  bool get _hasContent =>
      _textCtrl.text.trim().isNotEmpty || _medias.isNotEmpty;

  bool get _canPublish => _hasContent && !_publishing;

  /// 没有选中媒体时不能点 AI 帮写（AI 必须看图）。
  bool get _canUseAi => _medias.isNotEmpty && !_aiGenerating && !_publishing;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _onClose() async {
    if (_publishing) return;
    FocusScope.of(context).unfocus();
    if (!_hasContent) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('放弃发布？', style: AppText.titleMedium),
          content: const Text(
            '已填写的内容和选择的媒体将不会保留。',
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
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickMedias() async {
    if (_publishing) return;
    if (_medias.length >= _maxMedias) {
      _toast('最多选择 $_maxMedias 个媒体');
      return;
    }
    FocusScope.of(context).unfocus();
    try {
      final pickedResult = await pickMultipleMediaFiles(
        limit: _maxMedias - _medias.length,
      );
      if (!mounted) return;
      if (pickedResult.failedCount > 0) {
        _toast('存储空间不足，${pickedResult.failedCount} 个文件没能读取');
      }
      final items = pickedResult.items;
      if (items.isEmpty) return;

      final picked = <_PickedMedia>[];
      for (final item in items) {
        if (_medias.length + picked.length >= _maxMedias) break;
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
      setState(() => _medias.addAll(picked));
    } on PlatformException {
      // 用户取消或权限被拒绝，静默返回。
    } catch (e) {
      if (mounted) _toast('选择失败：$e');
    }
  }

  void _moveMedia(int from, int to) {
    if (from == to || from < 0 || from >= _medias.length) return;
    setState(() {
      final media = _medias.removeAt(from);
      final target = to.clamp(0, _medias.length);
      _medias.insert(target, media);
    });
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
    final media = _medias[index];
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

  Future<void> _publish() async {
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
                      _buildMediaGrid(),
                      _buildAiButton(),
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
              '发表',
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
          return DragTarget<int>(
            onWillAcceptWithDetails: (details) => details.data != index,
            onAcceptWithDetails: (details) {
              _moveMedia(details.data, index);
            },
            builder: (context, candidates, rejected) {
              final tile = _MediaPreviewTile(
                key: ObjectKey(media),
                media: media,
                onRemove: () => setState(() => _medias.removeAt(index)),
                onTap: () => _previewMedia(index),
              );
              return LongPressDraggable<int>(
                data: index,
                feedback: _DragMediaFeedback(media: media),
                childWhenDragging: Opacity(opacity: 0.25, child: tile),
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
                  child: tile,
                ),
              );
            },
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
        color: Colors.black.withOpacity(0.5),
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
                  '正在发布…',
                  style: AppText.body.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
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

  String get durationLabel {
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
                    color: Colors.black.withOpacity(0.6),
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
        color: Colors.black.withOpacity(0.55),
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
