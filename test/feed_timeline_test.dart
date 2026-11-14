import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:album_app/features/feed/feed_timeline.dart';
import 'package:album_app/models/post.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Post _post(int id, DateTime postedAt) => Post(
      id: id,
      authorId: 1,
      authorNickname: '测试',
      content: null,
      postedAt: postedAt,
      medias: const [],
    );

/// 变高列表 + 右侧时间轴，和动态流的层级一致（时间轴浮在列表外面）。
Widget _scrollHarness(
  ScrollController controller, {
  required String Function() label,
  Future<void> Function()? onRefresh,
}) {
  final list = ListView.builder(
    controller: controller,
    physics: const AlwaysScrollableScrollPhysics(),
    itemCount: 50,
    itemBuilder: (context, index) => const SizedBox(height: 100),
  );
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 400,
          child: Stack(
            children: [
              if (onRefresh != null)
                RefreshIndicator(onRefresh: onRefresh, child: list)
              else
                list,
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 30,
                child: PhotoTimelineScrubber(
                  controller: controller,
                  progressLabel: label,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 三个日期分组，每组一条 400 高的动态，视口 300 高。
Widget _sliverHarness(ScrollController controller, List<GlobalKey> keys) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 300,
          child: CustomScrollView(
            controller: controller,
            slivers: [
              for (var i = 0; i < keys.length; i++)
                SliverList(
                  key: keys[i],
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => SizedBox(
                      height: 400,
                      child: Text('post-$i-$index'),
                    ),
                    childCount: 1,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('progress 模式拖到 50% 时滚到 maxScrollExtent 的一半', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _scrollHarness(controller, label: () => '2024年8月'),
    );
    await tester.pumpAndSettle();

    final max = controller.position.maxScrollExtent;
    expect(max, greaterThan(0));

    final rect = tester.getRect(find.byType(PhotoTimelineScrubber));
    final center = rect.center;
    final gesture = await tester.startGesture(center);
    await tester.pump();
    // 先滑过 touch slop 让竖直拖拽生效，再回到正中。
    await gesture.moveTo(center + const Offset(0, 30));
    await tester.pump();
    await gesture.moveTo(center);
    await tester.pump();

    expect(controller.offset, closeTo(max * 0.5, 1.0));

    // 跳转要等布局完成才取月份，多 pump 一帧。
    await tester.pump();
    expect(find.text('2024年8月'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('月份标签取自顶部可见的那条动态', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final keys = List.generate(3, (_) => GlobalKey());
    await tester.pumpWidget(_sliverHarness(controller, keys));
    await tester.pumpAndSettle();

    final timeline = FeedTimeline(
      items: [
        _post(1, DateTime(2024, 1, 5)),
        _post(2, DateTime(2024, 2, 7)),
        _post(3, DateTime(2024, 3, 9)),
      ],
      sliverStarts: const [0, 1, 2],
      sliverKeys: keys,
    );

    expect(timeline.visibleMonthLabel, '2024年1月');

    controller.jumpTo(450);
    await tester.pump();
    expect(timeline.visibleMonthLabel, '2024年2月');

    controller.jumpTo(850);
    await tester.pump();
    expect(timeline.visibleMonthLabel, '2024年3月');

    expect(FeedTimeline.monthLabel(DateTime(2024, 8, 20)), '2024年8月');
  });

  testWidgets('空闲时不渲染任何时间轴视觉元素，按下才出现、松手后消失', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _scrollHarness(controller, label: () => '2024年8月'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(timelineScrubberThumbKey), findsNothing);
    expect(find.byKey(timelineScrubberLabelKey), findsNothing);
    expect(find.text('2024年8月'), findsNothing);

    final rect = tester.getRect(find.byType(PhotoTimelineScrubber));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveTo(rect.center + const Offset(0, 40));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(timelineScrubberThumbKey), findsOneWidget);
    expect(find.text('2024年8月'), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(timelineScrubberThumbKey),
      findsOneWidget,
      reason: '松手后月份还要停留一会儿',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(timelineScrubberThumbKey), findsNothing);
  });

  testWidgets('在时间轴上拖拽不会触发下拉刷新', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var refreshes = 0;
    await tester.pumpWidget(
      _scrollHarness(
        controller,
        label: () => '2024年8月',
        onRefresh: () async {
          refreshes++;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    final rect = tester.getRect(find.byType(PhotoTimelineScrubber));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(refreshes, 0, reason: '时间轴接管了竖直拖拽，列表没被下拉');
    expect(controller.offset, greaterThan(0), reason: '拖拽应该让列表跟着跳');
  });

  test('动态少于 12 条不显示时间轴', () {
    expect(shouldShowFeedTimeline(0), isFalse);
    expect(shouldShowFeedTimeline(11), isFalse);
    expect(shouldShowFeedTimeline(12), isTrue);
  });
}
