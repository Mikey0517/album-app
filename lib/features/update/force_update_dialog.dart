import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/shadow.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';
import '../../models/app_release.dart';
import '../../widgets/app_glass.dart';
import 'download_progress.dart';
import 'update_action_button.dart';
import 'update_service.dart';

bool _forceUpdateDialogOpen = false;

/// 下载实现：生产用 [UpdateService.download]，测试注入一个不走网络的假实现。
typedef UpdateDownload = Future<String> Function(
  AppRelease release, {
  required void Function(DownloadProgress) onProgress,
});

/// 调起系统安装器的实现；返回 true 表示系统安装器已接住这个 APK。
typedef UpdateInstall = Future<bool> Function(String path);

/// 强制更新弹窗。
///
/// 语义不变：不可关闭（[barrierDismissible] = false）、返回键无效
/// （[PopScope.canPop] = false）、没有取消/稍后按钮。
///
/// 布局只有四块：标题、一行版本信息、可滚动的更新说明、按钮。旧版那套
/// 「图标圆底 + 必须更新胶囊 + 两段重复说明 + 独立进度条 + 速度/剩余时间」
/// 都删掉了——同一件事说一遍就够，进度现在长在按钮里（见
/// [UpdateActionButton]）。
Future<void> showForceUpdateDialog(
  BuildContext context,
  AppRelease release, {
  UpdateDownload? download,
  UpdateInstall? install,
}) async {
  // 启动检查、后台恢复检查和“我的”手动检查可能同时命中同一个版本。
  if (_forceUpdateDialogOpen) return;
  _forceUpdateDialogOpen = true;
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: true,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: _ForceUpdateDialog(
            release: release,
            download: download ?? UpdateService.download,
            install: install ?? _installApk,
          ),
        );
      },
    );
  } finally {
    _forceUpdateDialogOpen = false;
  }
}

/// 默认安装实现：把 APK 交给系统安装器。
Future<bool> _installApk(String path) async {
  final result = await OpenFilex.open(
    path,
    type: 'application/vnd.android.package-archive',
  );
  return result.type == ResultType.done;
}

enum _Phase { idle, downloading, opening, awaitingInstall, error }

/// 更新说明的最大高度：4~5 行（bodySmall 13px × 1.6 行高 ≈ 21）。
///
/// 再长就让它在框里滚，弹窗高度不跟着更新说明的字数变——强制更新弹窗
/// 不该因为一次写多了发布说明而变成一整页。
const double _notesMaxHeight = 96;

class _ForceUpdateDialog extends StatefulWidget {
  final AppRelease release;
  final UpdateDownload download;
  final UpdateInstall install;

  const _ForceUpdateDialog({
    required this.release,
    required this.download,
    required this.install,
  });

  @override
  State<_ForceUpdateDialog> createState() => _ForceUpdateDialogState();
}

class _ForceUpdateDialogState extends State<_ForceUpdateDialog> {
  _Phase _phase = _Phase.idle;
  DownloadProgress _progress = const DownloadProgress(
    received: 0,
    total: 0,
    bytesPerSecond: 0,
  );
  String? _error;
  String? _localPath;
  bool _openFailed = false;

  Future<void> _startDownload() async {
    if (_phase == _Phase.downloading || _phase == _Phase.opening) return;
    setState(() {
      _phase = _Phase.downloading;
      _error = null;
      _openFailed = false;
      _localPath = null;
      _progress = DownloadProgress(
        received: 0,
        total: widget.release.fileSize,
        bytesPerSecond: 0,
      );
    });

    try {
      final path = await widget.download(
        widget.release,
        onProgress: (value) {
          if (!mounted || _phase != _Phase.downloading) return;
          setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      _localPath = path;
      await _openInstaller();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = _friendlyError(e);
        _openFailed = false;
      });
    }
  }

  Future<void> _openInstaller() async {
    final path = _localPath;
    if (path == null) {
      await _startDownload();
      return;
    }
    setState(() {
      _phase = _Phase.opening;
      _error = null;
    });
    try {
      final opened = await widget.install(path);
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _phase = _Phase.error;
          _openFailed = true;
          _error = '无法调起安装器，请到系统设置允许本应用安装应用';
        });
      } else {
        setState(() => _phase = _Phase.awaitingInstall);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _openFailed = true;
        _error = '无法调起安装器，请到系统设置允许本应用安装应用';
      });
    }
  }

  void _retry() {
    if (_openFailed && _localPath != null) {
      _openInstaller();
    } else {
      _startDownload();
    }
  }

  @override
  void dispose() {
    // 弹窗被整棵树销毁（切页、测试拆树）时 showDialog 的 future 不一定会走
    // 到 finally：锁必须在这里一起放开，否则之后再也弹不出更新提示。
    _forceUpdateDialogOpen = false;
    super.dispose();
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.startsWith('Exception: ')) return raw.substring(11);
    if (raw.startsWith('FormatException: ')) return raw.substring(17);
    return '更新失败，请检查网络后重试';
  }

  /// 下载进度：百分比跟着按钮文字走，不再有第二处百分比。
  double? get _buttonProgress {
    switch (_phase) {
      case _Phase.downloading:
        return _progress.total > 0 ? _progress.percent : null;
      case _Phase.opening:
        return 1;
      case _Phase.idle:
      case _Phase.awaitingInstall:
      case _Phase.error:
        return null;
    }
  }

  /// 下载完成那一下：按钮闪一次，然后换文案。
  bool get _justCompleted =>
      _phase == _Phase.opening || _phase == _Phase.awaitingInstall;

  String get _buttonLabel {
    switch (_phase) {
      case _Phase.idle:
        return '立即更新';
      case _Phase.downloading:
        if (_progress.total <= 0) return '下载中…';
        final percent = (_progress.percent * 100).floor().clamp(0, 100);
        return '下载中 $percent%';
      case _Phase.opening:
        return '正在安装…';
      case _Phase.awaitingInstall:
        return '重新打开安装器';
      case _Phase.error:
        return '重试';
    }
  }

  VoidCallback? get _buttonAction {
    switch (_phase) {
      case _Phase.idle:
        return _startDownload;
      case _Phase.error:
        return _retry;
      case _Phase.awaitingInstall:
        return _openInstaller;
      case _Phase.downloading:
      case _Phase.opening:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final notes = release.releaseNotes.trim();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        // 投影留在外面：玻璃表面自己会裁圆角，阴影画不进它的裁剪里。
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadow.dialog,
          ),
          // 玻璃走 standard 档（静态弹窗，不需要 premium 每帧抓纹理）；
          // 没有档位或降到 minimal 时，[AppGlassSurface] 自己退化成不透明的
          // bgSurface。
          child: AppGlassSurface(
            radius: AppRadius.xl,
            padding: const EdgeInsets.all(24),
            requestedQuality: GlassQuality.standard,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('版本更新', style: AppText.titleMedium),
                const SizedBox(height: 4),
                // 版本号与包大小同一行：两个短事实，不需要两行，也不需要
                // 「安装包大小：」这样的标签。
                Text(
                  'v${release.versionName} · ${release.sizeLabel}',
                  style: AppText.caption,
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: _notesMaxHeight),
                    child: SingleChildScrollView(
                      child: Text(
                        notes,
                        style: AppText.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline,
                          size: 15, color: AppColors.danger),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style:
                              AppText.caption.copyWith(color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                UpdateActionButton(
                  label: _buttonLabel,
                  onPressed: _buttonAction,
                  progress: _buttonProgress,
                  completed: _justCompleted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
