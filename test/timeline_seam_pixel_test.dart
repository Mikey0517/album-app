import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/album_view_settings.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/album/album_timeline_layout.dart';
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

// 「吸顶条下沿 → 时间轴轨道」之间那条缝：两页、各种滚动位置逐个量。
//
// 缝的成因是「网格顶部内边距」：吸顶条下沿在 140，第一行照片却在 144，中间 4 行
// 页面底色。所以这里量三件事（两页 × 分组/平铺 × 多个滚动位置）：
//   1. 日期头下沿 == 它下面第一格照片的顶边（内容流里也不能有 4px 空隙）；
//   2. 吸顶日期头下沿 == 轨道顶边（吸顶条下沿到轨道之间没有第三段几何）；
//   3. 把时间轴拖到最上端（分组头正好顶到吸顶位的那一刻）时，
//      第一行照片顶边 == 吸顶条下沿 == 轨道顶边——缝宽 0 像素。

Media _photo(int id, DateTime takenAt) => Media(
      id: id, type: 'image', thumbUrl: null, url: '', width: 1920,
      height: 1080, durationMs: null, takenAt: takenAt, createdAt: takenAt,
      postId: null,
    );

/// 跨 4 个月、每组 16 张：分组头、多行网格和长滚动都有。
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

Future<void> _pumpAlbum(WidgetTester tester) async {
  _usePhoneViewport(tester);
  final data = _crossMonths();
  final album = Album(
    id: 7,
    title: '夏天',
    coverThumb: null,
    mediaCount: data.length,
    createdAt: DateTime(2020, 5, 1),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: AlbumDetailPage(
        album: album,
        loader: (id) async => AlbumDetail(album: album, items: data),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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

Future<void> _jumpTo(WidgetTester tester, double target) async {
  final position =
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  await tester.pumpAndSettle();
}

/// 把时间轴拖到轨道最上端（ratio = 0）：分组头正好顶到吸顶位。
Future<void> _dragTimelineToTop(WidgetTester tester) async {
  final rect = tester.getRect(find.byType(PhotoTimelineScrubber));
  final gesture = await tester.startGesture(rect.center);
  await tester.pump();
  await gesture.moveBy(const Offset(0, 24)); // 先越过触摸斜率
  await tester.pump();
  await gesture.moveTo(Offset(rect.center.dx, rect.top + 1));
  await tester.pump();
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// 吸顶栈下沿：筛选条下沿，有日期头钉在它下面时取日期头下沿。
double _stickyBottom(WidgetTester tester) {
  final filter = tester.getRect(find.byType(AppSegmentedBarSurface));
  var bottom = filter.bottom;
  final headers = find.byType(DateHeader);
  for (var i = 0; i < headers.evaluate().length; i++) {
    final rect = tester.getRect(headers.at(i));
    if ((rect.top - filter.bottom).abs() < 0.5) bottom = rect.bottom;
  }
  return bottom;
}

/// 顶边 >= [from] 的第一格照片的顶边（找不到返回 NaN）。
double _firstTileTopBelow(WidgetTester tester, double from) {
  final thumbs = find.byType(AlbumThumb);
  var top = double.infinity;
  for (var i = 0; i < thumbs.evaluate().length; i++) {
    final rect = tester.getRect(thumbs.at(i));
    if (rect.top >= from - 0.01 && rect.top < top) top = rect.top;
  }
  return top.isFinite ? top : double.nan;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AlbumViewSettings.group.value = AlbumGroup.day;
  });
  tearDown(() => AlbumViewSettings.group.value = AlbumGroup.day);

  testWidgets('几何只有一处定义：分组头吃掉留白，网格自己不再加内边距', (tester) async {
    expect(
      kTimelineDateHeaderExtent,
      kTimelineDateHeaderHeight + kTimelineSectionGap,
      reason: '分组头整体高度 = 文字区 34 + 留白 4',
    );
    expect(kTimelineGridTopPadding, 0, reason: '网格顶部内边距会漏出页面底色');

    await _pumpAlbum(tester);
    final headers = find.byType(DateHeader);
    expect(headers.evaluate(), isNotEmpty);
    for (var i = 0; i < headers.evaluate().length; i++) {
      expect(
        tester.getRect(headers.at(i)).height,
        closeTo(kTimelineDateHeaderExtent, 0.01),
        reason: '内容流里的日期头也要整块 38 高：留白不许是透明的',
      );
    }
  });

  /// 内容流里的每个日期头：下沿 == 它下面第一格照片的顶边（0 缝）。
  void expectHeadersTouchGrid(WidgetTester tester, String tag) {
    final filter = tester.getRect(find.byType(AppSegmentedBarSurface));
    final headers = find.byType(DateHeader);
    var checked = 0;
    for (var i = 0; i < headers.evaluate().length; i++) {
      final header = tester.getRect(headers.at(i));
      final pinned = (header.top - filter.bottom).abs() < 0.5 ||
          header.top < filter.bottom;
      final tileTop = _firstTileTopBelow(tester, header.bottom);
      if (tileTop.isNaN || tileTop > header.bottom + 400) continue;
      expect(
        tileTop - header.bottom,
        closeTo(0.0, 0.01),
        reason: '[$tag] 日期头$i（${pinned ? '吸顶' : '内容流'}）下沿到第一格照片'
            '之间不许有页面底色，差值 0',
      );
      checked++;
    }
    expect(checked, greaterThan(0), reason: '[$tag] 至少要量到一个日期头');
  }

  for (final target in <double>[0, 40, 80, 300, 700, 1400]) {
    testWidgets('相册详情页@$target：日期头紧贴网格，轨道不晚于吸顶条下沿', (tester) async {
      await _pumpAlbum(tester);
      await _jumpTo(tester, target);
      final sticky = _stickyBottom(tester);
      final track = tester.getRect(find.byType(PhotoTimelineScrubber));
      expect(
        track.top,
        lessThanOrEqualTo(sticky + 0.01),
        reason: '轨道顶边不许晚于吸顶条下沿（晚多少就是多宽的缝）',
      );
      if (target >= 80) {
        // 页头收起后：吸顶条下沿 == 轨道顶边（同一个数）。
        expect(track.top, closeTo(sticky, 0.01), reason: '折叠后轨道顶边 = 吸顶条下沿');
      }
      if (target == 0) {
        // 只在顶部量：那一刻分组头在内容流里，没被吸顶条压住。
        expectHeadersTouchGrid(tester, '相册详情页@0');
      }
    });
  }

  for (final target in <double>[0, 700]) {
    testWidgets('相册详情页平铺@$target：筛选条下沿 == 轨道顶边，网格贴住筛选条', (tester) async {
      AlbumViewSettings.group.value = AlbumGroup.flat;
      await _pumpAlbum(tester);
      expect(find.byType(DateHeader), findsNothing, reason: '平铺没有分组头');
      await _jumpTo(tester, target);
      final filter = tester.getRect(find.byType(AppSegmentedBarSurface));
      final track = tester.getRect(find.byType(PhotoTimelineScrubber));
      expect(
        track.top,
        lessThanOrEqualTo(filter.bottom + 0.01),
        reason: '平铺时轨道顶边不许晚于筛选条下沿（晚多少就是多宽的缝）',
      );
      expect(kTimelineGridTopPadding, 0, reason: '平铺时网格顶部不许有内边距');
    });
  }

  for (final target in <double>[0, 300, 700]) {
    testWidgets('朋友圈相册@$target：日期头紧贴网格，轨道顶边 == 吸顶条下沿', (tester) async {
      await _pumpFeedGallery(tester);
      await _jumpTo(tester, target);
      final sticky = _stickyBottom(tester);
      final track = tester.getRect(find.byType(PhotoTimelineScrubber));
      expect(
        track.top,
        closeTo(sticky, 0.01),
        reason: '轨道顶边 = 吸顶条下沿（46 筛选条 + 38 日期头）',
      );
      if (target == 0) {
        expectHeadersTouchGrid(tester, '朋友圈相册@0');
      }
    });
  }

  for (final page in <(String, Future<void> Function(WidgetTester))>[
    ('相册详情页', _pumpAlbum),
    ('朋友圈相册', _pumpFeedGallery),
  ]) {
    testWidgets('${page.$1}：拖到时间轴最上端那一格正好贴住吸顶条下沿', (tester) async {
      await page.$2(tester);
      await _dragTimelineToTop(tester);
      final sticky = _stickyBottom(tester);
      final track = tester.getRect(find.byType(PhotoTimelineScrubber));
      expect(track.top, closeTo(sticky, 0.01), reason: '轨道顶边 = 吸顶条下沿');
      expect(
        _firstTileTopBelow(tester, sticky) - sticky,
        closeTo(0.0, 0.01),
        reason: '第一行照片顶边 == 吸顶条下沿：这就是那条缝，宽度必须是 0',
      );
    });
  }
}
