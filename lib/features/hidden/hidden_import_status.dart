import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';
import '../../core/hidden_space/hidden_import_manager.dart';

/// 隐藏空间里的「上传中 x/y」状态条：和相册上传那颗胶囊同一套配色/尺寸/文案。
///
/// 它只画在隐藏空间页面里，所以退出页面就看不到；队列本身挂在进程上，
/// 再进来还能看到进度。
class HiddenImportStatusChip extends StatelessWidget {
  final VoidCallback onTap;

  const HiddenImportStatusChip({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final manager = HiddenImportManager.instance;
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        if (!manager.showStatusChip) return const SizedBox.shrink();
        final uploading = manager.isUploading;
        final failed = manager.failedCount;
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
                            value:
                                manager.progress <= 0 ? null : manager.progress,
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
      },
    );
  }
}

/// 打开隐藏空间的上传列表：版式与相册的上传列表一致（把手 + 标题 + 计数 + 列表）。
Future<void> showHiddenImportSheet(BuildContext context) async {
  final manager = HiddenImportManager.instance;
  if (!manager.hasItems) return;
  manager.setSheetOpen(true);
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _HiddenImportSheet(),
    );
  } finally {
    manager.setSheetOpen(false);
    manager.acknowledgeCompleted();
  }
}

class _HiddenImportSheet extends StatelessWidget {
  const _HiddenImportSheet();

  @override
  Widget build(BuildContext context) {
    final manager = HiddenImportManager.instance;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
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
                        if (!manager.isUploading && manager.hasItems)
                          PopupMenuButton<String>(
                            onSelected: (_) => manager.clearFinished(),
                            tooltip: '更多',
                            icon: const Icon(Icons.more_horiz, size: 20),
                            itemBuilder: (context) => const [
                              PopupMenuItem<String>(
                                value: 'clear',
                                child: Text('清空记录'),
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
                  const SizedBox(height: 4),
                  Expanded(
                    child: manager.items.isEmpty
                        ? const Center(
                            child: Text(
                              '没有记录',
                              style: AppText.caption,
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: manager.items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) => _ItemTile(
                              item: manager.items[index],
                            ),
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
}

class _ItemTile extends StatelessWidget {
  final HiddenImportItem item;

  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final path = item.path;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 44,
              height: 44,
              child: path != null && item.isImage
                  ? Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _icon(item),
                    )
                  : _icon(item),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: item.done
                          ? const SizedBox.shrink()
                          : LinearProgressIndicator(
                              value: item.progress <= 0 ? null : item.progress,
                              minHeight: 3,
                              backgroundColor: AppColors.divider,
                            ),
                    ),
                    if (!item.done) const SizedBox(width: 8),
                    Text(
                      item.failed
                          ? '失败'
                          : item.done
                              ? '已完成'
                              : item.status,
                      style: AppText.caption.copyWith(
                        color: item.failed ? AppColors.danger : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(formatBytes(item.source.size), style: AppText.caption),
        ],
      ),
    );
  }

  Widget _icon(HiddenImportItem item) {
    final icon = item.isVideo
        ? Icons.videocam_outlined
        : item.isImage
            ? Icons.image_outlined
            : Icons.insert_drive_file_outlined;
    return Container(
      color: AppColors.mediaPlaceholder,
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: AppColors.textTertiary),
    );
  }
}
