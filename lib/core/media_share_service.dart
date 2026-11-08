import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/media.dart';
import 'design/text_styles.dart';
import 'url_utils.dart';

/// 下载选中的原图/视频到临时目录，调起系统分享面板后清理。
Future<void> shareMedia(BuildContext context, List<Media> medias) async {
  if (medias.isEmpty) return;

  final progress = ValueNotifier<double>(0);
  final dialogFuture = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('正在准备分享'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, value, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${(value * 100).round()}%', style: AppText.caption),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: value),
                ],
              );
            },
          ),
        ),
      );
    },
  );
  await Future<void>.delayed(const Duration(milliseconds: 30));

  final directory = await getTemporaryDirectory();
  final folder = Directory(
    '${directory.path}/album_share_${DateTime.now().microsecondsSinceEpoch}',
  );
  await folder.create(recursive: true);
  final files = <XFile>[];
  var dialogClosed = false;
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
    ),
  );

  try {
    for (var i = 0; i < medias.length; i++) {
      final media = medias[i];
      final file = File(
        '${folder.path}/${media.id}${_extensionOf(media)}',
      );
      await dio.download(
        fullUrl(media.url),
        file.path,
        onReceiveProgress: (received, total) {
          final fraction = total > 0 ? received / total : 0.0;
          progress.value = ((i + fraction) / medias.length).clamp(0.0, 1.0);
        },
      );
      files.add(XFile(file.path));
    }
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      dialogClosed = true;
    }
    await dialogFuture;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await Share.shareXFiles(files, text: '来自家庭相册');
  } catch (e) {
    if (!dialogClosed && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      dialogClosed = true;
    }
    await dialogFuture;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享失败，请重试')),
      );
    }
  } finally {
    dio.close(force: true);
    try {
      await folder.delete(recursive: true);
    } catch (_) {
      // 清理失败不影响分享。
    }
  }
}

String _extensionOf(Media media) {
  try {
    final name = Uri.parse(media.url).pathSegments.last;
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && name.length - dot <= 6) {
      return name.substring(dot).toLowerCase();
    }
  } catch (_) {
    // 默认扩展名。
  }
  return media.isVideo ? '.mp4' : '.jpg';
}
