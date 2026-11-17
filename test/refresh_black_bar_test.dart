import 'dart:async';
import 'dart:ui' as ui;

import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/album_view_settings.dart';
import 'package:album_app/core/design/bar_tint.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:album_app/widgets/date_header.dart';
import 'package:album_app/widgets/pinned_band_blur.dart';
import 'package:album_app/widgets/pinned_bar_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, LightweightLiquidGlass;
import 'package:shared_preferences/shared_preferences.dart';

// 「下拉刷新时分类条整块发黑」的复现 / 回归用例（同一条断言也盖住日期条）。
//
// 现象：真机上下拉刷新时，「全部 / 照片 / 动态照片 / 视频」那条横条整块发黑，
// 白底页面上像被挖了一条黑洞。
//
// 根因：分类条原来是 AppSegmentedBarSurface（透明 + blur 8）里再套一层
// AppGlassSurface → GlassContainer，走 premium 档。premium 的实现是
//   GlassContainer -> AdaptiveGlass -> LiquidGlass.withOwnLayer -> LiquidGlassLayer
// 的「全管线」路径：背景靠 BackdropGroup / RepaintBoundary 的 capture 提供。
// 刷新那几帧列表整体重建、指示器还在动画，玻璃层换掉的瞬间 capture 还没就绪，
// 采到空纹理、叠上 tint 就是一块近黑——和「刷新时黑卡」是同一个根因
// （机制说明见 test/feed_refresh_glass_test.dart）。
//
// 修复：分类条不再包玻璃（渐变底衬已经承担材质）。两条横条现在都只有「一层
// 主题色浅渐变 + 文字」，吸顶的那一份再多一层**很轻的**兜底模糊
// （[PinnedBandBlur]，纯 BackdropFilter，不抓 capture）。所以：
// - 条带里不许再出现 GlassContainer / AppGlassSurface（capture 黑条的来源）；
// - 那层兜底模糊在刷新全程必须是**同一个 Element**（重建/换材质才是黑条真正
//   发生的地方）；
// - 逐帧采条带区域，亮度不许掉到近黑。
//
// 怎么复现（沿用 feed_refresh_glass_test.dart 的办法）：flutter_tester 里
// ImageFilter.isShaderFilterSupported 是 false，premium 的 GPU 路径根本不参与
// 光栅化，修复前后拍出来是同一张图。所以像素只用来兜「没有近黑填充」，真正
// 的结构证据是「条带里有没有需要 capture 的玻璃」，以及刷新全程有没有换过那层
// 模糊的 Element。

const Key _pageKey = Key('refresh-black-bar-page');

/// 条带亮度低于这条线就算「近黑填充」。
const double kBlackBandLuminanceFloor = 0.5;

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

  double luminanceAt(Offset global) => at(global).computeLuminance();
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

/// 条带里最暗的一像素亮度：只采左右内边距那一条（文字从 12/16 起，避开字），
/// 这样量到的就是「底衬」本身，正文的深色不会把结果拖下去。
double _bandMinLuminance(_Shot shot, Rect band) {
  var min = 1.0;
  for (var dx = 3.0; dx <= 8.0; dx += 1) {
    for (var dy = 2.0; dy <= band.height - 2; dy += 2) {
      final value = shot.luminanceAt(Offset(band.left + dx, band.top + dy));
      if (value < min) min = value;
    }
  }
  return min;
}

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

/// 三组、每组 8 张：分组头与吸顶筛选条都在屏上，列表也够长。
List<Media> _items() => <Media>[
      for (var day = 1; day <= 3; day++)
        for (var i = 0; i < 8; i++)
          _photo(day * 100 + i, DateTime(2024, 11, day, 9, i)),
    ];

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

  testWidgets('下拉刷新 + 吸顶态刷新：条带无玻璃、模糊层不重建、不出现近黑填充',
      (tester) async {
    _phoneViewport(tester);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());

    final items = _items();
    final album = Album(
      id: 7,
      title: '秋天到冬天',
      coverThumb: null,
      mediaCount: items.length,
      createdAt: DateTime(2020, 5, 1),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: _pageKey,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: AlbumDetailPage(
            album: album,
            loader: (id) async => AlbumDetail(album: album, items: items),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final filterBand = find.byType(AppSegmentedBarSurface);
    expect(filterBand, findsOneWidget, reason: '这页得有分类条，否则测的不是那条带子');
    expect(find.byType(DateHeader).evaluate(), isNotEmpty, reason: '这页得有日期条');

    // 这一帧要量的日期条：优先取吸顶的那一条（照片正从它下面滚过去），
    // 没有吸顶的就取内容流里第一条。
    (Finder, bool) dateBand() {
      final pinned = find
          .descendant(
            of: find.byType(PinnedBarSliver),
            matching: find.byType(DateHeader),
          )
          .evaluate();
      if (pinned.isEmpty) return (find.byType(DateHeader).first, false);
      return (find.byElementPredicate((e) => e == pinned.first), true);
    }

    final phases = <String, double>{};
    final blurElements = <String, Element>{};

    void checkBand(String phase, String label, Finder band, {required bool pinned}) {
      // 1. 条带里不许有需要 capture 的玻璃表面。
      expect(
        find.descendant(of: band, matching: find.byType(GlassContainer)),
        findsNothing,
        reason: '$phase：$label里还有一层玻璃容器（premium 的 capture 就是'
            '「刷新时整块发黑」的来源）',
      );
      expect(
        find.descendant(of: band, matching: find.byType(AppGlassSurface)),
        findsNothing,
        reason: '$phase：$label里还有一层 AppGlassSurface',
      );
      // 底衬自己不含模糊：模糊是吸顶专用的一层，挂在条带外面。
      expect(
        find.descendant(of: band, matching: find.byType(BackdropFilter)),
        findsNothing,
        reason: '$phase：$label自己还嵌着一层模糊/采样层',
      );
      final blur =
          find.ancestor(of: band, matching: find.byType(PinnedBandBlur)).evaluate();
      if (!pinned) {
        expect(blur, isEmpty,
            reason: '$phase：$label不是吸顶的那一条，不该带兜底模糊');
        return;
      }
      expect(blur, hasLength(1),
          reason: '$phase：$label外面那层兜底模糊不见了（滚动内容会一条条透出来）');
      expect((blur.first.widget as PinnedBandBlur).blur, kPinnedBandBlur);
      expect(kPinnedBandBlur, inInclusiveRange(6, 8));
      final previous = blurElements[label];
      if (previous == null) {
        blurElements[label] = blur.first;
      } else {
        expect(blur.first, same(previous),
            reason: '$phase：$label的兜底模糊层被重建/换掉了：真机上这就是'
                '「刷新时材质断一下、整条发黑」的那一帧');
      }
    }

    Future<void> sample(String phase) async {
      final (dateFinder, datePinned) = dateBand();
      checkBand(phase, '分类条', filterBand, pinned: true);
      checkBand(phase, '日期条', dateFinder, pinned: datePinned);

      // 2. 像素：采条带区域，不许有近黑填充。
      final shot = await _shoot(tester);
      final bands = <String, Rect>{
        '分类条': tester.getRect(filterBand),
        '日期条': tester.getRect(dateFinder),
      };
      var darkest = 1.0;
      for (final entry in bands.entries) {
        final value = _bandMinLuminance(shot, entry.value);
        phases['$phase·${entry.key}'] = value;
        if (value < darkest) darkest = value;
      }
      expect(
        darkest,
        greaterThan(kBlackBandLuminanceFloor),
        reason: '$phase：条带里出现近黑填充（最暗像素 ${darkest.toStringAsFixed(3)}），'
            '刷新时用户看到的就是这条黑洞',
      );
    }

    await sample('刷新前');

    // 按住列表往下拖：RefreshIndicator 收到 overscroll，内容跟着下移。
    final list = find.byType(CustomScrollView);
    final gesture = await tester.startGesture(tester.getCenter(list));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await sample('下拉中');

    // 松手：刷新开始，指示器回弹、数据替换，材质最容易在这几帧换掉。
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    await sample('释放瞬间');

    await tester.pump(const Duration(milliseconds: 200));
    await sample('刷新中');

    await tester.pumpAndSettle();
    await sample('刷新完成');

    // 再来一遍「吸顶态」：滚到日期头吸住的位置，让照片正从它下面过，然后
    // 用 RefreshIndicator.show() 走同一个刷新回调（下拉只能在顶部触发）。
    final position = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    ).position;
    position.jumpTo(260);
    await tester.pumpAndSettle();
    await sample('吸顶刷新前');

    final indicator =
        tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator));
    unawaited(indicator.show());
    await tester.pump(const Duration(milliseconds: 16));
    await sample('吸顶刷新中');
    await tester.pump(const Duration(milliseconds: 120));
    await sample('吸顶刷新中（回包后）');
    await tester.pumpAndSettle();
    await sample('吸顶刷新完成');

    // 九个阶段 × 两条带子。
    expect(phases, hasLength(18), reason: '每个阶段都要同时量到两条带子');
    final darkest = phases.values.reduce((a, b) => a < b ? a : b);
    expect(darkest, greaterThan(kBlackBandLuminanceFloor),
        reason: '整段刷新里条带最暗的那一像素是 ${darkest.toStringAsFixed(3)}');
    // 吸顶那一份确实带着兜底模糊，而且刷新全程是同一个 Element。
    expect(blurElements.keys, contains('分类条'));
    expect(blurElements.keys, contains('日期条'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('渐变底衬本身是「浅」的：条带亮度接近页面底色（不是色块）', (tester) async {
    _phoneViewport(tester);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());
    final items = _items();
    final album = Album(
      id: 7,
      title: '秋天到冬天',
      coverThumb: null,
      mediaCount: items.length,
      createdAt: DateTime(2020, 5, 1),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: _pageKey,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: AlbumDetailPage(
            album: album,
            loader: (id) async => AlbumDetail(album: album, items: items),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shot = await _shoot(tester);
    final band = tester.getRect(find.byType(AppSegmentedBarSurface));
    final surface = tester.widget<AppSegmentedBarSurface>(
      find.byType(AppSegmentedBarSurface),
    );
    // 底衬就是那份浅渐变（主题色、很淡）。
    expect(surface.gradient.colors, BarTint.gradient.colors);
    expect(surface.gradient.colors.first.a, lessThanOrEqualTo(BarTint.maxAlpha));
    // 这一页条带后面是页面背景的渐变（不是纯 bgPage），所以这里只钉两件事：
    // 条带整体是亮的（不是色块、更不是黑洞），而且被主题色染过（蓝通道偏高）。
    final pixel = shot.at(Offset(band.left + 3, band.center.dy));
    expect(_bandMinLuminance(shot, band), greaterThan(0.7),
        reason: '条带整体偏暗：浅渐变变成了色块（实测最暗像素 '
            '${_bandMinLuminance(shot, band).toStringAsFixed(3)}）');
    expect(((pixel.b - pixel.r) * 255).round(), greaterThanOrEqualTo(8),
        reason: '条带里看不到主题色（实测 $pixel）：底衬没画上去');
  });
}
