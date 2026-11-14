import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/feed_gallery_page.dart';
import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/models/paged.dart';
import 'package:album_app/widgets/album_thumb.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:album_app/widgets/empty_state.dart';
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

/// 30 项（16 照片 + 14 视频），够撑出时间轴。
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

/// 40 个视频 + 20 张照片，用于分页测试（筛选到视频后仍然能滚动）。
List<Media> _pagedFirstPage() {
  final items = <Media>[];
  var id = 1;
  for (var i = 0; i < 40; i++) {
    items.add(_video(id++, DateTime(2020, 8, 1, 9, i)));
  }
  for (var i = 0; i < 20; i++) {
    items.add(_photo(id++, DateTime(2020, 7, 1, 9, i)));
  }
  return items;
}

List<Media> _pagedSecondPage() {
  final items = <Media>[];
  for (var i = 0; i < 20; i++) {
    items.add(_photo(1000 + i, DateTime(2020, 6, 1, 9, i)));
  }
  return items;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Media> items,
  Future<Paged<Media>> Function(String? cursor)? loader,
  GlobalKey<FeedGalleryPageState>? pageKey,
  void Function(bool selecting, int selected, int total)? onSelectionChanged,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: FeedGalleryPage(
          key: pageKey,
          onSelectionChanged: onSelectionChanged,
          loader: loader ??
              (cursor) async => Paged(
                    items: cursor == null ? items : const <Media>[],
                    nextCursor: null,
                  ),
        ),
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

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('筛选只显示对应类型，数量不随筛选跳变', (tester) async {
    await _pump(tester, items: _mixed());

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('照片'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(_chipCount(tester, '全部'), 12);
    expect(_chipCount(tester, '照片'), 8);
    expect(_chipCount(tester, '视频'), 4);
    expect(find.byType(AlbumThumb), findsNWidgets(12));

    await _tapFilter(tester, '照片');
    final photos =
        tester.widgetList<AlbumThumb>(find.byType(AlbumThumb)).toList();
    expect(photos, hasLength(8));
    expect(photos.every((thumb) => !thumb.media.isVideo), isTrue);
    // 数量始终是全量：切来切去数字不跳。
    expect(_chipCount(tester, '全部'), 12);
    expect(_chipCount(tester, '照片'), 8);
    expect(_chipCount(tester, '视频'), 4);

    await _tapFilter(tester, '视频');
    final videos =
        tester.widgetList<AlbumThumb>(find.byType(AlbumThumb)).toList();
    expect(videos, hasLength(4));
    expect(videos.every((thumb) => thumb.media.isVideo), isTrue);
    expect(_chipCount(tester, '全部'), 12);
    expect(_chipCount(tester, '照片'), 8);
    expect(_chipCount(tester, '视频'), 4);

    await _tapFilter(tester, '全部');
    expect(find.byType(AlbumThumb), findsNWidgets(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选后时间轴 itemCount / offsets / 实时月份跟随可见集合', (tester) async {
    await _pump(tester, items: _many());

    // 气泡文案改成实时取顶部可见项，不再依赖预计算 label 表。
    var scrubber = tester.widget<PhotoTimelineScrubber>(
      find.byType(PhotoTimelineScrubber),
    );
    expect(scrubber.itemCount, 30);
    expect(scrubber.itemOffsets, hasLength(30));
    expect(scrubber.liveLabel, isNotNull);
    expect(scrubber.liveLabel!(), '2020年7月', reason: '7 月的视频排在最前');

    await _tapFilter(tester, '照片');
    scrubber = tester.widget<PhotoTimelineScrubber>(
      find.byType(PhotoTimelineScrubber),
    );
    expect(scrubber.itemCount, 16);
    expect(scrubber.itemOffsets, hasLength(16));
    expect(scrubber.liveLabel!(), '2020年6月', reason: '筛选后只剩 6 月的照片');

    await _tapFilter(tester, '视频');
    scrubber = tester.widget<PhotoTimelineScrubber>(
      find.byType(PhotoTimelineScrubber),
    );
    expect(scrubber.itemCount, 14);
    expect(scrubber.itemOffsets, hasLength(14));
    expect(scrubber.liveLabel!(), '2020年7月');
  });

  testWidgets('空状态一：一条动态都还没有', (tester) async {
    await _pump(tester, items: const []);

    expect(find.text('暂无照片或视频'), findsOneWidget);
    expect(tester.widget<EmptyState>(find.byType(EmptyState)).subtitle, isNull);
    // 没有内容就不摆筛选条，屏幕只留这一句。
    expect(find.byType(AppSegmentedBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空状态二：筛选后没有照片', (tester) async {
    await _pump(tester, items: [
      _video(1, DateTime(2020, 5, 10, 9)),
      _video(2, DateTime(2020, 5, 10, 10)),
      _video(3, DateTime(2020, 5, 11, 9)),
    ]);

    await _tapFilter(tester, '照片');
    expect(find.text('筛选后没有照片'), findsOneWidget);
    expect(tester.widget<EmptyState>(find.byType(EmptyState)).subtitle, isNull);
    expect(find.byType(AlbumThumb), findsNothing);

    // 一句「看全部」就能回去，不用自己去猜要换哪个筛选。
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
    expect(find.text('筛选后没有视频'), findsOneWidget);
    expect(tester.widget<EmptyState>(find.byType(EmptyState)).subtitle, isNull);
    expect(find.byType(AlbumThumb), findsNothing);
  });

  testWidgets('筛选条吸顶常驻：滚动后仍钉在顶部', (tester) async {
    await _pump(tester, items: _many());

    final before = tester.getRect(find.byType(AppSegmentedBarSurface));
    expect(before.top, 0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final after = tester.getRect(find.byType(AppSegmentedBarSurface));
    expect(after.top, closeTo(before.top, 0.5), reason: '筛选条不跟着内容滚走');
    expect(_position(tester).pixels, greaterThan(0), reason: '确实滚动了');
    // 时间轴轨道从吸顶条下沿开始，不会压住筛选条。
    final scrubber = tester.getRect(find.byType(PhotoTimelineScrubber));
    expect(scrubber.top, closeTo(after.bottom, 0.5));
  });

  testWidgets('全选与数量回报都只算可见项', (tester) async {
    final reports = <List<int>>[];
    final pageKey = GlobalKey<FeedGalleryPageState>();
    await _pump(
      tester,
      items: _mixed(),
      pageKey: pageKey,
      onSelectionChanged: (selecting, selected, total) =>
          reports.add([selected, total]),
    );

    await _tapFilter(tester, '照片');
    await tester.longPress(find.byType(AlbumThumb).first);
    await tester.pumpAndSettle();
    // 1 张已选，总数是当前可见的 8 张照片，不是 12 项。
    expect(reports.last, [1, 8]);

    pageKey.currentState!.toggleAll();
    await tester.pumpAndSettle();
    expect(reports.last, [8, 8]);

    // 切到视频：选中集合裁到可见项（4 个视频一个都没选）。
    await _tapFilter(tester, '视频');
    expect(reports.last, [0, 4]);

    pageKey.currentState!.toggleAll();
    await tester.pumpAndSettle();
    expect(reports.last, [4, 4]);
    expect(find.byType(AlbumThumb), findsNWidgets(4));
  });

  testWidgets('分页追加时筛选态不崩溃：不符合筛选的新数据不动滚动位置', (tester) async {
    final firstPage = _pagedFirstPage();
    final secondPage = _pagedSecondPage();
    var calls = 0;

    await _pump(
      tester,
      items: const [],
      loader: (cursor) async {
        calls++;
        return cursor == null
            ? Paged(items: firstPage, nextCursor: 'p2')
            : Paged(items: secondPage, nextCursor: null);
      },
    );
    expect(calls, 1);

    await _tapFilter(tester, '视频');
    var scrubber = tester.widget<PhotoTimelineScrubber>(
      find.byType(PhotoTimelineScrubber),
    );
    expect(scrubber.itemCount, 40, reason: '第一页的 40 个视频');

    // 滚到接近底部，触发无限滚动拉第二页（第二页全是照片）。
    final max = _position(tester).maxScrollExtent;
    await tester.drag(
      find.byType(CustomScrollView),
      Offset(0, -(max - 200)),
    );
    await tester.pump();
    final offsetBefore = _position(tester).pixels;
    expect(offsetBefore, greaterThan(0));

    await tester.pumpAndSettle();
    expect(calls, 2, reason: '无限滚动拉了第二页');
    expect(
      _position(tester).pixels,
      closeTo(offsetBefore, 0.5),
      reason: '新数据全被筛掉，滚动位置不能被重置或跳动',
    );

    scrubber = tester.widget<PhotoTimelineScrubber>(
      find.byType(PhotoTimelineScrubber),
    );
    expect(scrubber.itemCount, 40, reason: '时间轴仍是可见的 40 个视频');
    expect(scrubber.itemOffsets, hasLength(40));
    expect(find.text('筛选后没有视频'), findsNothing);
    expect(find.byType(EmptyState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选后没内容但还有下一页时，静默补读直到找到可见项', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      items: const [],
      loader: (cursor) async {
        calls++;
        if (cursor == null) {
          return Paged(
            items: [_photo(1, DateTime(2020, 5, 10, 9))],
            nextCursor: 'p2',
          );
        }
        return Paged(
          items: [_video(2, DateTime(2020, 5, 9, 9))],
          nextCursor: null,
        );
      },
    );

    await _tapFilter(tester, '视频');
    expect(calls, 2, reason: '第一页没有视频，补读了第二页');
    expect(find.byType(AlbumThumb), findsOneWidget);
    expect(find.text('筛选后没有视频'), findsNothing);
  });
}
