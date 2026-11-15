import 'dart:typed_data';

import 'package:album_app/core/api_client.dart';
import 'package:dio/dio.dart';

/// 把所有请求变成「立刻失败的连接错误」或「一条空列表」，测试不碰真实网络。
///
/// 页面里的 catch 分支会照常走：加载失败态或空态，两种都适合断言。
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter({this.json});

  /// 有值时返回 200 + 这段 JSON，否则抛连接错误。
  final String? json;

  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final body = json;
    if (body == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: '测试环境不发真实请求',
      );
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 装上 [FakeHttpAdapter]，并关掉 dio 的超时定时器（否则测试结束时会报
/// 「Timer is still pending」）。返回一个还原函数，测试里 addTearDown 掉。
void Function() installFakeApi({String? json}) {
  final dio = ApiClient.dio;
  final adapter = dio.httpClientAdapter;
  final options = dio.options;
  final connect = options.connectTimeout;
  final receive = options.receiveTimeout;
  final send = options.sendTimeout;

  dio.httpClientAdapter = FakeHttpAdapter(json: json);
  options
    ..connectTimeout = null
    ..receiveTimeout = null
    ..sendTimeout = null;

  return () {
    dio.httpClientAdapter = adapter;
    options
      ..connectTimeout = connect
      ..receiveTimeout = receive
      ..sendTimeout = send;
  };
}
