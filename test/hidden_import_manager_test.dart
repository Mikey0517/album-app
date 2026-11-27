import 'dart:io';

import 'package:album_app/core/hidden_space/hidden_import_manager.dart';
import 'package:album_app/core/hidden_space/hidden_space_store.dart';
import 'package:album_app/core/media_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('album/media_picker');
  late Directory tempDir;

  setUp(() async {
    HiddenImportManager.instance.resetForTest();
    tempDir = await Directory.systemTemp.createTemp('hidden_import_test_');
    HiddenSpaceStore.overrideDirectory = tempDir;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'copyHiddenFile') return null;
      final args = call.arguments as Map<Object?, Object?>;
      final name = args['name'] as String? ?? 'file';
      final target = File('${tempDir.path}/copied_$name');
      await target.writeAsBytes([1, 2, 3, 4]);
      return {'path': target.path, 'size': 4};
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    HiddenSpaceStore.overrideDirectory = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> waitIdle() async {
    for (var i = 0; i < 100 && HiddenImportManager.instance.isBusy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('导入一条：复制进私有目录、写索引、状态条出现', () async {
    final manager = HiddenImportManager.instance;
    await manager.enqueue(const [
      HiddenSource(
          uri: 'content://pick/1', name: 'a.jpg', mime: 'image/jpeg', size: 4),
    ]);
    await waitIdle();

    expect(manager.finished, 1);
    expect(manager.failedCount, 0);
    expect(manager.addedCount, 1);
    expect(manager.showStatusChip, isTrue);

    final files = await HiddenSpaceStore.load();
    expect(files, hasLength(1));
    expect(files.first.name, 'a.jpg');
    expect(await File(files.first.path).exists(), isTrue);
  });

  test('一条失败不影响后面的条目', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'copyHiddenFile') return null;
      final args = call.arguments as Map<Object?, Object?>;
      final name = args['name'] as String? ?? 'file';
      if (name == 'bad.jpg') throw PlatformException(code: 'copy_failed');
      final target = File('${tempDir.path}/copied_$name');
      await target.writeAsBytes([1]);
      return {'path': target.path, 'size': 1};
    });

    final manager = HiddenImportManager.instance;
    await manager.enqueue(const [
      HiddenSource(
          uri: 'content://pick/bad',
          name: 'bad.jpg',
          mime: 'image/jpeg',
          size: 1),
      HiddenSource(
          uri: 'content://pick/good',
          name: 'good.jpg',
          mime: 'image/jpeg',
          size: 1),
    ]);
    await waitIdle();

    expect(manager.total, 2);
    expect(manager.finished, 2);
    expect(manager.failedCount, 1);
    expect(manager.addedCount, 1);
    expect(manager.items.first.failed, isTrue);
    expect(manager.items.last.done, isTrue);
  });

  test('打开面板会收起状态条，确认后隐藏', () async {
    final manager = HiddenImportManager.instance;
    await manager.enqueue(const [
      HiddenSource(
          uri: 'content://pick/1', name: 'a.jpg', mime: 'image/jpeg', size: 1),
    ]);
    await waitIdle();

    manager.setSheetOpen(true);
    expect(manager.showStatusChip, isFalse);
    manager.setSheetOpen(false);
    expect(manager.showStatusChip, isTrue);

    manager.acknowledgeCompleted();
    expect(manager.showStatusChip, isFalse);

    manager.clearFinished();
    expect(manager.hasItems, isFalse);
  });
}
