import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/album/album_media_filter.dart';
import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:album_app/core/album_view_settings.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/widgets/album_thumb.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:album_app/widgets/date_header.dart';
import 'package:album_app/widgets/pinned_bar_sliver.dart';
import 'package:album_app/widgets/selection_footer.dart';
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

Album _album({int mediaCount = 12}) => Album(
      id: 7,
      title: '夏天',
      coverThumb: null,
      mediaCount: mediaCount,
      createdAt: DateTime(2020, 5, 1),
    );

/// 8 张照片 + 4 个视频，分三天；分组数量 3 / 5 / 4。
List<Media> _mixed() => [
      _photo(1, DateTime(2020, 5, 10, 9)),
      _photo(2, DateTime(2020, 5, 10, 9, 1)),
      _video(3, DateTime(2020, 5, 10, 10)),
      _photo(4, DateTime(2020, 5, 11, 9)),
      _photo(5, DateTime(2020, 5, 11, 9, 1)),
      _photo(6, DateTime(2020, 5, 11, 9, 2)),
      _photo(7, DateTime(2020, 5, 11, 9, 3)),
      _video(8, DateTime(2020, 5, 11, 10)),
      _photo(9, DateTime(2020, 5, 12, 9)),
      _photo(10, DateTime(2020, 5, 12, 9, 1)),
      _video(11, DateTime(2020, 5, 12, 10)),
      _video(12, DateTime(2020, 5, 12, 10, 1)),
    ];

/// 30 项（16 照片 + 14 视频），用来验证时间轴跟筛选走。
List<Media> _many() {
  final items = <Media>[];
  var id = 1;
  for (var i = 0; i < 16; i++) {
    items.add(_photo(id++, DateTime(2020, 6, 1 + (i ~/ 6), 9, i)));
  }
  for (var i = 0; i < 14; i++) {
    items.add(_video(id++, DateTime(2020, 7, 1 + (i ~/ 5), 10, i)));
  }
  return items;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Media> items,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final album = _album(mediaCount: items.length);
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

Future<void> _tapFilter(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

int? _chipCount(WidgetTester tester, String label) {
  final bar = tester.widget<AppSegmentedBar>(find.byType(AppSegmentedBar));
  for (final item in bar.items) {
    if (item.label == label) return item.count;
  }
  return null;
}

/// 分组头右侧的数量：日期头里第二个 Text 就是它。
String? _headerCount(WidgetTester tester, String date) {
  final header = find.ancestor(
    of: find.text(date),
    matching: find.byType(DateHeader),
  );
  final texts = tester
      .widgetList<Text>(find.descendant(of: header, matching: find.byType(Text)))
      .toList();
  return texts.length > 1 ? texts.last.data : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('筛选与计数：数量始终取全量', () {
    final items = _mixed();
    final counts = AlbumMediaCounts.from(items);
    expect(counts.total, 12);
    expect(counts.photos, 8);
    expect(counts.videos, 4);
    expect(counts.of(AlbumMediaFilter.photos), 8);
    expect(filterAlbumMedia(items, AlbumMediaFilter.photos).length, 8);
    expect(filterAlbumMedia(items, AlbumMediaFilter.videos).length, 4);
    expect(filterAlbumMedia(items, AlbumMediaFilter.all).length, 12);
    expect(
      filterAlbumMedia(items, AlbumMediaFilter.videos).every((m) => m.isVideo),
      isTrue,
    );
  });

  test('时间轴偏移扣掉吸顶区，且不会出现负偏移', () {
    final sections = [
      AlbumSection(
        header: '2020年5月',
        items: [
          _photo(1, DateTime(2020, 5, 10)),
          _photo(2, DateTime(2020, 5, 10)),
          _photo(3, DateTime(2020, 5, 10)),
          _photo(4, DateTime(2020, 5, 10)),
          _photo(5, DateTime(2020, 5, 10)),
        ],
      ),
    ];
    final metrics = buildTimelineMetrics(
      sections,
      width: 300,
      columns: 4,
      headerHeight: 38,
      base: 156,
      topInset: 136,
    );
    // 第一行内容偏移 156 + 38 = 194，扣掉吸顶 136 后是 58。
    expect(metrics.offsets.first, 58);
    // 每行高 = 格宽 (300 - 2*3) / 4 + 格间距 2 = 75.5。
    expect(metrics.offsets[4], closeTo(58 + 75.5, 0.001));
    expect(metrics.labels.every((label) => label == '2020年5月'), isTrue);

    final clamped = buildTimelineMetrics(
      sections,
      width: 300,
      columns: 4,
      headerHeight: 38,
      base: 156,
      topInset: 1000,
    );
    expect(clamped.offsets.every((offset) => offset >= 0), isTrue);
  });

  testWidgets('默认展示全部，筛选条带三类数量', (tester) async {
    await _pump(tester, items: _mixed());

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('照片'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(_chipCount(tester, '全部'), 12);
    expect(_chipCount(tester, '照片'), 8);
    expect(_chipCount(tester, '视频'), 4);
    // 头部统计始终是整本相册，不随筛选变。
    expect(find.text('8 张照片 · 4 个视频'), findsOneWidget);
    expect(find.byType(AlbumThumb), findsNWidgets(12));
  });

  testWidgets('只看照片 / 只看视频只留下对应类型', (tester) async {
    await _pump(tester, items: _mixed());

    await _tapFilter(tester, '照片');
    final photos =
        tester.widgetList<AlbumThumb>(find.byType(AlbumThumb)).toList();
    expect(photos, hasLength(8));
    expect(photos.every((thumb) => !thumb.media.isVideo), isTrue);

    await _tapFilter(tester, '视频');
    final videos =
        tester.widgetList<AlbumThumb>(find.byType(AlbumThumb)).toList();
    expect(videos, hasLength(4));
    expect(videos.every((thumb) => thumb.media.isVideo), isTrue);
  });

  testWidgets('筛选后计数正确：筛选条不跳、分组头只数可见项', (tester) async {
    await _pump(tester, items: _mixed());
    expect(_headerCount(tester, '2020年5月12日'), '4');

    await _tapFilter(tester, '照片');
    // 筛选条上的数量还是全量 12 / 8 / 4，切来切去数字不闪。
    expect(_chipCount(tester, '全部'), 12);
    expect(_chipCount(tester, '照片'), 8);
    expect(_chipCount(tester, '视频'), 4);
    // 分组头跟着当前可见集合：5月12日从 4 项变成 2 张照片。
    expect(_headerCount(tester, '2020年5月12日'), '2');
    expect(_headerCount(tester, '2020年5月11日'), '4');
    expect(_headerCount(tester, '2020年5月10日'), '2');
  });

  testWidgets('筛选与全选联动，未选时不出现操作条', (tester) async {
    await _pump(tester, items: _mixed());

    await _tapFilter(tester, '照片');
    await tester.longPress(find.byType(AlbumThumb).first);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.byType(SelectionFooter), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    // 全选只覆盖当前可见的 8 张照片，不含 4 个视频。
    expect(find.text('已选 8 项'), findsOneWidget);

    await tester.tap(find.text('取消全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);
    expect(find.byType(SelectionFooter), findsNothing);

    // 全选后再切到视频，选中集合跟着可见集合清空。
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 8 项'), findsOneWidget);
    await _tapFilter(tester, '视频');
    expect(find.text('已选 0 项'), findsOneWidget);
    expect(find.byType(SelectionFooter), findsNothing);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 4 项'), findsOneWidget);
  });

  testWidgets('空状态一：相册为空', (tester) async {
    await _pump(tester, items: const []);
    expect(find.text('相册还是空的'), findsOneWidget);
    expect(find.text('添加媒体'), findsOneWidget);
    // 没有内容就不摆筛选条，屏幕只留「添加」。
    expect(find.byType(AppSegmentedBar), findsNothing);
    expect(find.byType(AlbumThumb), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空状态二：筛选后没有照片', (tester) async {
    await _pump(tester, items: [
      _video(1, DateTime(2020, 5, 10, 9)),
      _video(2, DateTime(2020, 5, 10, 10)),
      _video(3, DateTime(2020, 5, 11, 9)),
    ]);
    await _tapFilter(tester, '照片');
    expect(find.text('还没有照片'), findsOneWidget);
    expect(find.text('看全部'), findsOneWidget);
    expect(find.byType(AlbumThumb), findsNothing);

    await tester.tap(find.text('看全部'));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumThumb), findsNWidgets(3));
  });

  testWidgets('空状态三：筛选后没有视频', (tester) async {
    await _pump(tester, items: [
      _photo(1, DateTime(2020, 5, 10, 9)),
      _photo(2, DateTime(2020, 5, 10, 10)),
      _photo(3, DateTime(2020, 5, 11, 9)),
    ]);
    await _tapFilter(tester, '视频');
    expect(find.text('还没有视频'), findsOneWidget);
    expect(find.text('看全部'), findsOneWidget);
    expect(find.byType(AlbumThumb), findsNothing);
  });

  testWidgets('筛选条吸顶，日期分组头压在它下面不打架', (tester) async {
    await _pump(tester, items: _many());
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    // 折叠后的头高 56（测试环境没有状态栏内边距），筛选条钉在它下面。
    expect(
      tester.getRect(find.byType(AppSegmentedBarSurface)).top,
      closeTo(56, 0.5),
    );

    final headers = find.byType(DateHeader);
    final tops = [
      for (var i = 0; i < headers.evaluate().length; i++)
        tester.getRect(headers.at(i)).top,
    ];
    expect(
      tops.any((top) => (top - 102).abs() < 0.5),
      isTrue,
      reason: '正好有一个日期头钉在筛选条下方（56 + 46）',
    );
    // 标题不会同时出现两份：折叠后只剩工具栏标题。
    expect(find.text('夏天'), findsOneWidget);
  });

  testWidgets('时间轴紧贴吸顶条下沿：不悬空、不压住筛选条', (tester) async {
    await _pump(tester, items: _many());
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    final filter = tester.getRect(find.byType(AppSegmentedBarSurface));
    final scrubber = tester.getRect(find.byType(PhotoTimelineScrubber));
    // 日期头也吸顶：它钉在筛选条下沿（56 + 46），时间轴从它下沿开始。
    final headers = find.byType(DateHeader);
    final rects = [
      for (var i = 0; i < headers.evaluate().length; i++)
        tester.getRect(headers.at(i)),
    ];
    final pinned =
        rects.firstWhere((rect) => (rect.top - filter.bottom).abs() < 0.5);
    expect(
      scrubber.top,
      closeTo(pinned.bottom, 0.5),
      reason: '轨道顶边 = 吸顶区下沿，接缝宽度为 0',
    );
    expect(
      scrubber.top,
      greaterThanOrEqualTo(filter.bottom),
      reason: '轨道不许压在筛选条上（之前轨道从 0 起算，滑块会浮到 tab 上面）',
    );
  });

  testWidgets('平铺模式没有日期头，轨道顶边正好等于筛选条底边', (tester) async {
    AlbumViewSettings.group.value = AlbumGroup.flat;
    addTearDown(() => AlbumViewSettings.group.value = AlbumGroup.day);
    await _pump(tester, items: _many());
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.byType(DateHeader), findsNothing);
    final filter = tester.getRect(find.byType(AppSegmentedBarSurface));
    final scrubber = tester.getRect(find.byType(PhotoTimelineScrubber));

    // 吸顶条只有筛选条这一层时，两者坐标完全一致：0 缝隙。
    expect(scrubber.top, closeTo(filter.bottom, 0.5));
    // 轨道高度也只剩「视口 - 吸顶区」，拖动比例不再把吸顶区算进去。
    expect(scrubber.height, closeTo(844 - filter.bottom, 0.5));
  });

  testWidgets('吸顶筛选条背景不透明，且与页面背景同色', (tester) async {
    await _pump(tester, items: _many());
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    final surface = tester.widget<AppSegmentedBarSurface>(
      find.byType(AppSegmentedBarSurface),
    );
    expect(surface.color, AppColors.bgPage);
    expect(surface.color.alpha, 255, reason: '不透明，滚动内容不会从缝里透出来');

    // 吸顶 sliver 自己也垫了一层同色底，任何一个 child 忘了画底也不会透。
    final pinnedBar =
        tester.widget<PinnedBarSliver>(find.byType(PinnedBarSliver).first);
    expect(pinnedBar.color, AppColors.bgPage);
    expect(pinnedBar.color.alpha, 255);
  });

  testWidgets('iPad 竖屏按 5 列排，不溢出', (tester) async {
    await _pump(
      tester,
      items: _mixed(),
      size: const Size(834, 1194),
    );
    final grid = tester.widgetList<SliverGrid>(find.byType(SliverGrid)).first;
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 5, reason: '760 以上加一列');
    expect(delegate.mainAxisSpacing, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏 360 宽不溢出', (tester) async {
    await _pump(tester, items: _mixed(), size: const Size(360, 780));
    expect(tester.takeException(), isNull);
    expect(find.byType(AlbumThumb), findsNWidgets(12));
  });

  testWidgets('筛选后时间轴 itemCount 跟随可见集合', (tester) async {
    await _pump(tester, items: _many());

    var scrubber = tester.widget<PhotoTimelineScrubber>(
      find.byType(PhotoTimelineScrubber),
    );
    expect(scrubber.itemCount, 30);
    expect(scrubber.itemOffsets, hasLength(30));

    await _tapFilter(tester, '照片');
    scrubber = tester.widget<PhotoTimelineScrubber>(
      find.byType(PhotoTimelineScrubber),
    );
    expect(scrubber.itemCount, 16);
    expect(scrubber.itemOffsets, hasLength(16));

    await _tapFilter(tester, '视频');
    scrubber = tester.widget<PhotoTimelineScrubber>(
      find.byType(PhotoTimelineScrubber),
    );
    expect(scrubber.itemCount, 14);
    expect(scrubber.itemOffsets, hasLength(14));
  });
}
