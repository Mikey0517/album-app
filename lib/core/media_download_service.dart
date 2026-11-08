import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media.dart';
import 'url_utils.dart';

class MediaDownloadException implements Exception {
  final String message;

  const MediaDownloadException(this.message);

  @override
  String toString() => message;
}

/// 下载原图/视频并写入系统相册的“家庭相册”目录。
class MediaDownloadService {
  static const String albumName = '家庭相册';

  static Future<void> save(
    Media media, {
    void Function(double? progress)? onProgress,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 10),
      ),
    );
    final url = fullUrl(media.url);
    final extension = _extensionOf(url, media.isVideo);
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/familyalbum_${media.id}_'
      '${DateTime.now().microsecondsSinceEpoch}$extension',
    );

    try {
      await dio.download(
        url,
        file.path,
        onReceiveProgress: (received, total) {
          if (onProgress == null) return;
          onProgress(total > 0 ? (received / total).clamp(0.0, 1.0) : null);
        },
      );
      await _ensureGalleryAccess();
      if (media.isVideo) {
        await Gal.putVideo(file.path, album: albumName);
      } else {
        await Gal.putImage(file.path, album: albumName);
      }
    } on GalException catch (e) {
      throw MediaDownloadException(_galMessage(e.type));
    } finally {
      dio.close(force: true);
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // 清理临时文件失败不影响已经保存到相册的内容。
      }
    }
  }

  static Future<void> _ensureGalleryAccess() async {
    try {
      if (await Gal.hasAccess(toAlbum: true)) return;
      final granted = await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        throw const MediaDownloadException('没有相册写入权限');
      }
    } on GalException catch (e) {
      throw MediaDownloadException(_galMessage(e.type));
    }
  }

  static String _extensionOf(String url, bool isVideo) {
    try {
      final name = Uri.parse(url).pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot >= 0 && name.length - dot <= 6) {
        return name.substring(dot).toLowerCase();
      }
    } catch (_) {
      // 使用默认扩展名。
    }
    return isVideo ? '.mp4' : '.jpg';
  }

  static String _galMessage(GalExceptionType type) {
    return switch (type) {
      GalExceptionType.accessDenied => '没有相册写入权限',
      GalExceptionType.notEnoughSpace => '手机存储空间不足',
      GalExceptionType.notSupportedFormat => '系统不支持该文件格式',
      GalExceptionType.unexpected => '保存到相册失败',
    };
  }
}
