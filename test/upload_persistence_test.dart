import 'dart:async';
import 'dart:io';

import 'package:album_app/core/picked_media_cleaner.dart';
import 'package:album_app/core/upload_errors.dart';
import 'package:album_app/core/upload_manager.dart';
import 'package:album_app/core/upload_queue_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitUntil(
  bool Function() condition, {
  String reason = '',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('等待超时：$reason');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manager = UploadManager.instance;
  late Directory tmp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('album_upload_persist_test');
    Directory('${tmp.path}/picked_media').createSync();
    PickedMediaCleaner.rootsOverride = () async => [tmp.path];
    manager.resetForTest();
  });

  tearDown(() {
    manager.resetForTest();
    PickedMediaCleaner.rootsOverride = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // 忽略临时目录清理失败。
    }
  });

  File pickedFile(String name) {
    return File('${tmp.path}/picked_media/$name')
      ..writeAsBytesSync([1, 2, 3, 4]);
  }

  test('App 被杀后重新打开会继续上次没传完的队列', () async {
    final a = pickedFile('a.jpg');
    final b = pickedFile('b.jpg');
    final hold = Completer<void>();
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      await hold.future; // 模拟上传中被系统杀掉，永远不返回
      return const [];
    };

    manager.enqueue(albumId: 9, files: [
      XFile(a.path, name: 'a.jpg'),
      XFile(b.path, name: 'b.jpg'),
    ]);
    await _waitUntil(() => manager.items.length == 2, reason: '入队');
    await manager.flushPersistence();

    // 进程被杀：内存清空，磁盘上的队列还在。
    manager.resetForTest();
    await manager.restore();
    expect(manager.items.length, 2);
    expect(manager.restoredPending.length, 2);

    var calls = 0;
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      calls++;
      return const [];
    };
    manager.resumeRestored();
    await _waitUntil(
      () => manager.items.every((item) => item.done) && !manager.isUploading,
      reason: '续传完成',
    );

    expect(calls, 2);
    expect(await UploadQueueStore.load(), isEmpty);
  });

  test('每传完一个就删掉对应的本地副本', () async {
    final a = pickedFile('a.jpg');
    final b = pickedFile('b.jpg');
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async => const [];

    manager.enqueue(albumId: 1, files: [
      XFile(a.path, name: 'a.jpg'),
      XFile(b.path, name: 'b.jpg'),
    ]);
    await _waitUntil(
      () => manager.items.every((item) => item.done && item.sourceCleaned),
      reason: '上传并清理',
    );

    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isFalse);
  });

  test('重启时会清掉没有被队列引用的副本', () async {
    final keep = pickedFile('keep.jpg');
    final orphan = pickedFile('orphan.jpg');
    final hold = Completer<void>();
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      await hold.future;
      return const [];
    };

    manager.enqueue(albumId: 1, files: [XFile(keep.path, name: 'keep.jpg')]);
    await _waitUntil(() => manager.items.length == 1, reason: '入队');
    await manager.flushPersistence();

    manager.resetForTest();
    await manager.restore();

    await _waitUntil(() => !orphan.existsSync(), reason: '孤儿副本被清理');
    expect(keep.existsSync(), isTrue, reason: '队列里还在用的副本要保留');
  });

  test('重启后副本已被系统清掉的条目提示重新上传，不会卡住队列', () async {
    final file = pickedFile('c.jpg');
    final hold = Completer<void>();
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      await hold.future;
      return const [];
    };

    manager.enqueue(albumId: 1, files: [XFile(file.path, name: 'c.jpg')]);
    await _waitUntil(() => manager.items.length == 1, reason: '入队');
    await manager.flushPersistence();

    file.deleteSync();
    manager.resetForTest();
    await manager.restore();

    expect(manager.items.single.failed, isTrue);
    expect(manager.items.single.failure, UploadFailureKind.sourceMissing);
    expect(manager.restoredPending, isEmpty);

    manager.resumeRestored();
    expect(manager.isUploading, isFalse);
  });

  test('服务端拒绝的条目重启后保留失败状态，等用户手动重试', () async {
    final file = pickedFile('d.jpg');
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/albums/1/media'),
        type: DioExceptionType.badResponse,
        response: Response<void>(
          requestOptions: RequestOptions(path: '/api/albums/1/media'),
          statusCode: 413,
        ),
      );
    };

    manager.enqueue(albumId: 1, files: [XFile(file.path, name: 'd.jpg')]);
    await _waitUntil(() => manager.items.single.failed, reason: '上传失败');
    await manager.flushPersistence();

    manager.resetForTest();
    await manager.restore();

    expect(manager.items.single.failed, isTrue);
    expect(manager.items.single.failure, UploadFailureKind.server);
    expect(manager.restoredPending, isEmpty);
  });
}