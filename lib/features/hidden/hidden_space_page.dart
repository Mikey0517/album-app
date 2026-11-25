import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../core/design/radius.dart';
import '../../core/design/colors.dart';
import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';
import '../../core/hidden_space/hidden_lock.dart';
import '../../core/hidden_space/hidden_space_store.dart';
import '../feed/preview/image_preview_page.dart';
import '../feed/preview/video_preview_page.dart';

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
  bool _busy = false;

  String _pin = '';
  String? _firstPin;
  String? _error;

  List<HiddenFile> _files = const [];

  /// 视频缩略图：同一条只生成一次。
  final Map<String, Future<Uint8List?>> _videoThumbs = {};

  @override
  void initState() {
    super.initState();
    HiddenSpacePage.isOpen = true;
    _init();
  }

  @override
  void dispose() {
    HiddenSpacePage.isOpen = false;
    super.dispose();
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
  }

  Future<void> _importFiles() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final added = await HiddenSpaceStore.importPicked();
      if (!mounted) return;
      if (added.isEmpty) return;
      await _loadFiles();
    } on UnsupportedError catch (e) {
      if (mounted) _snack(e.message ?? '当前系统暂不支持导入文件');
    } catch (e) {
      if (mounted) _snack('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _open(HiddenFile file) {
    if (file.isImage) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImagePreviewPage(path: file.path),
        ),
      );
    } else if (file.isVideo) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPreviewPage(path: file.path),
        ),
      );
    }
    // 其它类型先不处理。
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
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      );
    }
    if (!_unlocked) return _buildGate();
    return _buildVault();
  }

  Widget _buildGate() {
    final setting = !_configured;
    final title = setting
        ? (_firstPin == null ? '设置 6 位数字密码' : '再输入一次')
        : '输入密码';
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
                Text(title, style: AppText.titleMedium.copyWith(color: Colors.white)),
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
        actions: [
          IconButton(
            tooltip: '导入文件',
            onPressed: _busy ? null : _importFiles,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                : const Icon(Icons.add),
          ),
        ],
      ),
      body: _files.isEmpty ? _buildEmpty() : _buildGrid(),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _importFiles,
        tooltip: '导入文件',
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
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
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        return _HiddenTile(
          file: file,
          videoThumbnail: file.isVideo
              ? _videoThumbs.putIfAbsent(file.path, () => _loadVideoThumb(file))
              : null,
          onTap: file.canOpen ? () => _open(file) : null,
          onLongPress: () => _delete(file),
        );
      },
    );
  }

  Future<Uint8List?> _loadVideoThumb(HiddenFile file) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 240,
        quality: 70,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 隐藏空间里的一个格子：图片/视频显示缩略图，其它类型显示图标 + 文件名。
class _HiddenTile extends StatelessWidget {
  final HiddenFile file;
  final Future<Uint8List?>? videoThumbnail;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _HiddenTile({
    required this.file,
    this.videoThumbnail,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          color: Colors.white.withValues(alpha: 0.06),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPreview(),
              if (file.isVideo)
                const Center(
                  child: Icon(Icons.play_circle_fill,
                      size: 30, color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (file.isImage) {
      return Image.file(
        File(file.path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _icon(Icons.broken_image_outlined),
      );
    }
    if (file.isVideo) {
      final future = videoThumbnail;
      if (future == null) return _icon(Icons.videocam_outlined);
      return FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) return _icon(Icons.videocam_outlined);
          return Image.memory(bytes, fit: BoxFit.cover);
        },
      );
    }
    return Column(
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
    );
  }

  Widget _icon(IconData icon) => Center(
        child: Icon(icon, size: 30, color: Colors.white.withValues(alpha: 0.5)),
      );

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
