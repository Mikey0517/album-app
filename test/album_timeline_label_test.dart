import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/album_view_settings.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/widgets/album_thumb.dart';
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

Media _video(int id, DateTime takenAt) => Media(
      id: id,
      type: 'video',
      thumbUrl: null,
      url: '',
      width: 1920,
      height: 1080,
      durationMs: 62000,
      takenAt: takenAt,
      createdAt: takenAt,
      postId: null,
    );

/// 跨三个月的照片（9/10/11 月各 32 张、各占 8 行），够长，能拖到每个月。
List<Media> _crossMonths() {
  final items = <Media>[];
  var id = 1;
  for (var month = 9; month <= 11; month++) {
    for (var i = 0; i < 32; i++) {
      items.add(_photo(id++, DateTime(2024, month, 5, 9, i)));
    }
  }
  return items;
}

/// 7 月只有照片、8 月只有视频：筛选切换时可见集合的月份完全不同。
/// （相册按时间倒序，所以「全部」时 8 月在最前面。）
List<Media> _splitByType() {
  final items = <Media>[];
  var id = 1;
  for (var i = 0; i < 16; i++) {
    items.add(_photo(id++, DateTime(2024, 7, 5, 9, i)));
  }
  for (var i = 0; i < 16; i++) {
    items.add(_video(id++, DateTime(2024, 8, 6, 10, i)));
  }
  return items;
}

Future<void> _pump(WidgetTester tester, List<Media> items) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final album = Album(
    id: 7,
    title: '夏天',
    coverThumb: null,
    mediaCount: items.length,
    createdAt: DateTime(2020, 5, 1),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: AlbumDetailPage(
        album: album,
        loader: (id) async => AlbumDetail(album: album, items: items),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 把时间轴拖到轨道的 [ratio] 处（0 = 最上端），松手后气泡还停留一会儿。
Future<void> _dragTimelineTo(WidgetTester tester, double ratio) async {
  final rect = tester.getRect(find.byType(PhotoTimelineScrubber));
  final gesture = await tester.startGesture(rect.center);
  await tester.pump();
  // 先越过触摸斜率，竖直拖拽才接管。
  await gesture.moveBy(const Offset(0, 24));
  await tester.pump();
  await gesture.moveTo(
    Offset(rect.center.dx, rect.top + 2 + (rect.height - 4) * ratio),
  );
  // 跳转要等这一帧布局完才知道顶部是谁，下一帧才取月份。
  await tester.pump();
  await tester.pump();
  await gesture.up();
}

/// 吸顶区下沿：筛选条下沿；有日期头正好钉在它下面时取日期头下沿。
double _stickyBottom(WidgetTester tester) {
  final filter = tester.getRect(find.byType(AppSegmentedBarSurface));
  final headers = find.byType(DateHeader);
  for (var i = 0; i < headers.evaluate().length; i++) {
    final rect = tester.getRect(headers.at(i));
    if ((rect.top - filter.bottom).abs() < 0.5) return rect.bottom;
  }
  return filter.bottom;
}

/// 当前画面里「吸顶条下沿那第一张媒体」的月份：和实现同一种看法——
/// 顶边已经落到吸顶条下沿、且最靠上的那张缩略图。
String? _topVisibleMonth(WidgetTester tester) {
  final inset = _stickyBottom(tester);
  final finder = find.byType(AlbumThumb);
  String? label;
  double? top;
  for (var i = 0; i < finder.evaluate().length; i++) {
    final rect = tester.getRect(finder.at(i));
    if (rect.top < inset - 0.01) continue;
    if (top != null && rect.top >= top) continue;
    top = rect.top;
    label = timelineMonthLabel(
      albumSortDate(
        tester.widget<AlbumThumb>(finder.at(i)).media,
        AlbumViewSettings.sort.value,
      ),
    );
  }
  return label;
}

Future<void> _tapFilter(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AlbumViewSettings.sort.value = AlbumSort.takenAt;
    AlbumViewSettings.group.value = AlbumGroup.day;
  });

  tearDown(() {
    AlbumViewSettings.sort.value = AlbumSort.takenAt;
    AlbumViewSettings.group.value = AlbumGroup.day;
  });

  testWidgets('相册时间轴气泡 == 当前顶部可见项的月份', (tester) async {
    await _pump(tester, _crossMonths());

    // 顶部：第一条就是最近的那个月。
    await _dragTimelineTo(tester, 0);
    expect(find.text('2024年11月'), findsOneWidget);
    expect(_topVisibleMonth(tester), '2024年11月');

    // 拖到中段：气泡跟着顶部可见项走，不读预计算 label 表。
    await _dragTimelineTo(tester, 0.5);
    final middle = _topVisibleMonth(tester);
    expect(middle, isNotNull);
    expect(find.text(middle!), findsOneWidget, reason: '气泡要等于顶部那张的月份');
    expect(middle, '2024年10月', reason: '中段顶部可见项落在 10 月');

    // 再往下拖：又换一个月，气泡继续跟着顶部走。
    await _dragTimelineTo(tester, 0.85);
    final bottom = _topVisibleMonth(tester);
    expect(bottom, isNotNull);
    expect(find.text(bottom!), findsOneWidget);
    expect(bottom, '2024年9月', reason: '拖到底时顶部可见项落到 9 月');

    await tester.pumpAndSettle();
  });

  testWidgets('相册页真的把吸顶区下沿传给了定位器', (tester) async {
    await _pump(tester, _crossMonths());
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);

    // 先滚过折叠阈值，吸顶区高度才稳定成「折叠头 + 筛选条 + 日期头」。
    const collapsed = 200.0;
    scrollable.position.jumpTo(collapsed);
    await tester.pump();

    // 每个月 32 张、4 列，占 8 行；第一行是 11 月，最后一行的下一条已经是 10 月。
    // 行距直接从渲染结果里量，别写死。
    final thumbFinder = find.byType(AlbumThumb);
    final rowTops = <double>{
      for (var i = 0; i < thumbFinder.evaluate().length; i++)
        tester.getRect(thumbFinder.at(i)).top,
    }.toList()
      ..sort();
    expect(rowTops.length, greaterThanOrEqualTo(2));
    final rowPitch = rowTops[1] - rowTops[0];
    expect(rowPitch, greaterThan(0));
    // 换成滚动内容里的坐标：11 月最后一行的顶边。
    final lastRowOfNovemberTop =
        rowTops.first + collapsed + 7 * rowPitch;

    // 滚到「11 月最后一行被吸顶条压住一半、10 月第一行刚好露在吸顶条下沿」。
    final inset = _stickyBottom(tester);
    expect(inset, 136, reason: '折叠后的吸顶区：56 工具栏 + 46 筛选条 + 34 日期头');
    scrollable.position.jumpTo(lastRowOfNovemberTop - inset + 22);
    await tester.pump();

    // 直接问相册页交给时间轴的 liveLabel：被压住的那一行不该再报 11 月。
    final label = tester
        .widget<PhotoTimelineScrubber>(find.byType(PhotoTimelineScrubber))
        .liveLabel!;
    expect(label(), '2024年10月', reason: '气泡跟着吸顶条下沿那一行换月');
    expect(label(), _topVisibleMonth(tester));
    expect(label(), isNot('2024年11月'), reason: '被吸顶条压住的那一行不参与文案');
  });

  testWidgets('筛选后气泡月份跟随可见集合', (tester) async {
    await _pump(tester, _splitByType());

    // 全部：8 月的视频排在最前。
    await _dragTimelineTo(tester, 0);
    expect(find.text('2024年8月'), findsOneWidget);

    // 只看照片：可见集合只剩 7 月的照片，同一位置换成 7 月。
    await _tapFilter(tester, '照片');
    await _dragTimelineTo(tester, 0);
    expect(find.text('2024年7月'), findsOneWidget);
    expect(find.text('2024年8月'), findsNothing, reason: '8 月只有视频，已被筛掉');
    expect(_topVisibleMonth(tester), '2024年7月');

    // 只看视频：又换回 8 月。
    await _tapFilter(tester, '视频');
    await _dragTimelineTo(tester, 0);
    expect(find.text('2024年8月'), findsOneWidget);
    expect(find.text('2024年7月'), findsNothing);
    expect(_topVisibleMonth(tester), '2024年8月');

    await tester.pumpAndSettle();
  });

  testWidgets('相册与朋友圈共用同一份可见项定位', (tester) async {
    // 两个 sliver：第一个整体滚出视口后，月份要来自第二个的第一项。
    final keys = [GlobalKey(), GlobalKey()];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: CustomScrollView(
              controller: controller,
              slivers: [
                SliverList(
                  key: keys[0],
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const SizedBox(height: 400),
                    childCount: 1,
                  ),
                ),
                SliverList(
                  key: keys[1],
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const SizedBox(height: 400),
                    childCount: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final locator = VisibleItemLocator(
      sliverStarts: const [0, 1],
      sliverKeys: keys,
    );
    String labelAt(int index) => index == 0 ? '2024年1月' : '2024年2月';
    expect(locator.visibleIndex, 0);
    expect(locator.visibleLabel(labelAt), '2024年1月');

    // 第一条整体滚出去之后，顶部可见项换成第二个 sliver 的第一项。
    controller.jumpTo(400);
    await tester.pump();
    expect(locator.visibleIndex, 1);
    expect(locator.visibleLabel(labelAt), '2024年2月');

    // 量不到时给空串，气泡自己藏起来。
    expect(VisibleItemLocator.empty.visibleLabel(labelAt), '');
    expect(timelineMonthLabel(DateTime(2024, 2, 7)), '2024年2月');
  });

  testWidgets('topInset：被吸顶条压住的那一行不再影响气泡文案', (tester) async {
    // 两条各 400 高的 sliver，视口 300：滚到 200 时第一条还剩 200 露在视口里，
    // 但它整条都在「吸顶条下沿 100」以上，不该拿来报月份。
    final keys = [GlobalKey(), GlobalKey()];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: CustomScrollView(
              controller: controller,
              slivers: [
                SliverList(
                  key: keys[0],
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const SizedBox(height: 400),
                    childCount: 1,
                  ),
                ),
                SliverList(
                  key: keys[1],
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const SizedBox(height: 400),
                    childCount: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(200);
    await tester.pump();

    String labelAt(int index) => index == 0 ? '2024年1月' : '2024年2月';
    // 不传吸顶高度（视口口径）：第一条还露着，就用它。
    final viewportTop = VisibleItemLocator(
      sliverStarts: const [0, 1],
      sliverKeys: keys,
    );
    expect(viewportTop.visibleIndex, 0);
    expect(viewportTop.visibleLabel(labelAt), '2024年1月');

    // 传了吸顶高度：第一条被压住，气泡换成吸顶条下沿那一行。
    final belowSticky = VisibleItemLocator(
      sliverStarts: const [0, 1],
      sliverKeys: keys,
      topInset: 100,
    );
    expect(belowSticky.visibleIndex, 1);
    expect(belowSticky.visibleLabel(labelAt), '2024年2月');
  });
}
