import 'package:album_app/features/hidden/four_finger_pull.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<int Function()> pump(WidgetTester tester) async {
    var triggers = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FourFingerPullDetector(
          onTrigger: () => triggers++,
          child: const Scaffold(body: Center(child: Text('内容'))),
        ),
      ),
    );
    return () => triggers;
  }

  testWidgets('四指一起往下拉会触发', (tester) async {
    final triggers = await pump(tester);
    final gestures = <TestGesture>[];
    for (var i = 0; i < 4; i++) {
      gestures.add(await tester.startGesture(Offset(100.0 + i * 40, 200)));
    }
    for (final gesture in gestures) {
      await gesture.moveBy(const Offset(0, 60));
    }
    await tester.pump();
    for (final gesture in gestures) {
      await gesture.moveBy(const Offset(0, 100));
    }
    await tester.pump();
    expect(triggers(), 1, reason: '四指下拉超过阈值，触发一次');
    for (final gesture in gestures) {
      await gesture.up();
    }
    await tester.pump();
  });

  testWidgets('三指下拉不触发', (tester) async {
    final triggers = await pump(tester);
    final gestures = <TestGesture>[];
    for (var i = 0; i < 3; i++) {
      gestures.add(await tester.startGesture(Offset(100.0 + i * 40, 200)));
    }
    for (final gesture in gestures) {
      await gesture.moveBy(const Offset(0, 300));
    }
    await tester.pump();
    expect(triggers(), 0);
    for (final gesture in gestures) {
      await gesture.up();
    }
  });

  testWidgets('一次手势只触发一次', (tester) async {
    final triggers = await pump(tester);
    final gestures = <TestGesture>[];
    for (var i = 0; i < 4; i++) {
      gestures.add(await tester.startGesture(Offset(100.0 + i * 40, 200)));
    }
    for (var step = 0; step < 4; step++) {
      for (final gesture in gestures) {
        await gesture.moveBy(const Offset(0, 60));
      }
      await tester.pump();
    }
    expect(triggers(), 1);
    for (final gesture in gestures) {
      await gesture.up();
    }
  });
}
