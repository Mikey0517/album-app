import 'dart:io';

import 'package:album_app/core/upload_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

DioException _networkError() => DioException(
      requestOptions: RequestOptions(path: '/api/albums/1/media'),
      type: DioExceptionType.connectionError,
    );

Future<void> _waitUntil(bool Function() condition,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('等待超时');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manager = UploadManager.instance;
  late Directory tmp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('album_source_delete_test');
    manager.resetForTest();
  });

  tearDown(() {
    manager.resetForTest();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // 忽略清理失败。
    }
  });

  File makeFile(String name) =>
      File('${tmp.path}/$name')..writeAsBytesSync([1, 2, 3]);

  test('只取上传成功且带相册 URI 的条目，并且只取一次', () async {
    final ok = makeFile('ok.jpg');
    final bad = makeFile('bad.jpg');
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      if (files.first.name == 'bad.jpg') throw _networkError();
      return const [];
    };

    manager.enqueue(
      albumId: 1,
      files: [
        XFile(ok.path, name: 'ok.jpg'),
        XFile(bad.path, name: 'bad.jpg'),
      ],
      sourceUris: ['content://media/1', 'content://media/2'],
    );
    await _waitUntil(
      () => manager.items.every((item) => item.done || item.failed) &&
          !manager.isUploading,
    );

    final taken = manager.takeCompletedWithSource(albumId: 1);
    expect(taken.length, 1, reason: '失败的那条不能删原图');
    expect(taken.single.sourceUri, 'content://media/1');
    expect(manager.takeCompletedWithSource(albumId: 1), isEmpty,
        reason: '同一条只提示一次');
  });

  test('按相册过滤，别的相册的原图不会被带出来', () async {
    final file = makeFile('a.jpg');
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async => const [];

    manager.enqueue(
      albumId: 7,
      files: [XFile(file.path, name: 'a.jpg')],
      sourceUris: ['content://media/7'],
    );
    await _waitUntil(() => manager.items.single.done && !manager.isUploading);

    expect(manager.takeCompletedWithSource(albumId: 8), isEmpty);
    expect(manager.takeCompletedWithSource(albumId: 7).length, 1);
  });

  test('没有相册 URI 的条目不会触发删除提示', () async {
    final file = makeFile('no_uri.jpg');
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async => const [];

    manager.enqueue(
      albumId: 1,
      files: [XFile(file.path, name: 'no_uri.jpg')],
    );
    await _waitUntil(() => manager.items.single.done && !manager.isUploading);

    expect(manager.takeCompletedWithSource(albumId: 1), isEmpty);
  });
}
