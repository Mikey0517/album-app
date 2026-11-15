import 'dart:convert';

import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('发布入口只剩 AppBar 按钮与空态按钮，页面没有 FAB', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 空列表：走空态分支，空态里的「发动态」按钮才会出现。
    addTearDown(
      installFakeApi(json: jsonEncode({'items': [], 'next_cursor': null})),
    );

    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const FeedPage()),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.floatingActionButton, isNull, reason: '右下角玻璃 FAB 已删除');
    expect(find.byType(FloatingActionButton), findsNothing);

    // 发布入口保留：AppBar 的相机按钮 + 空态按钮。
    expect(find.byTooltip('发布动态'), findsOneWidget);
    expect(find.byTooltip('那年今日'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '发动态'), findsOneWidget);
    expect(find.text('还没有动态'), findsOneWidget);
  });
}
