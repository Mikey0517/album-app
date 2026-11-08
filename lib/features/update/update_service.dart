import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/cache_service.dart';

import '../../core/server_config.dart';
import '../../core/url_utils.dart';
import '../../models/app_release.dart';
import 'download_progress.dart';

class UpdateService {
  /// 检查失败（断网 / 5xx / 超时 / 404）一律返回 null，不阻塞 App 启动。
  static Future<AppRelease?> check() async {
    // iOS 不能安装 APK，更新检查直接跳过（iPad 上不会弹强制更新）。
    if (!Platform.isAndroid) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      final baseUrl = ServerConfig.current;
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );
      try {
        final response = await dio.get<dynamic>(
          '$baseUrl/api/app/latest',
          options: Options(
              validateStatus: (status) => status == 200 || status == 404),
        );
        if (response.statusCode == 404) return null;
        final data = response.data;
        if (data is! Map) return null;
        final release = AppRelease.fromJson(Map<String, dynamic>.from(data));
        if (release.versionCode <= currentCode) return null;
        return release;
      } finally {
        dio.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  /// 下载 + SHA-256 校验，返回本地 APK 路径；失败时抛异常。
  static Future<String> download(
    AppRelease release, {
    required void Function(DownloadProgress) onProgress,
  }) async {
    if (!RegExp(r'^[0-9A-Za-z._-]+\.apk$').hasMatch(release.filename) ||
        release.filename.contains('..')) {
      throw const FormatException('服务器返回了非法的安装包文件名');
    }
    final tempRoot = await getTemporaryDirectory();
    final dir = Directory('${tempRoot.path}/album_updates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final savePath = '${dir.path}/${release.filename}';
    final file = File(savePath);
    if (await file.exists()) {
      await file.delete();
    }

    final url = fullUrl(
      '/api/app/download/${Uri.encodeComponent(release.filename)}',
    );
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 10),
      ),
    );

    // 下载安装包期间不要被“清理缓存”删掉。
    CacheService.updating = true;

    int lastBytes = 0;
    DateTime lastTime = DateTime.now();
    double lastSpeed = 0;
    int lastTotal = release.fileSize;
    try {
      await dio.download(
        url,
        savePath,
        deleteOnError: true,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
        onReceiveProgress: (received, total) {
          final now = DateTime.now();
          final elapsed = now.difference(lastTime).inMilliseconds;
          if (elapsed >= 500) {
            lastSpeed = (received - lastBytes) * 1000 / elapsed;
            lastBytes = received;
            lastTime = now;
          }
          lastTotal = total > 0 ? total : release.fileSize;
          onProgress(
            DownloadProgress(
              received: received,
              total: lastTotal,
              bytesPerSecond: lastSpeed,
            ),
          );
        },
      );
    } on DioException catch (e) {
      if (await file.exists()) await file.delete();
      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        throw Exception('下载超时，请检查网络后重试');
      }
      final status = e.response?.statusCode;
      if (status != null) {
        throw Exception('下载失败（HTTP $status）');
      }
      throw Exception('下载失败，请检查网络后重试');
    } catch (e) {
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      CacheService.updating = false;
      dio.close(force: true);
    }

    if (!await file.exists() || await file.length() == 0) {
      throw Exception('下载文件为空');
    }
    if (release.sha256.isNotEmpty) {
      final actual = await _sha256(file);
      if (actual.toLowerCase() != release.sha256.toLowerCase()) {
        await file.delete();
        throw Exception('安装包校验失败，请重新下载');
      }
    }
    return savePath;
  }

  static Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
