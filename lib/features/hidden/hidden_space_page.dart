import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';
import '../../core/responsive.dart';
import '../../core/hidden_space/hidden_import_manager.dart';
import '../../core/hidden_space/hidden_lock.dart';
import '../../core/hidden_space/hidden_space_store.dart';
import '../../core/local_image_preview.dart';
import '../../core/media_picker.dart';
import '../../core/motion_photo.dart';
import '../../models/media.dart';
import '../../widgets/album_thumb.dart';
import '../album/album_detail_page.dart' show AlbumUploadFab;
import '../viewer/media_viewer_page.dart';
import 'hidden_import_status.dart';

/// 隐藏空间：四指下拉进入。
///
/// 第一次进来先设置 6 位数字密码；之后每次都要解锁。里面只做三件事：
/// 导入任意文件、列出文件、打开图片/视频（其它类型先只列出来，点了不处理）。
/// 文件存在 App 私有目录，不进系统相册、也不上传到相册服务。
///
/// 这个页面不挂在任何 tab 上：唯一入口是全局的四指下拉手势。
class HiddenSpacePage extends StatefulWidget {
  const HiddenSpacePage({super.key});

  /// 同一时间只允许存在一个隐藏空间页（手势可能连触发）。
  static bool isOpen = false;

  static Route<void> route() {
    return MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const HiddenSpacePage(),
    );
  }

  @override
  State<HiddenSpacePage> createState() => _HiddenSpacePageState();
}

class _HiddenSpacePageState extends State<HiddenSpacePage> {
  bool _checking = true;
  bool _configured = false;
  bool _unlocked = false;

  String _pin = '';
  String? _firstPin;
  String? _error;

  List<HiddenFile> _files = const [];

  /// 本地图片是不是动态照片（XMP 探测），缩略图角标和全屏播放都靠它。
  final Map<String, bool> _motion = {};

  /// 本地视频时长（毫秒）；探测不到就记 null。
  final Map<String, int?> _durations = {};

  /// 本地视频的封面帧（临时目录里的 jpg），和相册里的视频缩略图同一种画面。
  final Map<String, String?> _videoThumbPaths = {};

  /// 本地视频的分辨率（探测时长时顺带拿到），详情页要用。
  final Map<String, Size> _videoSizes = {};

  /// 正在探测时避免重复排队。
  final Set<String> _probing = {};

  /// 这张图是不是必须先用 JPEG 预览（现在所有本地图片都走预览）。
  final Map<String, bool> _needsPreview = {};

  /// 预览生成串行化：几十张大图同时解码会瞬间吃掉几百 MB。
  Future<void> _previewQueue = Future<void>.value();

  /// 已经刷进网格的导入条数：导入队列每完成一条就刷新一次列表。
  int _importedSeen = 0;

  @override
  void initState() {
    super.initState();
    HiddenSpacePage.isOpen = true;
    HiddenImportManager.instance.addListener(_onImportChanged);
    _init();
  }

  @override
  void dispose() {
    HiddenSpacePage.isOpen = false;
    HiddenImportManager.instance.removeListener(_onImportChanged);
    super.dispose();
  }

  /// 导入队列有进展：完成数变了就重读文件列表（新文件出现在网格里）。
  void _onImportChanged() {
    if (!mounted) return;
    final manager = HiddenImportManager.instance;
    if (manager.addedCount == _importedSeen) return;
    _importedSeen = manager.addedCount;
    unawaited(_loadFiles());
  }

  Future<void> _init() async {
    final configured = await HiddenLock.isConfigured();
    if (!mounted) return;
    setState(() {
      _configured = configured;
      _checking = false;
    });
  }

  void _onDigit(String digit) {
    if (!_configured) {
      if (_pin.length >= 6) return;
      setState(() {
        _pin += digit;
        _error = null;
      });
      if (_pin.length == 6) unawaited(_submitSetup());
      return;
    }
    if (_unlocked || _pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 6) unawaited(_submitUnlock());
  }

  void _onBackspace() {
    if (_pin.isEmpty || _unlocked) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _submitSetup() async {
    final first = _firstPin;
    if (first == null) {
      setState(() {
        _firstPin = _pin;
        _pin = '';
      });
      return;
    }
    if (first != _pin) {
      setState(() {
        _firstPin = null;
        _pin = '';
        _error = '两次输入不一致，请重新设置';
      });
      return;
    }
    final ok = await HiddenLock.setPin(_pin);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = '密码保存失败，请重试');
      return;
    }
    setState(() {
      _configured = true;
      _unlocked = true;
      _pin = '';
      _error = null;
    });
    await _loadFiles();
  }

  Future<void> _submitUnlock() async {
    final ok = await HiddenLock.verify(_pin);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _pin = '';
        _error = '密码不对';
      });
      return;
    }
    setState(() {
      _unlocked = true;
      _pin = '';
      _error = null;
    });
    await _loadFiles();
  }

  Future<void> _loadFiles() async {
    final files = await HiddenSpaceStore.load();
    if (!mounted) return;
    setState(() => _files = files);
    for (final file in files) {
      if (file.isImage) {
        unawaited(_detectNeedsPreview(file));
      }
      if (file.isVideo) {
        unawaited(_probeDuration(file));
        unawaited(_probeVideoThumb(file));
      } else if (file.isImage && !_motion.containsKey(file.path)) {
        unawaited(_probeMotion(file));
      }
    }
  }

  /// 本地图片一律先出 JPEG 预览：原图可能是 50MP/HEIC，直接解会 OOM abort。
  Future<void> _detectNeedsPreview(HiddenFile file) async {
    if (_needsPreview[file.path] == true) return;
    _needsPreview[file.path] = true;
    unawaited(_enqueuePreview(file));
  }

  /// 串行排队生成预览：一张解完再解下一张。
  Future<void> _enqueuePreview(HiddenFile file) {
    _previewQueue = _previewQueue.then((_) => _ensurePreview(file)).catchError((_) {});
    return _previewQueue;
  }

  /// 本地图片：生成 JPEG 预览并记进索引；失败就先显示占位。
  Future<void> _ensurePreview(HiddenFile file) async {
    if (_probing.contains(file.path)) return;
    final existing = file.previewPath;
    if (existing != null && File(existing).existsSync()) return;
    _probing.add(file.path);
    try {
      final preview = await LocalImagePreview.resolve(file.path);
      if (preview != null && preview != file.path) {
        await HiddenSpaceStore.updatePreview(file.path, preview);
        final index = _files.indexWhere((item) => item.path == file.path);
        if (index >= 0 && mounted) {
          final updated = List<HiddenFile>.of(_files);
          updated[index] = updated[index].copyWith(previewPath: preview);
          setState(() => _files = updated);
        }
      }
    } finally {
      _probing.remove(file.path);
    }
  }

  /// 探测本地图片是不是动态照片：相册里的「动态」角标和大屏播放都靠这个。
  Future<void> _probeMotion(HiddenFile file) async {
    if (_probing.contains(file.path)) return;
    _probing.add(file.path);
    final motion = await isMotionPhotoFile(file.path);
    _probing.remove(file.path);
    _motion[file.path] = motion;
    if (mounted) setState(() {});
  }

  /// 探测本地视频时长（缩略图上的时长角标和全屏控制条要用）。
  Future<void> _probeDuration(HiddenFile file) async {
    if (_durations.containsKey(file.path) || _probing.contains(file.path)) {
      return;
    }
    _probing.add(file.path);
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(file.path));
      await controller.initialize();
      _durations[file.path] = controller.value.duration.inMilliseconds;
      final size = controller.value.size;
      if (size.width > 0 && size.height > 0) _videoSizes[file.path] = size;
    } catch (_) {
      _durations[file.path] = null;
    } finally {
      await controller?.dispose();
      _probing.remove(file.path);
    }
    if (mounted) setState(() {});
  }

  /// 抽一帧当本地视频的封面（相册里的视频缩略图也是画面，不是占位图标）。
  Future<void> _probeVideoThumb(HiddenFile file) async {
    if (_videoThumbPaths.containsKey(file.path) ||
        _probing.contains(file.path)) {
      return;
    }
    _probing.add(file.path);
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory('${tempDir.path}/hidden_thumbs');
      if (!await dir.exists()) await dir.create(recursive: true);
      _videoThumbPaths[file.path] = await VideoThumbnail.thumbnailFile(
        video: file.path,
        thumbnailPath: dir.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        quality: 75,
      );
    } catch (_) {
      _videoThumbPaths[file.path] = null;
    } finally {
      _probing.remove(file.path);
    }
    if (mounted) setState(() {});
  }

  /// 把可打开的文件转成 [Media]，交给全屏浏览页（图片/视频和相册里同一套）。
  ({List<Media> items, Map<String, int> indexById}) _openableMedia() {
    final items = <Media>[];
    final indexById = <String, int>{};
    for (final file in _files) {
      if (!file.canOpen) continue;
      final index = items.length;
      indexById[file.id] = index;
      items.add(
        Media(
          id: index,
          type: file.isVideo ? 'video' : 'image',
          thumbUrl: null,
          url: '',
          width: _videoSizes[file.path]?.width.round(),
          height: _videoSizes[file.path]?.height.round(),
          durationMs: _durations[file.path],
          takenAt: file.addedAt,
          createdAt: file.addedAt,
          postId: null,
          originalFormat: file.extension.isEmpty ? null : file.extension,
          fileSize: file.size,
          localPath: file.path,
          localMotion: _motion[file.path] ?? false,
          localThumbPath: _videoThumbPaths[file.path],
          localPreviewPath: file.previewPath,
          localNeedsPreview: _needsPreview[file.path],
        ),
      );
    }
    return (items: items, indexById: indexById);
  }

  Future<void> _importFiles() async {
    try {
      final sources = await pickHiddenSources();
      if (!mounted || sources.isEmpty) return;
      // 排进导入队列：进度显示在页面里的「上传中 x/y」状态条上（和相册一致）。
      await HiddenImportManager.instance.enqueue(sources);
    } on UnsupportedError catch (e) {
      if (mounted) _snack(e.message ?? '当前系统暂不支持导入文件');
    } catch (e) {
      if (mounted) _snack('导入失败：$e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _open(List<Media> items, int index) {
    Navigator.of(context).push(
      MediaViewerPage.route(
        items: items,
        initialIndex: index,
        heroPrefix: 'hidden_',
      ),
    );
  }

  Future<void> _delete(HiddenFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        title: const Text('删除这个文件？', style: AppText.titleMedium),
        content: Text(file.name, style: AppText.bodySmall),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final files = await HiddenSpaceStore.delete(file);
    if (!mounted) return;
    setState(() => _files = files);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child:
              CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      );
    }
    if (!_unlocked) return _buildGate();
    return _buildVault();
  }

  Widget _buildGate() {
    final setting = !_configured;
    final title =
        setting ? (_firstPin == null ? '设置 6 位数字密码' : '再输入一次') : '输入密码';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: AppText.titleMedium.copyWith(color: Colors.white)),
                if (setting && _firstPin == null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '忘记密码将无法找回，请记牢',
                    style: AppText.caption.copyWith(color: Colors.white54),
                  ),
                ],
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 6; i++)
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _pin.length
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(
                  height: 44,
                  child: Center(
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            style: AppText.caption.copyWith(
                              color: AppColors.danger,
                            ),
                          ),
                  ),
                ),
                _PinKeypad(
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  enabled: _pin.length < 6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVault() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_files.length} 个文件', style: AppText.body),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _files.isEmpty ? _buildEmpty() : _buildGrid(),
          ),
          // 「上传中 x/y」状态条：只在隐藏空间里出现（退出就看不到），点开是
          // 和相册上传列表一样的面板。
          Positioned(
            right: 16,
            bottom: 16 +
                AlbumUploadFab.diameter +
                12 +
                MediaQuery.paddingOf(context).bottom,
            child: HiddenImportStatusChip(
              onTap: () => showHiddenImportSheet(context),
            ),
          ),
        ],
      ),
      // 和相册页同一个上传按钮（玻璃圆钮），导入文件就是它。
      floatingActionButton: AlbumUploadFab(
        label: '导入文件',
        onPressed: _importFiles,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined,
              size: 44, color: Colors.white.withValues(alpha: 0.32)),
          const SizedBox(height: 12),
          Text('还没有文件', style: AppText.body.copyWith(color: Colors.white70)),
          const SizedBox(height: 6),
          Text(
            '点右下角导入',
            style: AppText.caption.copyWith(color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    // 几何照搬相册页的媒体网格：外边距 12、格间距 2、圆角 4、手机 4 列。
    final columns = responsiveColumns(context, 4);
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final tile = (width - 12 * 2 - 2 * (columns - 1)) / columns;
    final cacheWidth = (tile * dpr).round();
    final openable = _openableMedia();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final mediaIndex = openable.indexById[file.id];
        if (mediaIndex == null) {
          // 打不开的类型：图标 + 文件名（先只列出来）。
          return _HiddenTile(file: file, onLongPress: () => _delete(file));
        }
        final media = openable.items[mediaIndex];
        return AlbumThumb(
          media: media,
          radius: AppRadius.xs,
          cacheWidth: cacheWidth,
          // 时长还没探测完就先别挂角标，免得显示成 00:00。
          showVideoBadge: !file.isVideo || media.durationMs != null,
          heroTag: 'hidden_${media.id}',
          onTap: () => _open(openable.items, mediaIndex),
          onLongPress: () => _delete(file),
        );
      },
    );
  }
}

/// 打不开的文件（PDF/文档/压缩包等）：图标 + 文件名 + 大小。
///
/// 图片/视频走 [AlbumThumb] 和相册里完全一致，这里只负责剩下的类型。
class _HiddenTile extends StatelessWidget {
  final HiddenFile file;
  final VoidCallback? onLongPress;

  const _HiddenTile({required this.file, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Container(
          color: Colors.white.withValues(alpha: 0.06),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _iconForExtension(file.extension),
                size: 30,
                color: Colors.white.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.3,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatBytes(file.size),
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withValues(alpha: 0.38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconForExtension(String extension) {
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
      case 'txt':
      case 'md':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_outlined;
      case 'zip':
      case 'rar':
      case '7z':
      case 'gz':
        return Icons.folder_zip_outlined;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'flac':
        return Icons.audiotrack_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

/// 数字键盘：3×4，最后一行是「空、0、退格」。
class _PinKeypad extends StatelessWidget {
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  const _PinKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final key in row)
                SizedBox(
                  width: 84,
                  height: 66,
                  child: key.isEmpty
                      ? const SizedBox.shrink()
                      : TextButton(
                          onPressed: !enabled
                              ? null
                              : key == '⌫'
                                  ? onBackspace
                                  : () => onDigit(key),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                          ),
                          child: key == '⌫'
                              ? const Icon(Icons.backspace_outlined, size: 20)
                              : Text(
                                  key,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}
