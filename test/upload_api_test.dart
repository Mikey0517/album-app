import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/api_client.dart';
import 'package:album_app/core/upload_errors.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// 第一次上传挂起（模拟锁屏后连接卡死），取消令牌触发后失败，第二次成功。
/// 请求体已经发完、服务端还在处理（大视频转码/缩略图）时不能误判为卡死。
class _SlowProcessingAdapter implements HttpClientAdapter {
  int attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts += 1;
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return ResponseBody.fromString(
      jsonEncode({'items': <dynamic>[]}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StallThenOkAdapter implements HttpClientAdapter {
  int attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts += 1;
    if (attempts == 1) {
      // 不消费请求流：模拟发送中途卡死，进度不再前进。
      final completer = Completer<ResponseBody>();
      cancelFuture?.then((_) {
        if (!completer.isCompleted) {
          completer.completeError(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          );
        }
      });
      return completer.future;
    }
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    return ResponseBody.fromString(
      jsonEncode({'items': <dynamic>[]}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late HttpClientAdapter originalAdapter;
  late String originalBaseUrl;
  late Duration originalStallTimeout;
  late Duration Function(int) originalRetryDelay;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('album_upload_api_test');
    final options = ApiClient.dio.options;
    originalAdapter = ApiClient.dio.httpClientAdapter;
    originalBaseUrl = options.baseUrl;
    options.baseUrl = 'http://upload.test';
    originalStallTimeout = AlbumApi.stallTimeout;
    originalRetryDelay = AlbumApi.retryDelay;
    AlbumApi.stallTimeout = const Duration(milliseconds: 100);
    AlbumApi.retryDelay = (_) => Duration.zero;
  });

  tearDown(() {
    ApiClient.dio.httpClientAdapter = originalAdapter;
    ApiClient.dio.options.baseUrl = originalBaseUrl;
    AlbumApi.stallTimeout = originalStallTimeout;
    AlbumApi.retryDelay = originalRetryDelay;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // 忽略临时目录清理失败。
    }
  });

  test('上传长时间没有进展会被中断并自动重试', () async {
    final file = File('${tmp.path}/stall.mp4')
      ..writeAsBytesSync(List<int>.filled(2048, 7));
    final adapter = _StallThenOkAdapter();
    ApiClient.dio.httpClientAdapter = adapter;

    final started = DateTime.now();
    final result = await AlbumApi.upload(
      1,
      [XFile(file.path, name: 'stall.mp4')],
    );

    expect(result, isEmpty);
    expect(adapter.attempts, 2, reason: '卡死后应自动重试一次');
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 20)),
      reason: '不能被 30 分钟超时卡住',
    );
  });

  test('请求体发完后服务端处理较慢不会被当成卡死', () async {
    final file = File('${tmp.path}/slow.mp4')
      ..writeAsBytesSync(List<int>.filled(2048, 7));
    final adapter = _SlowProcessingAdapter();
    ApiClient.dio.httpClientAdapter = adapter;

    final result = await AlbumApi.upload(
      1,
      [XFile(file.path, name: 'slow.mp4')],
    );

    expect(result, isEmpty);
    expect(adapter.attempts, 1, reason: '处理阶段不应被发送进度看门狗中断');
  });

  test('源文件不存在时抛出明确的“请重新上传”异常', () async {
    ApiClient.dio.httpClientAdapter = _StallThenOkAdapter();

    await expectLater(
      AlbumApi.upload(
        1,
        [XFile('${tmp.path}/missing.jpg', name: 'missing.jpg')],
      ),
      throwsA(isA<UploadSourceMissingException>()),
    );
  });

  test('失败分类：锁屏断网可重试，源文件失效不可重试', () {
    final options = RequestOptions(path: '/api/albums/1/media');
    expect(
      classifyUploadFailure(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      )),
      UploadFailureKind.network,
    );
    expect(
      classifyUploadFailure(DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: const SocketException('Connection reset by peer'),
      )),
      UploadFailureKind.network,
    );
    expect(
      classifyUploadFailure(const UploadSourceMissingException('/tmp/a.jpg')),
      UploadFailureKind.sourceMissing,
    );
    expect(
      classifyUploadFailure(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<void>(requestOptions: options, statusCode: 413),
      )),
      UploadFailureKind.server,
    );
  });
}
