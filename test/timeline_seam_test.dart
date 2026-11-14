import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/feed_gallery_page.dart';
import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/models/paged.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:album_app/widgets/date_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media _photo(int id, DateTime takenAt) => Media(
      id: id,
      type: 'image',
      thumbUrl: null,
      url: '',
      width: 1920,
      height: 1080,
      durationMs: null,
      takenAt: takenAt,
      createdAt: takenAt,
      postId: null,
    );

/// 30 张、分 6 天：够撑出时间轴，也有多个日期分组。
List<Media> _many() {
  final items = <Media>[];
  var id = 1;
  for (var i = 0; i < 18; i++) {
    items.add(_photo(id++, DateTime(2020, 6, 1 + (i ~/ 3), 9, i)));
  }
  for (var i = 0; i < 12; i++) {
    items.add(_photo(id++, DateTime(2020, 7, 1 + (i ~/ 4), 10, i)));
  }
  return items;
}

Future<void> _pumpGallery(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final items = _many();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: FeedGalleryPage(
          loader: (cursor) async => Paged<Media>(
            items: cursor == null ? items : const <Media>[],
            nextCursor: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 动态流层级：吸顶日期头（36）+ 变高卡片 + 右侧时间轴。
Widget _feedHarness(ScrollController controller) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: controller,
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _FeedDateHeaderDelegate(),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => const SizedBox(height: 100),
                  childCount: 50,
                ),
              ),
            ],
          ),
          FeedTimelineLayer(
            controller: controller,
            label: () => '2024年8月',
          ),
        ],
      ),
    ),
  );
}

/// 和生产代码同高同宽的吸顶日期头，测试里量它的下沿。
class _FeedDateHeaderDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => kFeedDateHeaderHeight;

  @override
  double get maxExtent => kFeedDateHeaderHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return const DateHeader(text: '今天 · 8月20日', height: kFeedDateHeaderHeight);
  }

  @override
  bool shouldRebuild(covariant _FeedDateHeaderDelegate oldDelegate) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('朋友圈相册：轨道顶边 = 吸顶筛选条下沿，滚动不漂移', (tester) async {
    await _pumpGallery(tester);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    // 吸顶区只有筛选条这一层（日期头是内容流里的普通横条）：46 高，恒定。
    for (final target in <double>[0, 300, 600, 1200]) {
      position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
      await tester.pumpAndSettle();

      final filter = tester.getRect(find.byType(AppSegmentedBarSurface));
      expect(filter.top, closeTo(0, 0.5), reason: '筛选条始终吸在顶部');
      expect(
        filter.height,
        closeTo(kAppSegmentedBarHeight, 0.5),
        reason: '吸顶区高度恒为筛选条高度',
      );
      expect(
        tester.getRect(find.byType(PhotoTimelineScrubber)).top - filter.bottom,
        closeTo(0.0, 0.01),
        reason: '轨道顶边 = 吸顶条下沿，接缝 0 像素',
      );
    }

    // 日期头跟着内容走：滚 100 就正好上移 100，说明它没有被钉住。
    position.jumpTo(300);
    await tester.pumpAndSettle();
    DateHeader? probe;
    double? before;
    final headers = find.byType(DateHeader);
    for (var i = 0; i < headers.evaluate().length; i++) {
      final rect = tester.getRect(headers.at(i));
      if (rect.top < 120) continue; // 留出余量，滚 100 之后它还在树里
      probe = tester.widget<DateHeader>(headers.at(i));
      before = rect.top;
      break;
    }
    expect(probe, isNotNull, reason: '屏上总该有一条日期头');
    position.jumpTo(400);
    await tester.pumpAndSettle();
    final after = tester.getRect(
      find.byWidgetPredicate((w) => w is DateHeader && w.text == probe!.text),
    );
    expect(
      after.top,
      closeTo(before! - 100, 0.5),
      reason: '日期头是普通内容，不会像 pinned 那样叠在顶部',
    );

    // 拖到轨道最上端：滑块贴住轨道顶边，不压吸顶筛选条。
    final open = find.byType(PhotoTimelineScrubber);
    final rect = tester.getRect(open);
    final gesture = await tester.startGesture(rect.center);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    await gesture.moveTo(Offset(rect.center.dx, rect.top + 1));
    await tester.pump();
    final thumb = tester.getRect(find.byKey(timelineScrubberThumbKey));
    expect(thumb.top - rect.top, closeTo(0.0, 0.01));
    expect(
      thumb.top,
      greaterThanOrEqualTo(kAppSegmentedBarHeight - 0.01),
      reason: '滑块不许盖住吸顶筛选条',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('朋友圈动态流：轨道从吸顶日期头下沿开始，滑块不盖日期头', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_feedHarness(controller));
    await tester.pumpAndSettle();

    final header = tester.getRect(find.byType(DateHeader));
    final track = tester.getRect(find.byType(PhotoTimelineScrubber));
    expect(header.top, closeTo(0, 0.01), reason: '日期头钉在视口顶部');
    expect(
      track.top - header.bottom,
      closeTo(0.0, 0.01),
      reason: '轨道顶边 = 吸顶日期头下沿（之前从 0 起算，滑块会盖住日期头）',
    );

    final gesture = await tester.startGesture(track.center);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    await gesture.moveTo(Offset(track.center.dx, track.top + 1));
    await tester.pump();
    final thumb = tester.getRect(find.byKey(timelineScrubberThumbKey));
    expect(thumb.top - track.top, closeTo(0.0, 0.01));
    expect(
      thumb.top,
      greaterThanOrEqualTo(header.bottom - 0.01),
      reason: '滑块顶端不许高过吸顶日期头下沿',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
