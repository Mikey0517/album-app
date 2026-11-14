import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(ScrollController controller, {int count = 10}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          SizedBox(
            height: 400,
            width: 300,
            child: ListView.builder(
              controller: controller,
              itemCount: 50,
              itemBuilder: (context, index) => const SizedBox(height: 100),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 30,
            child: PhotoTimelineScrubber(
              controller: controller,
              itemCount: count,
              itemOffsets: List.generate(count, (i) => i * 400.0),
              labels: List.generate(count, (i) => '2024年${i + 1}月'),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('拖到底部会跳到对应分组的偏移并浮出月份', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(PhotoTimelineScrubber));
    final gesture = await tester.startGesture(
      Offset(rect.left + 15, rect.top + 4),
    );
    await tester.pump();
    await gesture.moveTo(Offset(rect.left + 15, rect.bottom - 6));
    await tester.pump();

    // 400px 高度里拖到 394px ≈ 98.5%，10 项取整落在最后一项 3600。
    expect(controller.offset, closeTo(3600, 1));
    expect(find.text('2024年10月'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('拖回顶部会回到偏移 0', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    controller.jumpTo(3000);
    await tester.pump();

    final rect = tester.getRect(find.byType(PhotoTimelineScrubber));
    final gesture = await tester.startGesture(
      Offset(rect.left + 15, rect.bottom - 6),
    );
    await tester.pump();
    await gesture.moveTo(Offset(rect.left + 15, rect.top + 2));
    await tester.pump();

    expect(controller.offset, closeTo(0, 1));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('拖到最上端时滑块仍留在轨道内，不浮到吸顶条上', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(PhotoTimelineScrubber));
    final gesture = await tester.startGesture(rect.center);
    await tester.pump();
    await gesture.moveTo(Offset(rect.left + 15, rect.top + 2));
    await tester.pump();

    final thumb = tester.getRect(find.byKey(timelineScrubberThumbKey));
    expect(thumb.top, greaterThanOrEqualTo(rect.top - 0.01),
        reason: '滑块不许探出轨道顶边');
    expect(thumb.bottom, lessThanOrEqualTo(rect.bottom + 0.01));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('项数太少时不显示拖拽条', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, count: 1));
    await tester.pumpAndSettle();
    expect(find.byType(GestureDetector), findsNothing);
  });
}
