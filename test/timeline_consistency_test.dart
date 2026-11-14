import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/album_view_settings.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/album/feed_gallery_page.dart';
import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/models/paged.dart';
import 'package:album_app/widgets/album_thumb.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:album_app/widgets/date_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 两个页面的时间轴必须一模一样：吸顶栈（筛选条 + 只钉当前分组的日期头）、
// offsets 跳转、topInset、气泡取值、空闲隐藏。差异只允许「有没有折叠封面头」
// 这一处，所以这里用同一份数据、同一套测量函数分别跑两页。

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

/// 跨 4 个月（9/10/11/12 月各 16 张、各占 4 行）：日期分组就是 4 组，
/// 「某月第一行」正好是每组的第 0 张，落点可以直接量。
List<Media> _crossMonths() {
  final items = <Media>[];
  var id = 1;
  for (var month = 9; month <= 12; month++) {
    for (var i = 0; i < 16; i++) {
      items.add(_photo(id++, DateTime(2024, month, 5, 9, i)));
    }
  }
  return items;
}

const Size _viewport = Size(390, 844);

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 相册详情页：有折叠封面头，折叠后的吸顶区 = 56 工具栏 + 46 筛选条 + 34 日期头。
Future<void> _pumpAlbum(WidgetTester tester) async {
  _usePhoneViewport(tester);
  final items = _crossMonths();
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

/// 朋友圈相册：没有折叠封面头，吸顶区 = 46 筛选条 + 34 日期头 = 80。
Future<void> _pumpFeedGallery(WidgetTester tester) async {
  _usePhoneViewport(tester);
  final items = _crossMonths();
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

/// 一条可以直接按「比例」拖的时间轴页面。
class _PageSpec {
  const _PageSpec({
    required this.name,
    required this.stickyHeight,
    required this.pump,
  });

  final String name;

  /// 折叠完成后的吸顶区高度：相册页 136，朋友圈相册 80。
  final double stickyHeight;

  final Future<void> Function(WidgetTester) pump;
}

const List<_PageSpec> _pages = <_PageSpec>[
  _PageSpec(name: '相册详情页', stickyHeight: 136, pump: _pumpAlbum),
  _PageSpec(name: '朋友圈相册', stickyHeight: 80, pump: _pumpFeedGallery),
];

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

/// 钉在吸顶位（筛选条下沿）的日期头：正常应当只有一个。
List<Rect> _pinnedHeaders(WidgetTester tester) {
  final filter = tester.getRect(find.byType(AppSegmentedBarSurface));
  final headers = find.byType(DateHeader);
  final pinned = <Rect>[];
  for (var i = 0; i < headers.evaluate().length; i++) {
    final rect = tester.getRect(headers.at(i));
    if ((rect.top - filter.bottom).abs() <= 0.5) pinned.add(rect);
  }
  return pinned;
}

/// 吸顶区下沿：筛选条下沿，有日期头钉在它下面时取日期头下沿。
double _stickyBottom(WidgetTester tester) {
  final pinned = _pinnedHeaders(tester);
  if (pinned.isNotEmpty) return pinned.first.bottom;
  return tester.getRect(find.byType(AppSegmentedBarSurface)).bottom;
}

/// 吸顶区下沿以下第一项的月份：和实现同一种看法（被吸顶条压住的行不算）。
String? _topVisibleMonth(WidgetTester tester) {
  final inset = _stickyBottom(tester);
  final thumbs = find.byType(AlbumThumb);
  String? label;
  double? top;
  for (var i = 0; i < thumbs.evaluate().length; i++) {
    final rect = tester.getRect(thumbs.at(i));
    if (rect.top < inset - 0.01) continue;
    if (top != null && rect.top >= top) continue;
    top = rect.top;
    label = timelineMonthLabel(
      albumSortDate(
        tester.widget<AlbumThumb>(thumbs.at(i)).media,
        AlbumViewSettings.sort.value,
      ),
    );
  }
  return label;
}

/// 把时间轴拖到轨道的 [ratio] 处（0 = 最上端）；松手后气泡还停留一会儿。
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

String? _bubbleText(WidgetTester tester) {
  final bubble = find.byKey(timelineScrubberLabelKey);
  if (bubble.evaluate().isEmpty) return null;
  final text = find.descendant(of: bubble, matching: find.byType(Text));
  if (text.evaluate().isEmpty) return null;
  return tester.widget<Text>(text.first).data;
}

/// 某张照片在屏幕上的顶边（找不到时返回 NaN）。
double _thumbTop(WidgetTester tester, int mediaId) {
  final thumbs = find.byType(AlbumThumb);
  for (var i = 0; i < thumbs.evaluate().length; i++) {
    final thumb = tester.widget<AlbumThumb>(thumbs.at(i));
    if (thumb.media.id == mediaId) return tester.getRect(thumbs.at(i)).top;
  }
  return double.nan;
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

  testWidgets('同一拖动位置，两页气泡月份相同（0% / 50%）', (tester) async {
    // 两页用同一份数据、同一套 offsets：同一比例选中的是同一张照片，
    // 落点也都在吸顶区下沿，所以气泡月份必须一样。
    final months = <String, List<String?>>{};
    for (final page in _pages) {
      await page.pump(tester);
      final bubbles = <String?>[];
      for (final ratio in <double>[0, 0.5]) {
        await _dragTimelineTo(tester, ratio);
        bubbles.add(_bubbleText(tester));
        await tester.pumpAndSettle();
      }
      months[page.name] = bubbles;
    }
    expect(months['相册详情页'], isNot(contains(null)));
    expect(
      months['朋友圈相册'],
      months['相册详情页'],
      reason: '两页同一拖动位置要报同一个月',
    );
  });

  for (final page in _pages) {
    testWidgets('${page.name}：吸顶区高度恒定，且只有一条日期头吸顶', (tester) async {
      await page.pump(tester);
      final position = _position(tester);

      for (final target in <double>[200, 400, 600]) {
        position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
        await tester.pumpAndSettle();

        final filter = tester.getRect(find.byType(AppSegmentedBarSurface));
        // 筛选条钉在折叠页头下沿：相册页 56，朋友圈相册 0（没有页头）。
        expect(
          filter.top,
          closeTo(page.stickyHeight - kAppSegmentedBarHeight - 34, 0.5),
          reason: '筛选条始终吸在折叠页头下沿，不随滚动走',
        );
        expect(
          filter.height,
          closeTo(kAppSegmentedBarHeight, 0.5),
          reason: '筛选条高度不随滚动变',
        );

        final pinned = _pinnedHeaders(tester);
        expect(pinned, hasLength(1), reason: '同一时刻只有一个日期头吸顶');
        expect(
          pinned.single.height,
          closeTo(34, 0.5),
          reason: '日期头是 34 高（和另一页同一个数）',
        );
        expect(
          pinned.single.bottom,
          closeTo(page.stickyHeight, 0.5),
          reason: '吸顶区 = 折叠头(相册页 56) + 筛选条 46 + 日期头 34',
        );
        expect(
          tester.getRect(find.byType(PhotoTimelineScrubber)).top,
          closeTo(page.stickyHeight, 0.01),
          reason: '轨道顶边 = 吸顶区下沿，且不随滚动漂移',
        );
        expect(
          _stickyBottom(tester),
          closeTo(page.stickyHeight, 0.5),
          reason: '吸顶区高度恒定',
        );
      }

      // 其余日期头留在内容流里：不许有第二条叠在吸顶位。
      final all = find.byType(DateHeader);
      expect(all.evaluate().length, greaterThanOrEqualTo(2));
    });

    testWidgets('${page.name}：气泡月份 == 吸顶下沿以下第一项的月份', (tester) async {
      await page.pump(tester);

      for (final ratio in <double>[0, 0.5, 0.85]) {
        await _dragTimelineTo(tester, ratio);
        final bubble = _bubbleText(tester);
        final expected = _topVisibleMonth(tester);
        expect(bubble, isNotNull, reason: '${ratio * 100}% 位置要浮出月份气泡');
        expect(expected, isNotNull);
        expect(
          bubble,
          expected,
          reason: '${ratio * 100}% 位置：气泡必须等于吸顶区下沿以下第一项的月份',
        );
        await tester.pumpAndSettle();
      }
    });

    testWidgets('${page.name}：拖到某月后该月第一行落在吸顶区下沿', (tester) async {
      await page.pump(tester);
      final position = _position(tester);
      // 可见集合按时间倒序：12 月 / 11 月 / 10 月 / 9 月各 16 张，分组起点 0/16/32/48。
      final sections = albumSections(
        _crossMonths(),
        AlbumViewSettings.sort.value,
        AlbumViewSettings.group.value,
      );
      var start = 0;
      final starts = <int>[];
      for (final section in sections) {
        starts.add(start);
        start += section.items.length;
      }
      final scrubber = tester.widget<PhotoTimelineScrubber>(
        find.byType(PhotoTimelineScrubber),
      );
      final count = scrubber.itemCount;
      expect(count, 64);

      var checked = 0;
      for (var i = 0; i < starts.length; i++) {
        final index = starts[i];
        // 拖动只能滚到 maxScrollExtent：够不着的月份不参与落点断言。
        if (scrubber.itemOffsets[index] > position.maxScrollExtent) continue;
        final ratio = index / (count - 1);
        await _dragTimelineTo(tester, ratio);
        final inset = _stickyBottom(tester);
        final firstId = sections[i].items.first.id;
        expect(
          _thumbTop(tester, firstId),
          closeTo(inset, 1),
          reason: '拖到 ${sections[i].header} 后，该月第一行顶边 == 吸顶区下沿',
        );
        await tester.pumpAndSettle();
        checked++;
      }
      expect(checked, greaterThanOrEqualTo(3), reason: '至少三个月能滚到');
    });

    testWidgets('${page.name}：平铺分组也把第一行落在吸顶区下沿', (tester) async {
      AlbumViewSettings.group.value = AlbumGroup.flat;
      await page.pump(tester);
      expect(find.byType(DateHeader), findsNothing, reason: '平铺没有分组头');

      await _dragTimelineTo(tester, 0);
      // 没有日期头时吸顶区只剩折叠页头 + 筛选条（相册页 102，朋友圈相册 46）。
      final inset = _stickyBottom(tester);
      expect(inset, closeTo(page.stickyHeight - 34, 0.5));
      final sections = albumSections(
        _crossMonths(),
        AlbumViewSettings.sort.value,
        AlbumViewSettings.group.value,
      );
      expect(
        _thumbTop(tester, sections.single.items.first.id),
        closeTo(inset, 1),
        reason: '平铺模式拖到最上端，第一行也要贴住吸顶区下沿',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('${page.name}：空闲时不渲染时间轴视觉元素', (tester) async {
      await page.pump(tester);
      expect(find.byType(PhotoTimelineScrubber), findsOneWidget);
      expect(find.byKey(timelineScrubberThumbKey), findsNothing);
      expect(find.byKey(timelineScrubberLabelKey), findsNothing);

      // 按下去才出现，松手后自己收起（收起靠定时器，要真的等过 hideDelay）。
      await _dragTimelineTo(tester, 0.5);
      expect(find.byKey(timelineScrubberThumbKey), findsOneWidget);
      expect(find.byKey(timelineScrubberLabelKey), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(
        find.byKey(timelineScrubberThumbKey),
        findsNothing,
        reason: '松手后滑块自己藏起来',
      );
      expect(find.byKey(timelineScrubberLabelKey), findsNothing);
    });
  }
}