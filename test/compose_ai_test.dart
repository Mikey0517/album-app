import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/compose_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('没有选媒体时「AI 帮写」不可点击', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const ComposePage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 帮写'), findsOneWidget);
    // TextButton.icon 返回的是 TextButton 子类，要用 bySubtype 匹配。
    final aiButton = find.ancestor(
      of: find.text('AI 帮写'),
      matching: find.bySubtype<TextButton>(),
    );
    expect(aiButton, findsOneWidget);
    expect(
      tester.widget<TextButton>(aiButton).onPressed,
      isNull,
      reason: '没有媒体时必须禁用',
    );
    expect(tester.takeException(), isNull);
  });
}
