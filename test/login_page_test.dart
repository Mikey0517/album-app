import 'package:album_app/core/account_store.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/auth/login_page.dart';
import 'package:album_app/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> seedAccount() async {
    await AccountStore.remember(
      const AppUser(id: 1, userId: 'mikey', nickname: '爸爸'),
      'secret123',
      savePassword: true,
    );
  }

  testWidgets('登录页会带出上次账号和记住的密码，可从下拉切换', (tester) async {
    await tester.runAsync(seedAccount);

    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: LoginPage(onLoggedIn: () {})),
    );
    await tester.pumpAndSettle();

    // 默认填入最近登录的账号与密码，并勾上「记住密码」。
    final idField = tester.widget<TextField>(find.byType(TextField).first);
    expect(idField.controller!.text, 'mikey');
    final passwordField = tester.widget<TextField>(find.byType(TextField).last);
    expect(passwordField.controller!.text, 'secret123');
    expect(find.text('记住密码'), findsOneWidget);
    expect(find.text('已记录 1 个账号'), findsOneWidget);

    // 账号下拉。
    await tester.tap(find.byTooltip('选择已登录过的账号'));
    await tester.pumpAndSettle();
    expect(find.text('选择账号'), findsOneWidget);
    expect(find.text('爸爸'), findsOneWidget);
    expect(find.text('@mikey · 已记住密码'), findsOneWidget);

    await tester.tap(find.text('爸爸'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'mikey',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有历史账号时仍可手动输入', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: LoginPage(onLoggedIn: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('选择已登录过的账号'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'mikey');
    expect(find.text('记住密码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
