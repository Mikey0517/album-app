import 'dart:async';
import 'dart:io';

import 'package:album_app/core/upload_errors.dart';
import 'package:album_app/core/upload_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

DioException _networkError() => DioException(
      requestOptions: RequestOptions(path: '/api/albums/1/media'),
      type: DioExceptionType.connectionError,
    );

Future<void> _pumpUntil(
  bool Function() condition, {
  String reason = '',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待超时：$reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manager = UploadManager.instance;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('album_upload_test');
    manager.resetForTest();
  });

  tearDown(() {
    manager.resetForTest();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // 忽略临时目录清理失败。
    }
  });

  File makeFile(String name) {
    final file = File('${tmp.path}/$name');
    file.writeAsBytesSync([1, 2, 3, 4]);
    return file;
  }

  test('成功上传后条目标记为已完成并通知进度', () async {
    final file = makeFile('a.jpg');
    var progressSeen = false;
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      onSendProgress?.call(2, 4);
      return const [];
    };
    manager.addListener(() {
      if (manager.items.any((item) => item.progress > 0)) progressSeen = true;
    });

    manager.enqueue(albumId: 7, files: [XFile(file.path, name: 'a.jpg')]);
    await _pumpUntil(() => manager.items.first.done, reason: '上传完成');

    expect(progressSeen, isTrue);
    expect(manager.items.first.failed, isFalse);
    expect(manager.items.first.status, '已完成');
    expect(manager.failedCount, 0);
  });

  test('全部重试只重传源文件还在的条目，失效项改为重新上传提示', () async {
    final alive = makeFile('alive.jpg');
    final gone = makeFile('gone.jpg');
    var attempts = 0;
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      attempts++;
      if (attempts <= 2) throw _networkError();
      return const [];
    };

    manager.enqueue(albumId: 1, files: [
      XFile(alive.path, name: 'alive.jpg'),
      XFile(gone.path, name: 'gone.jpg'),
    ]);
    await _pumpUntil(() => manager.items.every((item) => item.failed),
        reason: '两项都失败');
    expect(manager.failedCount, 2);

    gone.deleteSync();
    final result = manager.retryAllFailed();

    expect(result.retried, 1);
    expect(result.missingSource, 1);
    expect(manager.items[1].sourceMissing, isTrue);
    expect(manager.items[1].canRetry, isFalse);
    expect(manager.items[1].status, '原文件已失效，请重新上传');

    await _pumpUntil(() => manager.items[0].done, reason: '有效项重试成功');
    expect(manager.failedCount, 1, reason: '失效项仍保留记录，可手动移除');
  });

  test('点击失效项的重试会明确标记原文件失效而不是毫无反应', () async {
    final file = makeFile('gone.jpg');
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      throw _networkError();
    };

    manager.enqueue(albumId: 1, files: [XFile(file.path, name: 'gone.jpg')]);
    await _pumpUntil(() => manager.items.first.failed, reason: '首次失败');

    file.deleteSync();
    final queued = manager.retry(manager.items.first);

    expect(queued, isFalse);
    expect(manager.items.first.sourceMissing, isTrue);
    expect(manager.items.first.retrying, isFalse);
  });

  test('锁屏/后台的网络失败不算失败，回到前台自动续传', () async {
    final file = makeFile('bg.jpg');
    var calls = 0;
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      calls++;
      if (calls == 1) throw _networkError();
      return const [];
    };

    manager.setAppActive(false);
    manager.enqueue(albumId: 3, files: [XFile(file.path, name: 'bg.jpg')]);
    await _pumpUntil(
      () => manager.items.first.retrying && !manager.running,
      reason: '后台失败后挂起',
    );
    expect(manager.items.first.failed, isFalse);
    expect(manager.items.first.status, '等待重试…');

    // 和 main.dart 的生命周期回调保持一致。
    manager.setAppActive(true);
    manager.onAppResumed();
    await _pumpUntil(() => manager.items.first.done, reason: '回前台后上传完成');
    expect(calls, 2);
    expect(manager.failedCount, 0);
  });

  test('网络恢复时自动补传网络类失败', () async {
    final file = makeFile('net.jpg');
    var calls = 0;
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      calls++;
      if (calls == 1) throw _networkError();
      return const [];
    };

    manager.enqueue(albumId: 4, files: [XFile(file.path, name: 'net.jpg')]);
    await _pumpUntil(() => manager.items.first.failed, reason: '首次失败');
    expect(manager.items.first.failure, UploadFailureKind.network);

    manager.onNetworkRestored();
    await _pumpUntil(() => manager.items.first.done, reason: '网络恢复后补传成功');
    expect(calls, 2);
  });

  test('新一批上传保留上一批的失败项，方便继续重试', () async {
    final first = makeFile('first.jpg');
    final second = makeFile('second.jpg');
    var calls = 0;
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      calls++;
      if (calls == 1) throw _networkError();
      return const [];
    };

    manager.enqueue(albumId: 1, files: [XFile(first.path, name: 'first.jpg')]);
    await _pumpUntil(() => manager.items.first.failed, reason: '首次失败');

    manager
        .enqueue(albumId: 1, files: [XFile(second.path, name: 'second.jpg')]);
    await _pumpUntil(() => manager.items.length == 2 && manager.items[1].done,
        reason: '第二批完成');

    expect(manager.items[0].failed, isTrue);
    expect(manager.retryableCount, 1);
  });

  test('并行上传：同时最多跑 3 个，有空位就补下一个', () async {
    final files = List.generate(6, (i) => makeFile('p$i.jpg'));
    var active = 0;
    var maxActive = 0;
    var startedCount = 0;
    final firstThree = Completer<void>();
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      active += 1;
      startedCount += 1;
      if (active > maxActive) maxActive = active;
      if (startedCount >= UploadManager.maxConcurrentUploads &&
          !firstThree.isCompleted) {
        firstThree.complete();
      }
      // 前 3 个必须同时在场，否则这里永远不返回（串行实现会超时）。
      await firstThree.future;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      active -= 1;
      return const [];
    };

    manager.enqueue(
      albumId: 1,
      files: files
          .map((f) => XFile(f.path, name: f.path.split('/').last))
          .toList(),
    );
    await _pumpUntil(
      () => manager.items.every((item) => item.done) && !manager.isUploading,
      reason: '并行上传完成',
    );

    expect(maxActive, UploadManager.maxConcurrentUploads);
    expect(startedCount, 6);
  });

  test('一批全部完成才回调 onFinished，且只回调一次', () async {
    final files = List.generate(3, (i) => makeFile('batch$i.jpg'));
    var finished = 0;
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return const [];
    };

    manager.enqueue(
      albumId: 1,
      files: files
          .map((f) => XFile(f.path, name: f.path.split('/').last))
          .toList(),
      onFinished: () => finished += 1,
    );
    await _pumpUntil(
      () => manager.items.every((item) => item.done) && !manager.isUploading,
      reason: '一批传完',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(finished, 1);
  });

  test('取消某一条会中断上传并从列表移除', () async {
    final file = makeFile('cancel.jpg');
    final started = Completer<void>();
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      if (!started.isCompleted) started.complete();
      await cancelToken!.whenCancel;
      throw const UploadCanceledException();
    };

    manager.enqueue(albumId: 1, files: [XFile(file.path, name: 'cancel.jpg')]);
    await started.future;
    expect(manager.items.length, 1);

    manager.cancel(manager.items.first);

    expect(manager.items, isEmpty);
    await _pumpUntil(() => !manager.isUploading, reason: '取消后队列结束');
  });

  test('取消全部会清掉排队任务但保留已完成记录', () async {
    final done = makeFile('done.jpg');
    final queued1 = makeFile('q1.jpg');
    final queued2 = makeFile('q2.jpg');
    var calls = 0;
    final secondStarted = Completer<void>();
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      calls++;
      if (calls == 1) return const [];
      if (!secondStarted.isCompleted) secondStarted.complete();
      await cancelToken!.whenCancel;
      throw const UploadCanceledException();
    };

    manager.enqueue(albumId: 1, files: [
      XFile(done.path, name: 'done.jpg'),
      XFile(queued1.path, name: 'q1.jpg'),
      XFile(queued2.path, name: 'q2.jpg'),
    ]);
    await secondStarted.future;

    manager.cancelAll();
    await _pumpUntil(() => !manager.isUploading, reason: '取消全部后队列结束');

    expect(manager.items.length, 1);
    expect(manager.items.single.done, isTrue);
  });
}