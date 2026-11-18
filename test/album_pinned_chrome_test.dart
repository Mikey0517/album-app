import 'dart:ui' as ui;

import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/album_view_settings.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/formatters.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/album/album_media_filter_bar.dart';
import 'package:album_app/features/album/album_timeline_layout.dart';
import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/widgets/app_chrome_glass_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:album_app/widgets/date_header.dart';
import 'package:album_app/widgets/pinned_bar_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassQuality, LightweightLiquidGlass;
import 'package:shared_preferences/shared_preferences.dart';

// 相册页吸顶区：**一整块玻璃**同时装「分类行 + 日期行」。
//
// 以前这里是两块独立的 AppChromeGlassBar 上下堆叠（分类条 46 + 日期条 38），
// 两条的底衬/描边在交界处各画一遍，滚动的照片从中间那条缝里透出来。现在两行
// 塞进同一个 AppChromeGlassBar.pinned 的 children，这份文件守五件事：
// 1. 整个吸顶区只有 **1 个** AppChromeGlassBar（不是 2 个）、1 层底衬；
// 2. 总高 == 46 + 34 == 80，两行严丝合缝（上行的下沿就是下行的上沿）；
// 3. 两行之间没有第二条底色、也没有分隔线：竖向剖面逐像素连续；
// 4. 只有整块吸顶（一个 PinnedBarSliver）：分类行四段照样能点、日期行跟着
//    当前分组换文案与张数；
// 5. 平铺分组没有日期行（整块只剩分类行 46）。

const Key _pageKey = Key('album-pinned-chrome-page');

/// 两行之间允许的最大相邻像素差：**3/255**。
///
/// 一整块玻璃的竖向剖面在纯色背景下是一条几乎水平的线（scrim 0.55 + 底衬 0.9
/// 之后只剩不到 1/255 的起伏）。以前两条各自带玻璃的吸顶条在交界处会跳一次
/// （两条底衬/描边叠在一起），实测远大于 3。数值与
/// test/pinned_bar_color_stable_test.dart 的「可漂移权重」同一档。
const int kSeamPixelDelta = 3;

class _Shot {
  _Shot(this.bytes, this.width, this.height, this.origin);

  final List<int> bytes;
  final int width;
  final int height;
  final Offset origin;

  Color at(Offset global) {
    final x = (global.dx - origin.dx).round().clamp(0, width - 1);
    final y = (global.dy - origin.dy).round().clamp(0, height - 1);
    final offset = (y * width + x) * 4;
    return Color.fromARGB(bytes[offset + 3], bytes[offset], bytes[offset + 1],
        bytes[offset + 2]);
  }
}

Future<_Shot> _shoot(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_pageKey));
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final origin = tester.getTopLeft(find.byKey(_pageKey));
  final shot =
      _Shot(data.buffer.asUint8List(), image.width, image.height, origin);
  image.dispose();
  return shot;
}

int _channel(double a, double b) => ((a - b).abs() * 255).round();

int _pixelDelta(Color a, Color b) => <int>[
      _channel(a.r, b.r),
      _channel(a.g, b.g),
      _channel(a.b, b.b),
    ].reduce((x, y) => x > y ? x : y);

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
      durationMs: 3000,
      takenAt: takenAt,
      createdAt: takenAt,
      postId: null,
    );

/// 四组：11/1、11/2 各 16 张照片，11/3、11/4 各 14 张 + 2 段视频。
/// 够长（能滚到第三组的第一行顶到吸顶区下沿），也有视频（分类行四段点得动）。
List<Media> _items() => <Media>[
      for (var i = 0; i < 16; i++) _photo(100 + i, DateTime(2024, 11, 1, 9, i)),
      for (var i = 0; i < 16; i++) _photo(200 + i, DateTime(2024, 11, 2, 9, i)),
      for (var i = 0; i < 14; i++) _photo(300 + i, DateTime(2024, 11, 3, 9, i)),
      for (var i = 0; i < 2; i++) _video(400 + i, DateTime(2024, 11, 3, 10, i)),
      for (var i = 0; i < 14; i++) _photo(500 + i, DateTime(2024, 11, 4, 9, i)),
      for (var i = 0; i < 2; i++) _video(600 + i, DateTime(2024, 11, 4, 10, i)),
    ];

Album _album(List<Media> items) => Album(
      id: 7,
      title: '秋天到冬天',
      coverThumb: null,
      mediaCount: items.length,
      createdAt: DateTime(2020, 5, 1),
    );

Future<void> _pumpAlbum(WidgetTester tester, {bool withBoundary = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final items = _items();
  final album = _album(items);
  final page = AlbumDetailPage(
    album: album,
    loader: (id) async => AlbumDetail(album: album, items: items),
  );
  // 注入 premium 档：真机上静态 chrome 拿到的就是这一套（不注入时
  // AppGlassSurface 会退化成不透明底，量不到底衬/玻璃）。
  final app = AppGlassScope(
    quality: GlassQuality.premium,
    child: MaterialApp(theme: buildAppTheme(), home: page),
  );
  await tester.pumpWidget(
    withBoundary ? RepaintBoundary(key: _pageKey, child: app) : app,
  );
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<void> _jumpTo(WidgetTester tester, double target) async {
  final position = _position(tester);
  position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  await tester.pumpAndSettle();
}

/// 相册吸顶区那块玻璃。
Finder _glass() => find.byType(AppChromeGlassBar);

/// 玻璃里那一行日期。
Finder _dateRow() => find.descendant(
      of: find.byType(AlbumPinnedChromeSliver),
      matching: find.byType(DateHeader),
    );

/// 玻璃里的分类行。
Finder _filterRow() => find.byType(AppSegmentedBarSurface);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AlbumViewSettings.group.value = AlbumGroup.day;
    AppColors.setDark(false);
    PageBackdropController.spec.value = const PageBackdropSpec.defaultGradient();
  });
  tearDown(() {
    AlbumViewSettings.group.value = AlbumGroup.day;
    AppColors.setDark(false);
    PageBackdropController.spec.value = const PageBackdropSpec.defaultGradient();
  });

  testWidgets('吸顶区只有 1 个 AppChromeGlassBar：分类行 + 日期行在同一块玻璃里',
      (tester) async {
    await _pumpAlbum(tester);
    await _jumpTo(tester, 600);

    expect(_glass(), findsOneWidget,
        reason: '又变成两条各自带玻璃的吸顶条了（两块玻璃就是中间那条缝的来源）');
    expect(
      find.descendant(of: _glass(), matching: find.byType(AppGlassSurface)),
      findsOneWidget,
      reason: '一层玻璃 = 一层底衬：两个 AppGlassSurface 就是两套材质',
    );
    expect(find.byType(PinnedBarSliver), findsOneWidget,
        reason: '吸顶的只能有整块这一个（两条各自吸顶会叠成两层）');

    final glass = tester.getRect(_glass());
    expect(
      kAlbumPinnedChromeHeight,
      kAppSegmentedBarHeight + kTimelineDateHeaderHeight,
      reason: '整块 = 分类行 46 + 日期行 34',
    );
    expect(kAppSegmentedBarHeight, 46);
    expect(kTimelineDateHeaderHeight, 34);
    expect(glass.height, closeTo(kAlbumPinnedChromeHeight, 0.5),
        reason: '整块玻璃总高 == 46 + 34 == 80');

    // 两行严丝合缝：上行的下沿就是下行的上沿——中间连 1px 都插不进去。
    final filter = tester.getRect(_filterRow());
    final date = tester.getRect(_dateRow());
    expect(filter.top, closeTo(glass.top, 0.5), reason: '分类行贴着玻璃上沿');
    expect(filter.height, closeTo(kAppSegmentedBarHeight, 0.5));
    expect(date.top, closeTo(filter.bottom, 0.01),
        reason: '日期行紧接分类行下沿：中间留 1px 就是那条缝');
    expect(date.height, closeTo(kTimelineDateHeaderHeight, 0.5));
    expect(date.bottom, closeTo(glass.bottom, 0.5), reason: '日期行贴着玻璃下沿');
    // 整块横贯整屏（直边条，圆角 0）。
    expect(glass.left, 0);
    expect(glass.width, 390);

    // 一块玻璃 = 一份光学参数：分类行与日期行不可能各拿一套（与 footer
    // 那一份逐项相同，见 test/pinned_chrome_bar_test.dart）。
    final surface = tester.widget<AppGlassSurface>(
      find.descendant(of: _glass(), matching: find.byType(AppGlassSurface)),
    );
    expect(surface.settings!.thickness, appGlassChromeThickness);
    expect(surface.settings!.thickness, 36, reason: '这一轮的斜面 36');
    expect(surface.settings!.refractiveIndex, appGlassChromeRefractiveIndex);
    expect(surface.settings!.refractiveIndex, 1.55, reason: '这一轮的折射率 1.55');
    expect(
      surface.settings!.chromaticAberration,
      appGlassChromeChromaticAberration,
    );
    expect(surface.settings!.chromaticAberration, 0.22,
        reason: '这一轮的色散 0.22');
    expect(surface.settings!.blur, appGlassChromeBlur);
    expect(surface.settings!.blur, 2, reason: '模糊保持 2');
    expect(surface.scrimColor!.a, closeTo(0.55, 1e-9),
        reason: 'scrim 保持 0.55（折射可见度 45%）');

    // 一整块 = 一层底衬：不是「每行各铺一层」。
    expect(
      find.descendant(
          of: _glass(), matching: find.byKey(AppGlassSurface.backplateKey)),
      findsOneWidget,
      reason: '底衬铺了两层：两行之间就会多一条被叠出来的色带',
    );
    final backplate = tester.widget<DecoratedBox>(
      find.descendant(
          of: _glass(), matching: find.byKey(AppGlassSurface.backplateKey)),
    ).decoration as BoxDecoration;
    expect(backplate.color!.a, closeTo(kAppChromePinnedBackplateAlpha, 1e-9),
        reason: '刷新不变色的那一层 0.9 还在');
    expect(tester.getRect(find.byKey(AppGlassSurface.backplateKey)), glass,
        reason: '底衬铺满整块（两行共用一层）');

    // 日期行里没有自己的底衬/分割线/模糊：两行之间不存在第二条底色。
    for (final type in <Type>[
      DecoratedBox,
      ColoredBox,
      Divider,
      BackdropFilter,
      Container,
    ]) {
      expect(
        find.descendant(of: _dateRow(), matching: find.byType(type)),
        findsNothing,
        reason: '日期行里还有一层 \$type：那就是两行之间的接缝/分隔线',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('两行之间没有接缝像素：整块玻璃的竖向剖面逐像素连续', (tester) async {
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());
    PageBackdropController.spec.value =
        const PageBackdropSpec.solid(Color(0xFFFFFFFF));
    await _pumpAlbum(tester, withBoundary: true);
    await _jumpTo(tester, 600);

    final glass = tester.getRect(_glass());
    final date = tester.getRect(_dateRow());
    final shot = await _shoot(tester);

    // 左侧内边距那一列（x = 5）：文字从 16/12 起，这里量到的就是底衬本身。
    const x = 5.0;
    var worst = 0;
    var previous = shot.at(Offset(x, glass.top + 1));
    for (var y = glass.top + 2; y <= glass.bottom - 1; y += 1) {
      final current = shot.at(Offset(x, y));
      final delta = _pixelDelta(previous, current);
      if (delta > worst) worst = delta;
      previous = current;
    }
    expect(worst, lessThanOrEqualTo(kSeamPixelDelta),
        reason: '整块玻璃的竖向剖面在某一像素行跳了 \$worst/255：'
            '那就是两行之间的接缝（一条底衬/描边叠出来的线）');

    // 两行的底衬是同一块：同一列上、分类行中部与日期行中部的像素几乎相同。
    final upper = shot.at(Offset(x, glass.top + 20));
    final lower = shot.at(Offset(x, date.center.dy));
    expect(_pixelDelta(upper, lower), lessThanOrEqualTo(kSeamPixelDelta),
        reason: '两行的底衬不是一个颜色（\$upper vs \$lower）：'
            '它们不是同一块玻璃');

    // 交界那一行也不许是「背景色/分隔线」：它与上下邻居同色。
    final seamY = tester.getRect(_filterRow()).bottom.round();
    expect(
      _pixelDelta(shot.at(Offset(x, seamY.toDouble())),
          shot.at(Offset(x, seamY - 2.0))),
      lessThanOrEqualTo(kSeamPixelDelta),
      reason: '交界处比上面暗/亮了：那是一条分隔线',
    );
    expect(
      _pixelDelta(shot.at(Offset(x, seamY.toDouble())),
          shot.at(Offset(x, seamY + 2.0))),
      lessThanOrEqualTo(kSeamPixelDelta),
      reason: '交界处比下面暗/亮了：那是一条分隔线',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('日期行跟着当前分组换文案与张数；分类行四段照样能点', (tester) async {
    await _pumpAlbum(tester);
    final sections = albumSections(
      _items(),
      AlbumViewSettings.sort.value,
      AlbumViewSettings.group.value,
    );
    expect(sections.length, greaterThanOrEqualTo(4));

    // 一进页面：日期行就是第一组的日期（它在玻璃里，内容流里没有这一条）。
    final firstHeader = sections.first.header!;
    expect(
      find.descendant(of: _dateRow(), matching: find.text(firstHeader)),
      findsOneWidget,
      reason: '顶部时玻璃里的日期行不是第一组',
    );
    expect(_dateRow(), findsOneWidget, reason: '玻璃里只该有一行日期');

    // 滚到第三组的第一行贴住吸顶区下沿：玻璃里的日期行换成这一组。
    final starts = timelineSliverStarts(sections);
    final scrubber = tester.widget<PhotoTimelineScrubber>(
      find.byType(PhotoTimelineScrubber),
    );
    await _jumpTo(tester, scrubber.itemOffsets[starts[2]]);
    final thirdHeader = sections[2].header!;
    expect(
      find.descendant(of: _dateRow(), matching: find.text(thirdHeader)),
      findsOneWidget,
      reason: '滚过第三组的分组头后，玻璃里的日期行应该换成第三组',
    );
    expect(
      find.descendant(of: _dateRow(), matching: find.text(firstHeader)),
      findsNothing,
      reason: '日期行没跟着当前分组换（还显示着第一组）',
    );
    // 张数也按当前分组。
    expect(
      find.descendant(
        of: _dateRow(),
        matching: find.text(formatCount(sections[2].items.length)),
      ),
      findsOneWidget,
      reason: '日期行的张数不是当前分组的张数',
    );

    // 分类行四段照旧：点「视频」只剩视频，点「全部」回来。
    final total = _items().length;
    await _jumpTo(tester, 0);
    await tester.tap(find.text('视频'));
    await tester.pumpAndSettle();
    final videos = _items().where((item) => item.type == 'video').length;
    expect(videos, greaterThan(0));
    expect(_glass(), findsOneWidget, reason: '筛选后吸顶区还是一整块玻璃');
    expect(_filterRow(), findsOneWidget);
    expect(
      find.descendant(of: _dateRow(), matching: find.byType(Text)),
      findsWidgets,
    );
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(total, _items().length);
  });

  testWidgets('平铺分组：整块玻璃只剩分类行 46', (tester) async {
    AlbumViewSettings.group.value = AlbumGroup.flat;
    await _pumpAlbum(tester);
    await _jumpTo(tester, 400);

    expect(find.byType(DateHeader), findsNothing, reason: '平铺没有日期行');
    expect(_glass(), findsOneWidget);
    expect(tester.getRect(_glass()).height,
        closeTo(kAppSegmentedBarHeight, 0.5),
        reason: '没有日期行时整块玻璃 = 分类行 46');
    expect(tester.getRect(_filterRow()).bottom,
        closeTo(tester.getRect(_glass()).bottom, 0.5));

    AlbumViewSettings.group.value = AlbumGroup.day;
  });
}
