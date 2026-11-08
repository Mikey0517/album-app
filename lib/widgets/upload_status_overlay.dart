import 'dart:io';

import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/radius.dart';
import '../core/design/text_styles.dart';
import '../core/upload_manager.dart';

class UploadStatusOverlay extends StatelessWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const UploadStatusOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    final manager = UploadManager.instance;
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final show = manager.showStatusChip && !manager.sheetOpen;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (show)
              Positioned(
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 88,
                child: _UploadChip(
                  manager: manager,
                  onTap: () => showUploadListSheet(
                    navigatorKey.currentContext ?? context,
                    navigatorKey,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UploadChip extends StatelessWidget {
  final UploadManager manager;
  final VoidCallback onTap;

  const _UploadChip({required this.manager, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uploading = manager.isUploading;
    final failed = manager.failedCount;
    // 有失败项时用红色，并把“失败”写进文案，用户一眼知道点进去能重试。
    final showFailure = !uploading && failed > 0;
    final background = showFailure ? AppColors.danger : AppColors.primary;

    final String label;
    if (uploading) {
      label = failed > 0
          ? '上传中 ${manager.finished}/${manager.total} · $failed 项失败'
          : '上传中 ${manager.finished}/${manager.total}';
    } else if (failed > 0) {
      label = '$failed 项上传失败，点此处理';
    } else {
      label = '上传完成 ${manager.finished}/${manager.total}';
    }

    return Material(
      color: background,
      elevation: 6,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: uploading
                    ? CircularProgressIndicator(
                        value: manager.progress <= 0 ? null : manager.progress,
                        strokeWidth: 2.2,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      )
                    : Icon(
                        showFailure ? Icons.error_outline : Icons.check,
                        size: 18,
                        color: Colors.white,
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppText.caption.copyWith(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showUploadListSheet(
  BuildContext context,
  GlobalKey<NavigatorState> navigatorKey,
) async {
  final manager = UploadManager.instance;
  if (!manager.hasItems) return;
  manager.setSheetOpen(true);
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _UploadListSheet(),
    );
  } finally {
    manager.setSheetOpen(false);
    if (!manager.isUploading) manager.acknowledgeCompleted();
  }
}

class _UploadListSheet extends StatefulWidget {
  const _UploadListSheet();

  @override
  State<_UploadListSheet> createState() => _UploadListSheetState();
}

class _UploadListSheetState extends State<_UploadListSheet> {
  bool _onlyFailed = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    UploadManager.instance.addListener(_closeWhenEmpty);
  }

  @override
  void dispose() {
    UploadManager.instance.removeListener(_closeWhenEmpty);
    super.dispose();
  }

  /// 取消掉最后一项后，列表已经没有内容，直接收起面板。
  void _closeWhenEmpty() {
    if (!mounted || UploadManager.instance.items.isNotEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  void _retryAll() {
    final manager = UploadManager.instance;
    final result = manager.retryAllFailed();
    setState(() {
      if (result.isEmpty) {
        _notice = '没有可重试的项目';
      } else if (result.missingSource > 0 && result.retried > 0) {
        _notice =
            '已重新上传 ${result.retried} 项；${result.missingSource} 项原文件已失效，请重新选择上传';
      } else if (result.missingSource > 0) {
        _notice = '${result.missingSource} 项原文件已失效，请重新选择上传';
      } else {
        _notice = '已重新上传 ${result.retried} 项';
      }
    });
  }

  void _retryOne(UploadItem item) {
    final manager = UploadManager.instance;
    final queued = manager.retry(item);
    if (!queued) {
      setState(() => _notice = '「${item.name}」原文件已失效，请重新选择上传');
    } else if (_notice != null) {
      setState(() => _notice = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = UploadManager.instance;
    return DraggableScrollableSheet(
      initialChildSize: 0.66,
      minChildSize: 0.32,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          child: AnimatedBuilder(
            animation: manager,
            builder: (context, _) {
              final all = manager.items;
              final visible = _onlyFailed
                  ? all.where((item) => item.failed).toList(growable: false)
                  : all;
              return Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 4, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('上传列表', style: AppText.titleMedium),
                        ),
                        Text(
                          manager.failedCount > 0
                              ? '${manager.finished}/${manager.total} · ${manager.failedCount} 项失败'
                              : '${manager.finished}/${manager.total}',
                          style: AppText.caption,
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'clear') {
                              manager.clearFinished();
                              setState(() => _notice = null);
                            } else if (value == 'cancelAll') {
                              manager.cancelAll();
                              setState(() => _notice = null);
                            }
                          },
                          tooltip: '更多',
                          icon: const Icon(Icons.more_horiz, size: 20),
                          itemBuilder: (context) => [
                            PopupMenuItem<String>(
                              value: 'cancelAll',
                              enabled: manager.isUploading,
                              child: const Text('取消全部上传'),
                            ),
                            PopupMenuItem<String>(
                              value: 'clear',
                              enabled: !manager.isUploading,
                              child: const Text('清空记录'),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _onlyFailed,
                          onChanged: (value) {
                            setState(() => _onlyFailed = value == true);
                          },
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        const Text('仅显示失败', style: AppText.caption),
                        const Spacer(),
                        if (manager.failedCount > 0)
                          TextButton(
                            onPressed: _retryAll,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              minimumSize: const Size(0, 32),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('全部重试'),
                          ),
                        const SizedBox(width: 8),
                        if (visible.isNotEmpty)
                          Text(
                            _onlyFailed
                                ? '${visible.length} 项失败'
                                : '${visible.length} 项',
                            style: AppText.caption,
                          ),
                      ],
                    ),
                  ),
                  if (_notice != null) _NoticeBanner(message: _notice!),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: Text(
                              _emptyText(manager),
                              style: AppText.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            // 固定行高 + builder：大量媒体时只构建可见行。
                            itemExtent: 66,
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              return SizedBox(
                                height: 66,
                                child: _UploadItemTile(
                                  item: item,
                                  onRetry: () => _retryOne(item),
                                  onCancel: () {
                                    manager.cancel(item);
                                    setState(() => _notice = null);
                                  },
                                  onRemove: () {
                                    manager.removeItem(item);
                                    setState(() => _notice = null);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                  if (manager.isUploading)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 14,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '并行 ${UploadManager.maxConcurrentUploads} 个上传 · '
                              '期间保持屏幕常亮，避免锁屏中断',
                              style: AppText.caption.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  String _emptyText(UploadManager manager) {
    if (_onlyFailed) {
      return manager.isUploading ? '失败项已重新排队，正在上传…' : '没有失败项';
    }
    return manager.isUploading ? '正在准备上传…' : '暂无上传项';
  }
}

class _NoticeBanner extends StatelessWidget {
  final String message;

  const _NoticeBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadItemTile extends StatelessWidget {
  final UploadItem item;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  const _UploadItemTile({
    required this.item,
    required this.onRetry,
    required this.onCancel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = item.failed
        ? AppColors.danger
        : item.done
            ? AppColors.success
            : AppColors.primary;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: item.sourceCleaned
                        ? Container(
                            color: AppColors.mediaPlaceholder,
                            child: Icon(Icons.check_circle_outline,
                                size: 20, color: AppColors.success),
                          )
                        : item.isVideo
                            ? Container(
                                color: AppColors.mediaPlaceholder,
                                child: Icon(Icons.videocam_outlined,
                                    size: 22, color: AppColors.textSecondary),
                              )
                            : Image.file(
                                File(item.path),
                                fit: BoxFit.cover,
                                cacheWidth: 120,
                                errorBuilder: (context, error, stack) =>
                                    Container(
                                  color: AppColors.mediaPlaceholder,
                                  child: Icon(Icons.image_outlined,
                                      size: 20, color: AppColors.textTertiary),
                                ),
                              ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                          )),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          value: item.done || item.failed ? 1 : item.progress,
                          minHeight: 3,
                          backgroundColor: AppColors.borderLight,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: color),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (item.sourceMissing)
                  TextButton(
                    onPressed: onRemove,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('移除'),
                  )
                else if (item.canRetry)
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('重试'),
                  )
                else if (!item.done)
                  IconButton(
                    onPressed: onCancel,
                    tooltip: '取消上传',
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  )
                else
                  Icon(
                    item.done
                        ? Icons.check_circle_outline
                        : Icons.cloud_upload_outlined,
                    size: 18,
                    color: color,
                  ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.divider.withOpacity(0.7)),
      ],
    );
  }
}
