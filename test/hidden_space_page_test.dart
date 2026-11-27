import 'dart:io';

import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/hidden_space/hidden_lock.dart';
import 'package:album_app/core/hidden_space/hidden_space_store.dart';
import 'package:album_app/features/album/album_media_filter_bar.dart';
import 'package:album_app/features/hidden/hidden_space_page.dart';
import 'package:album_app/features/viewer/media_viewer_page.dart';
import 'package:album_app/widgets/album_thumb.dart';
import 'package:album_app/widgets/selection_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1×1 透明 PNG：给「点图片进全屏」的用例当真实文件。
const List<int> _tinyPng = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('hidden_page_test_');
    HiddenSpaceStore.overrideDirectory = tempDir;
    HiddenSpaceStore.overrideFiles = null;
  });

  tearDown(() {
    HiddenSpaceStore.overrideDirectory = null;
    HiddenSpaceStore.overrideFiles = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HiddenSpacePage()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('第一次进入要求设置 6 位密码（输入两次）', (tester) async {
    await pumpPage(tester);
    expect(find.text('设置 6 位数字密码'), findsOneWidget);

    await enterPin(tester, '123456');
    expect(find.text('再输入一次'), findsOneWidget);

    await enterPin(tester, '123456');
    expect(await HiddenLock.isConfigured(), isTrue);
    expect(find.text('还没有文件'), findsOneWidget);
  });

  testWidgets('两次输入不一致会报错并要求重来', (tester) async {
    await pumpPage(tester);
    await enterPin(tester, '123456');
    await enterPin(tester, '654321');

    expect(find.text('两次输入不一致，请重新设置'), findsOneWidget);
    expect(find.text('设置 6 位数字密码'), findsOneWidget);
    expect(await HiddenLock.isConfigured(), isFalse);
  });

  testWidgets('已设置密码时先解锁，输错提示密码不对', (tester) async {
    await HiddenLock.setPin('123456');
    await pumpPage(tester);
    expect(find.text('输入密码'), findsOneWidget);

    await enterPin(tester, '000000');
    expect(find.text('密码不对'), findsOneWidget);
    expect(find.text('还没有文件'), findsNothing);

    await enterPin(tester, '123456');
    expect(find.text('还没有文件'), findsOneWidget);
  });

  testWidgets('空列表不显示格子', (tester) async {
    await pumpPage(tester);
    await enterPin(tester, '123456');
    await enterPin(tester, '123456');
    expect(find.text('还没有文件'), findsOneWidget);
    expect(find.byType(AlbumThumb), findsNothing);
  });

  testWidgets('点图片打开的是相册那套全屏浏览页', (tester) async {
    final file = File('${tempDir.path}/photo.png')..writeAsBytesSync(_tinyPng);
    HiddenSpaceStore.overrideFiles = [
      HiddenFile(
        id: 'photo-1',
        name: 'photo.png',
        path: file.path,
        mime: 'image/png',
        size: file.lengthSync(),
        addedAt: DateTime(2026, 1, 1),
      ),
    ];
    await HiddenLock.setPin('123456');
    await pumpPage(tester);
    await enterPin(tester, '123456');

    expect(find.byType(AlbumThumb), findsOneWidget);
    await tester.tap(find.byType(AlbumThumb));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MediaViewerPage), findsOneWidget);
  });

  testWidgets('有文件时顶部有分类条，长按进入多选并出下载/删除', (tester) async {
    final file = File('${tempDir.path}/photo.png')..writeAsBytesSync(_tinyPng);
    HiddenSpaceStore.overrideFiles = [
      HiddenFile(
        id: 'photo-1',
        name: 'photo.png',
        path: file.path,
        mime: 'image/png',
        size: file.lengthSync(),
        addedAt: DateTime(2026, 1, 1),
      ),
    ];
    await HiddenLock.setPin('123456');
    await pumpPage(tester);
    await enterPin(tester, '123456');

    expect(find.byType(AlbumMediaFilterBar), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);

    await tester.longPress(find.byType(AlbumThumb));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.byType(SelectionFooter), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });
}
