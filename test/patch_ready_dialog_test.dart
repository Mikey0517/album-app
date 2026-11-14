import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/update/patch_ready_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _appChannel = MethodChannel('album/app');

Widget _app() => MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showPatchReadyDialog(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

Future<void> _openDialog(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  expect(find.text('更新已准备好'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> appCalls;
  late List<MethodCall> platformCalls;

  setUp(() {
    appCalls = <MethodCall>[];
    platformCalls = <MethodCall>[];
    // SystemNavigator.pop 走 SystemChannels.platform，兜底分支就靠它判定。
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_appChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('点「立即重启」会发出原生的 restart 调用', (tester) async {
    messenger.setMockMethodCallHandler(_appChannel, (call) async {
      appCalls.add(call);
      return true;
    });

    await _openDialog(tester);
    await tester.tap(find.text('立即重启'));
    await tester.pumpAndSettle();

    expect(appCalls.map((call) => call.method), ['restart']);
    expect(
      platformCalls.map((call) => call.method),
      isNot(contains('SystemNavigator.pop')),
      reason: '原生接管了就不用兜底退出',
    );
  });

  testWidgets('原生返回错误时兜底退出 App，不抛异常', (tester) async {
    messenger.setMockMethodCallHandler(_appChannel, (call) async {
      appCalls.add(call);
      throw PlatformException(code: 'no_launch_intent', message: '取不到启动 Intent');
    });

    await _openDialog(tester);
    await tester.tap(find.text('立即重启'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(appCalls.map((call) => call.method), ['restart']);
    expect(platformCalls.map((call) => call.method), contains('SystemNavigator.pop'));
  });

  testWidgets('通道不可用（MissingPluginException）时同样兜底，不崩', (tester) async {
    // 原生没注册这条通道时，Dart 侧拿到的就是 MissingPluginException。
    messenger.setMockMethodCallHandler(_appChannel, (call) async {
      appCalls.add(call);
      throw MissingPluginException('No implementation found for method restart');
    });

    await _openDialog(tester);
    await tester.tap(find.text('立即重启'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(appCalls.map((call) => call.method), ['restart']);
    expect(platformCalls.map((call) => call.method), contains('SystemNavigator.pop'));
  });

  testWidgets('点「稍后」不调用 restart，弹窗关闭', (tester) async {
    messenger.setMockMethodCallHandler(_appChannel, (call) async {
      appCalls.add(call);
      return true;
    });

    await _openDialog(tester);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(appCalls, isEmpty);
    expect(platformCalls.map((call) => call.method), isNot(contains('SystemNavigator.pop')));
    expect(find.text('更新已准备好'), findsNothing);
  });
}
