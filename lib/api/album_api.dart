import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/server_config.dart';
import '../core/upload_errors.dart';
import '../models/album.dart';
import '../models/album_share.dart';
import '../models/media.dart';

class AlbumDetail {
  final Album album;
  final List<Media> items;

  const AlbumDetail({required this.album, required this.items});
}

class AlbumApi {
  static final Dio _dio = ApiClient.dio;

  static Future<List<Album>> list() async {
    final response = await _dio.get<dynamic>('/api/albums');
    final map = _asMap(response.data);
    final raw = map['items'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Album.fromJson)
        .toList(growable: false);
  }

  /// [isPrivate] 为 true 时创建私人相册（仅自己可见，可分享给指定用户）。
  static Future<Album> create(String title, {bool isPrivate = false}) async {
    final response = await _dio.post<dynamic>(
      '/api/albums',
      data: {'title': title, 'is_private': isPrivate},
    );
    return Album.fromJson(_asMap(response.data));
  }

  /// 私人相册当前分享名单。
  static Future<List<AlbumShare>> shares(int albumId) async {
    final response = await _dio.get<dynamic>('/api/albums/$albumId/shares');
    return _shares(response.data);
  }

  /// 按登录 ID 分享给某个用户并指定权限，返回最新名单。
  static Future<List<AlbumShare>> share(
    int albumId,
    String userId, {
    String role = 'viewer',
  }) async {
    final response = await _dio.post<dynamic>(
      '/api/albums/$albumId/shares',
      data: {'user_id': userId, 'role': role},
    );
    return _shares(response.data);
  }

  /// 修改某个已分享用户的权限。
  static Future<List<AlbumShare>> updateShareRole(
    int albumId,
    String userId,
    String role,
  ) async {
    final response = await _dio.patch<dynamic>(
      '/api/albums/$albumId/shares/${Uri.encodeComponent(userId)}',
      data: {'role': role},
    );
    return _shares(response.data);
  }

  /// 取消分享，返回最新名单。
  static Future<List<AlbumShare>> unshare(int albumId, String userId) async {
    final response = await _dio.delete<dynamic>(
      '/api/albums/$albumId/shares/${Uri.encodeComponent(userId)}',
    );
    return _shares(response.data);
  }

  static List<AlbumShare> _shares(dynamic data) {
    final raw = _asMap(data)['items'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AlbumShare.fromJson)
        .toList(growable: false);
  }

  static Future<Album> rename(int albumId, String title) async {
    final response = await _dio.patch<dynamic>(
      '/api/albums/$albumId',
      data: {'title': title},
    );
    return Album.fromJson(_asMap(response.data));
  }

  static Future<Album> setCover(int albumId, int mediaId) async {
    final response = await _dio.patch<dynamic>(
      '/api/albums/$albumId',
      data: {'cover_media_id': mediaId},
    );
    return Album.fromJson(_asMap(response.data));
  }

  static Future<void> delete(int albumId) async {
    await _dio.delete<dynamic>('/api/albums/$albumId');
  }

  static Future<AlbumDetail> detail(int albumId) async {
    final response = await _dio.get<dynamic>('/api/albums/$albumId');
    final map = _asMap(response.data);
    final album = Album.fromJson(
      map['album'] as Map<String, dynamic>? ?? const {},
    );
    final raw = map['items'] as List<dynamic>? ?? const [];
    final items = raw
        .whereType<Map<String, dynamic>>()
        .map(Media.fromJson)
        .toList(growable: false);
    return AlbumDetail(album: album, items: items);
  }

  /// 上传超过这个时间没有任何字节进展，就认为连接已经死掉。
  /// 锁屏/切网后，TCP 连接往往既不报错也不返回数据，光靠 30 分钟超时
  /// 会让队列一直卡在“上传中”，后面的重试按钮点了也没有反应。
  @visibleForTesting
  static Duration stallTimeout = const Duration(seconds: 45);

  /// 重试间隔，测试时可缩短。
  @visibleForTesting
  static Duration Function(int attempt) retryDelay = (int attempt) =>
      Duration(milliseconds: 1500 * (attempt + 1) * (attempt + 1));

  static const int _maxUploadAttempts = 4;

  static Future<List<Media>> upload(
    int albumId,
    List<XFile> files, {
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    // 缓存目录里的副本可能已被系统清理，先明确报错，别让用户重试一个
    // 永远不可能成功的任务。
    for (final file in files) {
      if (!await File(file.path).exists()) {
        throw UploadSourceMissingException(file.path);
      }
    }

    DioException? lastError;
    for (var attempt = 0; attempt < _maxUploadAttempts; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        throw const UploadCanceledException();
      }
      // 每次尝试用独立令牌，页面的“取消”会转发给它，看门狗只取消自己的请求。
      final attemptToken = CancelToken();
      cancelToken?.whenCancel.then((_) {
        if (!attemptToken.isCancelled) attemptToken.cancel('user');
      });
      Timer? watchdog;
      var stalled = false;

      void armWatchdog() {
        watchdog?.cancel();
        watchdog = Timer(stallTimeout, () {
          stalled = true;
          if (!attemptToken.isCancelled) {
            attemptToken.cancel('stalled');
          }
        });
      }

      void disarmWatchdog() {
        watchdog?.cancel();
        watchdog = null;
      }

      try {
        final form = await _buildForm(files);
        armWatchdog();
        // 单次请求可能包含大视频，给出比普通 API 更宽松的上传/处理超时。
        final response = await _dio.post<dynamic>(
          '/api/albums/$albumId/media',
          data: form,
          options: Options(
            extra: const {'noRetry': true},
            sendTimeout: const Duration(minutes: 30),
            receiveTimeout: const Duration(minutes: 30),
          ),
          cancelToken: attemptToken,
          onSendProgress: (sent, total) {
            if (total > 0 && sent >= total) {
              // 字节发完，进入服务端“处理中”阶段：大视频处理耗时较长，
              // 这里只靠发送进度判死会误杀，超时交给 receiveTimeout 兜底。
              disarmWatchdog();
            } else {
              armWatchdog();
            }
            onSendProgress?.call(sent, total);
          },
        );
        final map = _asMap(response.data);
        final raw = map['items'] as List<dynamic>? ?? const [];
        return raw
            .whereType<Map<String, dynamic>>()
            .map(Media.fromJson)
            .toList(growable: false);
      } on DioException catch (e) {
        if (cancelToken?.isCancelled ?? false) {
          throw const UploadCanceledException();
        }
        lastError = stalled ? _stalledError(e) : e;
        final retryable = stalled || _isRetryable(e);
        if (attempt == _maxUploadAttempts - 1 || !retryable) {
          if (stalled) throw lastError;
          rethrow;
        }
        onSendProgress?.call(0, 1);
        await ServerConfig.trySwitchFallback();
        await Future<void>.delayed(retryDelay(attempt));
      } on FileSystemException catch (e) {
        throw UploadSourceMissingException(e.path ?? files.first.path);
      } finally {
        watchdog?.cancel();
      }
    }
    throw lastError!;
  }

  /// 把“长时间无进展”包装成可重试的超时错误，界面提示也更准确。
  static DioException _stalledError(DioException source) {
    return DioException(
      requestOptions: source.requestOptions,
      type: DioExceptionType.sendTimeout,
      error: source.error,
      message: '上传长时间无响应',
    );
  }

  static Future<FormData> _buildForm(List<XFile> files) async {
    final form = FormData();
    for (final file in files) {
      form.files.add(
        MapEntry(
          'files',
          await MultipartFile.fromFile(file.path, filename: file.name),
        ),
      );
    }
    return form;
  }

  static bool _isRetryable(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.badCertificate:
        return true;
      case DioExceptionType.cancel:
        // 主动取消不重试；锁屏超时触发的取消在调用处已转成 sendTimeout。
        return false;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        return status >= 500 || status == 408 || status == 429;
      case DioExceptionType.unknown:
        // 锁屏/切网后连接被重置，dio 常把 SocketException 包成 unknown。
        final inner = error.error;
        return inner is SocketException ||
            inner is HttpException ||
            inner is TlsException ||
            inner is HandshakeException;
      case DioExceptionType.transformTimeout:
        return false;
    }
  }

  static Future<void> removeMedia(int albumId, int mediaId) async {
    await _dio.delete<dynamic>('/api/albums/$albumId/media/$mediaId');
  }

  static Future<void> moveMedia(
    int sourceAlbumId,
    int targetAlbumId,
    int mediaId,
  ) async {
    await _dio.post<dynamic>(
      '/api/albums/$sourceAlbumId/media/$mediaId/move',
      data: {'target_album_id': targetAlbumId},
    );
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return const {};
  }
}
