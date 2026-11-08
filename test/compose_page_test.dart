import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/compose_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compose page has borderless editor and text publish action',
      (tester) async {
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

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('发表'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('这一刻的想法…'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final editor = tester.widget<TextField>(find.byType(TextField));
    expect(editor.decoration?.border, InputBorder.none);
    expect(editor.decoration?.enabledBorder, InputBorder.none);
    expect(editor.decoration?.focusedBorder, InputBorder.none);
    expect(editor.decoration?.errorBorder, InputBorder.none);
    expect(editor.decoration?.focusedErrorBorder, InputBorder.none);
    expect(editor.minLines, 5);
    expect(editor.maxLines, isNull);

    final publish = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '发表'),
    );
    expect(publish.onPressed, isNull);
  });
}
