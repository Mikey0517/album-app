import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/auth/login_page.dart';
import 'package:album_app/features/feed/compose_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// iPad 竖屏尺寸（iPad Pro 11 吋约 834x1194 逻辑像素）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: child));
    await tester.pumpAndSettle();
  }

  testWidgets('iPad 竖屏：登录页不溢出', (tester) async {
    await pumpAt(tester, const Size(834, 1194), LoginPage(onLoggedIn: () {}));
    expect(find.text('家庭相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPad 横屏：登录页不溢出', (tester) async {
    await pumpAt(tester, const Size(1194, 834), LoginPage(onLoggedIn: () {}));
    expect(find.text('家庭相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPad 竖屏：发布页不溢出', (tester) async {
    await pumpAt(tester, const Size(834, 1194), const ComposePage());
    expect(find.text('这一刻的想法…'), findsOneWidget);
    expect(find.text('AI 帮写'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPad 横屏：发布页不溢出', (tester) async {
    await pumpAt(tester, const Size(1194, 834), const ComposePage());
    expect(find.text('AI 帮写'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
