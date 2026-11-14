import 'dart:async';
import 'dart:io';

import 'package:album_app/core/picked_media_cleaner.dart';
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

DioException _rejected() => DioException(
      requestOptions: RequestOptions(path: '/api/albums/1/media'),
      type: DioExceptionType.badResponse,
      response: Response<void>(
        requestOptions: RequestOptions(path: '/api/albums/1/media'),
        statusCode: 413,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manager = UploadManager.instance;
  late Directory tmp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('album_pending_copy_test');
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

  File pickedFile(String name) =>
      File('${tmp.path}/picked_media/$name')..writeAsBytesSync([1, 2, 3, 4]);

  test('孤儿清理只删队列未引用的副本', () async {
    final keep = pickedFile('keep.jpg');
    final orphan = pickedFile('orphan.jpg');

    final deleted = await PickedMediaCleaner.deleteOrphans([keep.path]);

    expect(deleted, 1);
    expect(keep.existsSync(), isTrue, reason: '队列还在引用的副本不能删');
    expect(orphan.existsSync(), isFalse);
  });

  test('清理待上传副本会连同队列条目一起删掉', () async {
    final file = pickedFile('rejected.jpg');
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      throw _rejected();
    };

    manager.enqueue(albumId: 1, files: [XFile(file.path, name: 'x.jpg')]);
    await _waitUntil(() => manager.items.single.failed, reason: '上传失败');
    await manager.flushPersistence();
    expect(
      await UploadQueueStore.load(),
      hasLength(1),
      reason: '失败条目会一直留在队列里，副本也就永远不会被清',
    );

    final result = await manager.clearPendingCopies();

    expect(result.removedItems, 1);
    expect(result.deletedCopies, 1);
    expect(result.freedBytes, 4);
    expect(manager.items, isEmpty);
    expect(file.existsSync(), isFalse);
    await manager.flushPersistence();
    expect(
      await UploadQueueStore.load(),
      isEmpty,
      reason: '队列不能指向已经删掉的副本',
    );
  });

  test('正在上传的副本不会被清掉，完成后才删', () async {
    final file = pickedFile('busy.jpg');
    final started = Completer<void>();
    final hold = Completer<void>();
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      if (!started.isCompleted) started.complete();
      await hold.future;
      return const [];
    };

    manager.enqueue(albumId: 1, files: [XFile(file.path, name: 'busy.jpg')]);
    await started.future;

    final result = await manager.clearPendingCopies();

    expect(result.removedItems, 0);
    expect(result.deletedCopies, 0);
    expect(manager.items, hasLength(1), reason: '在传的条目还要留着');
    expect(file.existsSync(), isTrue);

    hold.complete();
    await _waitUntil(() => manager.items.single.done, reason: '上传完成');
    await _waitUntil(() => !file.existsSync(), reason: '完成后副本才删');
  });
}
