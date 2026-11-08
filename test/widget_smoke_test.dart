import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/auth/login_page.dart';
import 'package:album_app/features/auth/register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('login page renders the design-system shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LoginPage(onLoggedIn: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('家庭相册'), findsOneWidget);
    expect(find.text('记录生活里的每个瞬间'), findsOneWidget);
    expect(find.text('登录'), findsWidgets);
    expect(find.text('没有账号？去注册'), findsOneWidget);
    expect(find.byIcon(Icons.dns_outlined), findsWidgets);
  });

  testWidgets('register page fits a small phone viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: RegisterPage(onLoggedIn: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('创建账号'), findsOneWidget);
    expect(find.text('注册并登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
