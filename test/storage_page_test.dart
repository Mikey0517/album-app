import 'dart:io';

import 'package:album_app/core/cache_service.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/picked_media_cleaner.dart';
import 'package:album_app/core/upload_manager.dart';
import 'package:album_app/features/profile/storage_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 页面统计的是真实磁盘：真实 IO 与 fake async 必须交替推进，
/// 每次 await 都要靠一轮「真实等待 + pump」才能继续，所以按条件循环推进。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int rounds = 200,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (done()) return;
  }
}

Widget _app() => MaterialApp(
      theme: buildAppTheme(),
      home: const StoragePage(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory tempDir;
  late Directory docsDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UploadManager.instance.resetForTest();
    tmp = Directory.systemTemp.createTempSync('album_storage_page_test');
    tempDir = Directory('${tmp.path}/temp')..createSync();
    docsDir = Directory('${tmp.path}/docs')..createSync(recursive: true);
    Directory('${docsDir.path}/picked_media').createSync();
    CacheService.dirsOverride = () async => CacheDirs(
          tempDir: tempDir.path,
          docsDir: docsDir.path,
        );
    CacheService.programBytesOverride = () => 4096;
    PickedMediaCleaner.rootsOverride = () async => [docsDir.path];
  });

  tearDown(() {
    CacheService.dirsOverride = null;
    CacheService.programBytesOverride = null;
    PickedMediaCleaner.rootsOverride = null;
    UploadManager.instance.resetForTest();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // 忽略清理失败。
    }
  });

  File writeFile(String path, int bytes) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(bytes, 7));
    return file;
  }

  testWidgets('分项展示四类占用，清理只删图片缓存和临时文件', (tester) async {
    final image = writeFile('${tempDir.path}/album_image_cache/a.jpg', 4096);
    final temp = writeFile('${tempDir.path}/motion_photos/b.mp4', 2048);
    final pending = writeFile('${docsDir.path}/picked_media/c.jpg', 1024);

    await tester.pumpWidget(_app());
    await _pumpUntil(tester, () => find.text('…').evaluate().isEmpty);

    expect(find.text('图片缓存'), findsOneWidget);
    expect(find.text('临时文件'), findsOneWidget);
    expect(find.text('待上传副本'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('总计'), findsOneWidget);
    expect(find.text('1 项 · 1.0 KB'), findsOneWidget);
    expect(find.text('11.0 KB'), findsOneWidget, reason: '总计是四项之和');

    await tester.tap(find.widgetWithText(FilledButton, '清理'));
    await _pumpUntil(tester, () => find.text('清理缓存？').evaluate().isNotEmpty);

    expect(find.text('清理缓存？'), findsOneWidget);
    expect(find.text('合计可清理'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '清理'));
    await _pumpUntil(
      tester,
      () =>
          !image.existsSync() &&
          find.textContaining('已清理 6.0 KB').evaluate().isNotEmpty,
    );

    expect(image.existsSync(), isFalse);
    expect(temp.existsSync(), isFalse);
    expect(pending.existsSync(), isTrue, reason: '主按钮不能删待上传副本');
    expect(find.textContaining('已清理 6.0 KB'), findsOneWidget);
  });

  testWidgets('清理待上传副本有二次确认，确认后副本被删掉', (tester) async {
    final pending = writeFile('${docsDir.path}/picked_media/c.jpg', 1024);

    await tester.pumpWidget(_app());
    await _pumpUntil(tester, () => find.text('…').evaluate().isEmpty);

    await tester.tap(find.widgetWithText(TextButton, '清理待上传副本'));
    await _pumpUntil(
      tester,
      () => find.text('清理待上传副本？').evaluate().isNotEmpty,
    );

    expect(find.text('清理待上传副本？'), findsOneWidget);
    expect(find.textContaining('会从上传队列移除并删除'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '清理'));
    await _pumpUntil(
      tester,
      () =>
          !pending.existsSync() &&
          find.textContaining('已清理 1 项').evaluate().isNotEmpty,
    );

    expect(pending.existsSync(), isFalse);
    expect(find.textContaining('已清理 1 项'), findsOneWidget);
  });
}
