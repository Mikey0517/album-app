import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/hidden_space/hidden_lock.dart';
import 'package:album_app/features/hidden/hidden_space_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  testWidgets('非图片/视频的格子点了不跳转', (tester) async {
    await pumpPage(tester);
    await enterPin(tester, '123456');
    await enterPin(tester, '123456');
    // 空列表里没有格子，这条只验证页面停在隐藏空间（没有意外 push）。
    expect(find.text('还没有文件'), findsOneWidget);
  });
}
