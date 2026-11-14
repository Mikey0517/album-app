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

  testWidgets('「其他」拆成五个子项，总计是所有分项之和', (tester) async {
    writeFile('${tempDir.path}/album_image_cache/a.jpg', 4096);
    writeFile('${tempDir.path}/motion_photos/b.mp4', 2048);
    writeFile('${tempDir.path}/album_updates/app.apk', 1024);
    writeFile('${tempDir.path}/album_share_1/c.jpg', 512);
    writeFile('${docsDir.path}/picked_media/d.jpg', 256);

    await tester.pumpWidget(_app());
    await _pumpUntil(tester, () => find.text('…').evaluate().isEmpty);

    expect(find.text('图片缓存'), findsOneWidget);
    expect(find.text('临时文件'), findsOneWidget);
    expect(find.text('待上传副本'), findsOneWidget);
    expect(find.text('更新包'), findsOneWidget);
    expect(find.text('分享/导出临时文件'), findsOneWidget);
    expect(find.text('应用数据'), findsOneWidget);
    expect(find.text('程序本体'), findsOneWidget);
    expect(find.text('其它残留'), findsOneWidget);
    expect(find.text('总计'), findsOneWidget);
    expect(find.text('1 项 · 256 B'), findsOneWidget);
    expect(find.text('1.0 KB'), findsOneWidget, reason: '更新包');
    expect(find.text('512 B'), findsOneWidget, reason: '分享/导出临时文件');
    expect(find.text('0 B'), findsNWidgets(2), reason: '应用数据与其它残留为空');
    // 4096 + 2048 + 1024 + 512 + 256 + 4096 = 12032
    expect(find.text('11.8 KB'), findsOneWidget, reason: '总计是所有分项之和');

    // 子项缩进一级，大小都在同一列右对齐。
    expect(
      tester.getTopLeft(find.text('更新包')).dx,
      greaterThan(tester.getTopLeft(find.text('图片缓存')).dx),
      reason: '子项靠缩进表达层级',
    );
    final valueRight = tester.getTopRight(find.text('2.0 KB')).dx;
    expect(tester.getTopRight(find.text('1.0 KB')).dx, valueRight);
    expect(tester.getTopRight(find.text('11.8 KB')).dx, valueRight);
    expect(
      tester.getTopRight(find.text('0 B').first).dx,
      valueRight,
      reason: '大小统一右对齐',
    );
  });

  testWidgets('主按钮清理会列明细，删可清理分项但保留不可清理的', (tester) async {
    final image = writeFile('${tempDir.path}/album_image_cache/a.jpg', 4096);
    final temp = writeFile('${tempDir.path}/motion_photos/b.mp4', 2048);
    final apk = writeFile('${tempDir.path}/album_updates/app.apk', 1024);
    final share = writeFile('${tempDir.path}/album_share_1/c.jpg', 512);
    final pending = writeFile('${docsDir.path}/picked_media/d.jpg', 256);

    await tester.pumpWidget(_app());
    await _pumpUntil(tester, () => find.text('…').evaluate().isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, '清理'));
    await _pumpUntil(tester, () => find.text('清理缓存？').evaluate().isNotEmpty);

    expect(find.text('清理缓存？'), findsOneWidget);
    expect(find.text('合计可清理'), findsOneWidget);
    expect(find.text('7.5 KB'), findsOneWidget, reason: '弹窗里的合计明细');
    expect(
      find.text('待上传副本、应用数据与程序本体不会被删除。'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, '清理'));
    await _pumpUntil(
      tester,
      () =>
          !image.existsSync() &&
          find.textContaining('已清理 7.5 KB').evaluate().isNotEmpty,
    );

    expect(image.existsSync(), isFalse);
    expect(temp.existsSync(), isFalse);
    expect(apk.existsSync(), isFalse, reason: '更新包可清理');
    expect(share.existsSync(), isFalse, reason: '分享临时目录可清理');
    expect(pending.existsSync(), isTrue, reason: '主按钮不能删待上传副本');
    expect(find.textContaining('已清理 7.5 KB'), findsOneWidget);
    // 清理后数字刷新：四个可清理分项归零。
    expect(find.text('0 B'), findsWidgets);
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
