import 'package:flutter/material.dart';

import '../../core/design/text_styles.dart';
import '../../core/media_download_service.dart';
import '../../models/media.dart';

class BatchDownloadResult {
  final int success;
  final int failed;

  const BatchDownloadResult({required this.success, required this.failed});
}

class _BatchDownloadProgress {
  final int done;
  final int total;
  final double current;

  const _BatchDownloadProgress(this.done, this.total, this.current);
}

/// 顺序下载一组媒体，并显示不可关闭的进度框。
Future<BatchDownloadResult> downloadMediaBatch({
  required BuildContext context,
  required List<Media> medias,
}) async {
  final progress = ValueNotifier<_BatchDownloadProgress>(
    _BatchDownloadProgress(0, medias.length, 0),
  );
  final dialogFuture = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _BatchDownloadDialog(progress: progress),
  );
  await Future<void>.delayed(const Duration(milliseconds: 50));

  var success = 0;
  var failed = 0;
  try {
    for (var i = 0; i < medias.length; i++) {
      try {
        await MediaDownloadService.save(
          medias[i],
          onProgress: (value) {
            progress.value = _BatchDownloadProgress(
              i,
              medias.length,
              value ?? 0,
            );
          },
        );
        success++;
      } catch (_) {
        failed++;
      }
      progress.value = _BatchDownloadProgress(i + 1, medias.length, 0);
    }
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialogFuture;
    progress.dispose();
  }
  return BatchDownloadResult(success: success, failed: failed);
}

class _BatchDownloadDialog extends StatelessWidget {
  final ValueNotifier<_BatchDownloadProgress> progress;

  const _BatchDownloadDialog({required this.progress});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在保存到相册'),
        content: SizedBox(
          width: 280,
          child: ValueListenableBuilder<_BatchDownloadProgress>(
            valueListenable: progress,
            builder: (context, value, child) {
              final total = value.total;
              final index = total == 0 ? 0 : (value.done + 1).clamp(1, total);
              final overall = total == 0
                  ? 0.0
                  : ((value.done + value.current) / total).clamp(0.0, 1.0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('第 $index / $total 项', style: AppText.body),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: overall,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${(overall * 100).round()}%', style: AppText.caption),
                  const SizedBox(height: 4),
                  const Text(
                    '请保持 App 在前台，完成后会提示保存结果。',
                    style: AppText.caption,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
