import 'dart:typed_data';

import 'package:album_app/core/api_client.dart';
import 'package:album_app/core/server_config.dart';
import 'package:album_app/core/url_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingAdapter implements HttpClientAdapter {
  String? lastUrl;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUrl = options.uri.toString();
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds full URL with the fixed internet base and keeps query params',
      () async {
    const base = ServerConfig.defaultWanUrl;
    SharedPreferences.setMockInitialValues({
      'lan_url': 'http://127.0.0.1:9000/album',
      'wan_url': 'http://example.test/album',
      'active_url': 'http://127.0.0.1:9000/album',
    });
    ServerConfig.resetForTest();
    ServerConfig.setNetworkKindForTest('mobile');
    addTearDown(ServerConfig.resetForTest);
    await ServerConfig.init();

    expect(ServerConfig.current, base);
    expect(fullUrl('/files/a.jpg'), '$base/files/a.jpg');

    final adapter = _RecordingAdapter();
    ApiClient.install();
    ApiClient.dio.httpClientAdapter = adapter;
    final response = await ApiClient.dio.get<dynamic>(
      '/api/posts',
      queryParameters: {'cursor': 'x'},
    );
    expect(response.statusCode, 200);
    expect(adapter.lastUrl, '$base/api/posts?cursor=x');
  });
}
