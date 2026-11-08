import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/server_config.dart';
import 'package:album_app/core/server_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings dialog shows read-only lan and wan addresses',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    ServerConfig.resetForTest();
    ServerConfig.setNetworkKindForTest('wifi');
    addTearDown(ServerConfig.resetForTest);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showServerSettings(context, autoTest: false),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('服务器状态'), findsOneWidget);
    expect(find.text('局域网'), findsOneWidget);
    expect(find.text('互联网'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
}
