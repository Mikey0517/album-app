import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/shadow.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';
import '../../models/app_release.dart';
import 'download_progress.dart';
import 'update_service.dart';

bool _forceUpdateDialogOpen = false;

Future<void> showForceUpdateDialog(
  BuildContext context,
  AppRelease release,
) async {
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
          child: _ForceUpdateDialog(release: release),
        );
      },
    );
  } finally {
    _forceUpdateDialogOpen = false;
  }
}

enum _Phase { idle, downloading, opening, awaitingInstall, error }

class _ForceUpdateDialog extends StatefulWidget {
  final AppRelease release;

  const _ForceUpdateDialog({required this.release});

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
      final path = await UpdateService.download(
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
      final result = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      if (!mounted) return;
      if (result.type != ResultType.done) {
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

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.startsWith('Exception: ')) return raw.substring(11);
    if (raw.startsWith('FormatException: ')) return raw.substring(17);
    return '更新失败，请检查网络后重试';
  }

  String get _buttonLabel {
    switch (_phase) {
      case _Phase.idle:
        return '立即更新';
      case _Phase.downloading:
        return '下载中…';
      case _Phase.opening:
        return '正在打开安装器…';
      case _Phase.awaitingInstall:
        return '重新打开安装器';
      case _Phase.error:
        return '重试';
    }
  }

  bool get _buttonEnabled =>
      _phase == _Phase.idle ||
      _phase == _Phase.error ||
      _phase == _Phase.awaitingInstall;

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
    final downloading = _phase == _Phase.downloading;
    final progress = _progress;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 440,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: AppShadow.dialog,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      size: 21,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('版本更新', style: AppText.titleMedium),
                        const SizedBox(height: 2),
                        Text('发现新版本 v${release.versionName}',
                            style: AppText.caption),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '必须更新',
                      style: AppText.caption.copyWith(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '需更新到 v${release.versionName} 后才能继续使用。',
                style: AppText.body,
              ),
              if (release.releaseNotes.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      release.releaseNotes.trim(),
                      style: AppText.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(Icons.archive_outlined,
                      size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: 5),
                  Text(
                    '安装包大小：${release.sizeLabel}',
                    style: AppText.caption,
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _buildStatus(progress),
              ),
              if (_phase == _Phase.error && _error != null) ...[
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
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _buttonEnabled ? _buttonAction : null,
                  child: downloading || _phase == _Phase.opening
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_buttonLabel),
                          ],
                        )
                      : Text(_buttonLabel),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Center(
                child: Text(
                  '安装完成后请重新打开应用',
                  style: AppText.caption,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(DownloadProgress progress) {
    if (_phase == _Phase.idle || _phase == _Phase.error) {
      return const SizedBox.shrink();
    }
    if (_phase == _Phase.awaitingInstall) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 16, color: AppColors.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '下载完成并通过校验，请在系统安装器中确认安装',
                style: AppText.caption.copyWith(color: AppColors.success),
              ),
            ),
          ],
        ),
      );
    }
    if (_phase == _Phase.opening) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.lg),
        child: Text('正在打开系统安装器…', style: AppText.caption),
      );
    }

    final percent = (progress.percent * 100).floor().clamp(0, 100);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress.received > 0 && progress.total > 0
                  ? progress.percent
                  : null,
              backgroundColor: AppColors.primaryLight,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                '$percent%',
                style: AppText.body.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${progress.receivedLabel} / ${progress.totalLabel}',
                  style: AppText.caption,
                ),
              ),
              Text(progress.speedLabel, style: AppText.caption),
            ],
          ),
          const SizedBox(height: 2),
          Text(progress.etaLabel, style: AppText.caption),
        ],
      ),
    );
  }
}
