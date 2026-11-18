import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/album_view_settings.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/widgets/app_chrome_glass_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_glass_tone.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:album_app/widgets/date_header.dart';
import 'package:album_app/widgets/pinned_bar_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LightweightLiquidGlass;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

// 「下拉刷新时吸顶条整块发黑」的复现 / 回归用例（分类条 + 日期条）。
//
// 现象：真机上下拉刷新时，吸顶的「全部 / 照片 / 动态照片 / 视频」分类条与吸顶
// 日期条整块发黑，白底页面上像被挖了一条黑洞。
//
// 根因：那两条原来各是一层玻璃（AppGlassSurface → GlassContainer，premium 档）。
// premium 的实现是
//   GlassContainer -> AdaptiveGlass -> LiquidGlass.withOwnLayer -> LiquidGlassLayer
// 的「全管线」路径：背景靠 BackdropGroup / RepaintBoundary 的 capture 提供。
// 刷新那几帧列表整体重建、指示器还在动画，玻璃层**被换掉**的瞬间 capture 还没
// 就绪，采到空纹理、叠上 tint 就是一块近黑（机制说明见
// test/feed_refresh_glass_test.dart）。
//
// 这一轮的契约：三条吸顶条（分类条 / 日期条 / 朋友圈日期条）与底部 footer 是
// **同一块玻璃**（AppChromeGlassBar），所以黑条不靠「把它拆成渐变」来躲，而是
// 靠**不重建**来挡：
// - 玻璃层挂常量 key 的 RepaintBoundary（AppChromeGlassBar.layerKey）+ 固定
//   位置的 AppGlassSurface（AppChromeGlassBar.surfaceKey）；
// - 刷新全程（下拉、松手、回包、结束）这几个 Element 必须一直是同一个；
// - 逐帧采条带区域，亮度不许掉到近黑（> 0.5）。
//
// 怎么复现（沿用 feed_refresh_glass_test.dart 的办法）：flutter_tester 里
// ImageFilter.isShaderFilterSupported 是 false，premium 的 GPU 路径根本不参与
// 光栅化，像素只能兜「没有近黑填充」；真正的结构证据是「刷新全程玻璃层是不是
// 同一个 Element」——换 Element 就是真机上换材质、重新抓 capture 的那一帧。

const Key _pageKey = Key('refresh-black-bar-page');

/// 条带亮度低于这条线就算「近黑填充」。
const double kBlackBandLuminanceFloor = 0.5;

/// 刷新四个阶段之间，条带像素允许的最大通道差：**3/255**。
///
/// 依据：修复前「页面底色 ↔ 卡片白」这一档（刷新时条带背后真正会变的那一档）
/// 实测就是 3/255（45% 背景权重 × 8/255）；3 以下人眼在这条 36px 高的柔和条带
/// 上分辨不出（约 1.2% 亮度）。定位与实测数据见
/// test/pinned_bar_color_stable_test.dart 的文件头。
const int kRefreshBandColorDelta = 3;

/// 条带的采样点：只取左侧内边距那一条（文字从 16 起，避开字），量到底衬本身。
List<Color> _bandColors(_Shot shot, Rect band) => <Color>[
      for (var dx = 3.0; dx <= 10.0; dx += 1)
        for (var dy = 2.0; dy <= band.height - 2; dy += 4)
          shot.at(Offset(band.left + dx, band.top + dy)),
    ];

int _maxBandDelta(List<Color> a, List<Color> b) {
  int channel(double v) => (v * 255).round();
  var worst = 0;
  for (var i = 0; i < a.length; i++) {
    final deltas = <int>[
      (channel(a[i].r) - channel(b[i].r)).abs(),
      (channel(a[i].g) - channel(b[i].g)).abs(),
      (channel(a[i].b) - channel(b[i].b)).abs(),
    ];
    final delta = deltas.reduce((x, y) => x > y ? x : y);
    if (delta > worst) worst = delta;
  }
  return worst;
}

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

  testWidgets('下拉刷新 + 吸顶态刷新：玻璃层不重建、不出现近黑填充', (tester) async {
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
    // 没有吸顶的就取内容流第一条。**内容流那条是透明条**（没有玻璃），
    // 所以它只参与像素采样，不参与「玻璃层是同一个 Element」的断言。
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
    final glassElements = <String, Element>{};
    final layerElements = <String, Element>{};

    void checkBand(String phase, String label, Finder band,
        {required bool pinned}) {
      // 吸顶的那一份是 footer 同款玻璃：AppChromeGlassBar + AppGlassSurface。
      // 相册页是一整块玻璃同时装分类行与日期行，所以玻璃是这一行的**祖先**；
      // 单行形态（朋友圈日期条）才是自己带着玻璃。
      final inside = find.descendant(
        of: band,
        matching: find.byType(AppChromeGlassBar),
      );
      final glass = inside.evaluate().isEmpty
          ? find.ancestor(of: band, matching: find.byType(AppChromeGlassBar))
          : inside;
      if (!pinned) {
        // 内容流里的日期条是**透明条**：没有玻璃、也没有模糊。
        expect(glass, findsNothing,
            reason: '$phase：$label不是吸顶的那一条，不该包玻璃');
        return;
      }
      expect(glass, findsOneWidget,
          reason: '$phase：$label不是 footer 同款玻璃（AppChromeGlassBar）');
      final surface = tester.widget<AppGlassSurface>(
        find.descendant(of: glass, matching: find.byType(AppGlassSurface)),
      );
      // 与 footer 同一组开关：premium / 自建层 / scrim。
      expect(surface.preferPremium, isTrue, reason: '$phase：$label丢了 premium');
      expect(surface.useOwnLayer, isTrue, reason: '$phase：$label丢了自建层');
      expect(surface.scrim, isTrue, reason: '$phase：$label丢了 scrim');
      expect(surface.requestedQuality, AppChromeGlassBar.preferredQuality);

      // 结构证据：刷新全程是**同一个玻璃 Element**（重建就是黑条那一帧）。
      final glassElement = glass.evaluate().first;
      final previous = glassElements[label];
      if (previous == null) {
        glassElements[label] = glassElement;
      } else {
        expect(glassElement, same(previous),
            reason: '$phase：$label的玻璃层被重建/换掉了：真机上这就是'
                '「刷新时材质断一下、整条发黑」的那一帧');
      }
      // 玻璃外面那层 RepaintBoundary 也一样：常量 key，位置不变。
      final layerInside = find.descendant(
        of: band,
        matching: find.byKey(AppChromeGlassBar.layerKey),
      );
      final layer = layerInside.evaluate().isEmpty
          ? find.ancestor(
              of: band,
              matching: find.byKey(AppChromeGlassBar.layerKey),
            )
          : layerInside;
      expect(layer, findsOneWidget,
          reason: '$phase：$label的玻璃层没有常量 key 的重绘边界');
      final layerElement = layer.evaluate().first;
      final previousLayer = layerElements[label];
      if (previousLayer == null) {
        layerElements[label] = layerElement;
      } else {
        expect(layerElement, same(previousLayer),
            reason: '$phase：$label的重绘边界被换掉了');
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
    // 两条带子全程都是同一块玻璃（Element 没换过）。
    expect(glassElements.keys, containsAll(<String>['分类条', '日期条']));
    expect(layerElements.keys, containsAll(<String>['分类条', '日期条']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('吸顶条的底衬是玻璃：不是色块、更不是黑洞', (tester) async {
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

    // 这条带子的底衬由 AppChromeGlassBar 画（与 footer 同一份），不再是渐变：
    // 这里不再有「主题色浅渐变」那一层。
    final band = find.byType(AppSegmentedBarSurface);
    // 分类行与日期行在**同一块**玻璃里：玻璃是这一行的祖先。
    expect(
      find.ancestor(of: band, matching: find.byType(AppChromeGlassBar)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: band, matching: find.byType(DecoratedBox)),
      findsWidgets,
      reason: '玻璃的 scrim / 描边 / 高光都是 DecoratedBox：底衬没画上去',
    );

    final shot = await _shoot(tester);
    final rect = tester.getRect(band);
    expect(_bandMinLuminance(shot, rect), greaterThan(0.7),
        reason: '条带整体偏暗（实测最暗像素 '
            '${_bandMinLuminance(shot, rect).toStringAsFixed(3)}）：底衬没画对');
  });

  testWidgets('朋友圈吸顶日期条：下拉刷新全程是同一块玻璃', (tester) async {
    _phoneViewport(tester);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());
    addTearDown(installFakeApi(
      json: jsonEncode({
        'items': [
          for (var i = 0; i < 8; i++)
            {
              'id': i + 1,
              'author_id': 1,
              'author_nickname': '妈妈',
              'content': '第 $i 条动态',
              'posted_at':
                  '2026-01-${(i % 4 + 1).toString().padLeft(2, '0')}T10:00:00Z',
              'medias': <dynamic>[],
            },
        ],
        'next_cursor': null,
      }),
    ));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _pageKey,
        child: MaterialApp(theme: buildAppTheme(), home: const FeedPage()),
      ),
    );
    await tester.pumpAndSettle();

    final band = find.byType(DateHeader).first;
    expect(band, findsOneWidget, reason: '动态流顶部那条吸顶日期条要在');

    Element? glassElement;
    Element? layerElement;
    // 变色：四个阶段各存一份条带像素与墨色（比「合成色/墨色有没有变」）。
    final bandColors = <String, List<Color>>{};
    final inks = <String, Color>{};

    Future<void> sample(String phase) async {
      // 玻璃层与它的重绘边界：刷新全程必须是同一个 Element（换掉就是真机上
      // 重新抓 capture、整条发黑的那一帧）。
      final glass = find
          .descendant(of: band, matching: find.byType(AppChromeGlassBar))
          .evaluate();
      expect(glass, hasLength(1), reason: '$phase：吸顶日期条不是 footer 同款玻璃');
      if (glassElement == null) {
        glassElement = glass.first;
      } else {
        expect(glass.first, same(glassElement),
            reason: '$phase：吸顶日期条的玻璃层被重建了');
      }
      final layer = find
          .descendant(of: band, matching: find.byKey(AppChromeGlassBar.layerKey))
          .evaluate();
      expect(layer, hasLength(1), reason: '$phase：玻璃层没有常量 key 的重绘边界');
      if (layerElement == null) {
        layerElement = layer.first;
      } else {
        expect(layer.first, same(layerElement),
            reason: '$phase：吸顶日期条的重绘边界被换掉了');
      }

      // 固定底衬：每一帧都在、颜色是同一个（页面底色 + 0.9）。这层把「背后
      // 内容在动」从合成色里挤出去，也是「刷新时不变色」的实现（见
      // AppChromeGlassBar.pinned / kAppChromePinnedBackplateAlpha）。
      // 这一帧的玻璃表面（测试环境里 tier 会退化成不透明，所以量参数本身；
      // 玻璃分支真的挂上这一层见 test/pinned_chrome_bar_test.dart）。
      final surface = tester.widget<AppGlassSurface>(
        find.descendant(of: band, matching: find.byType(AppGlassSurface)),
      );
      expect(surface.backplate, isNotNull,
          reason: '$phase：吸顶日期条没有固定底衬（会跟着背后内容变色）');
      expect(surface.backplate!.a, closeTo(kAppChromePinnedBackplateAlpha, 1e-9),
          reason: '$phase：底衬的不透明度被改了');
      expect(surface.backplate!.withValues(alpha: 1.0),
          AppColors.bgPage.withValues(alpha: 1.0),
          reason: '$phase：底衬不是页面底色');

      // 墨色：刷新全程不许翻档（(a) 那条路）。
      inks[phase] = appGlassToneInk();

      // 像素：条带里不许有近黑填充。
      final shot = await _shoot(tester);
      final rect = tester.getRect(band);
      bandColors[phase] = _bandColors(shot, rect);
      final darkest = _bandMinLuminance(shot, rect);
      expect(darkest, greaterThan(kBlackBandLuminanceFloor),
          reason: '$phase：吸顶日期条出现近黑填充（最暗像素 '
              '${darkest.toStringAsFixed(3)}）');
    }

    await sample('刷新前');

    final list = find.byType(CustomScrollView);
    final gesture = await tester.startGesture(tester.getCenter(list));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await sample('下拉中');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    await sample('释放瞬间');
    await tester.pump(const Duration(milliseconds: 200));
    await sample('刷新中');
    await tester.pumpAndSettle();
    await sample('刷新完成');

    // 变色验收：四个阶段（刷新前 / 下拉中 / 释放瞬间 / 刷新完成 —— 这里还多
    // 采了「刷新中」）的条带像素，最大通道差 ≤ 3/255。
    const phases = <String>['刷新前', '下拉中', '释放瞬间', '刷新中', '刷新完成'];
    expect(bandColors.keys, containsAll(phases));
    final reference = bandColors['刷新前']!;
    for (final phase in phases) {
      final delta = _maxBandDelta(reference, bandColors[phase]!);
      expect(delta, lessThanOrEqualTo(kRefreshBandColorDelta),
          reason: '$phase：条带颜色相对「刷新前」差了 $delta/255，用户看到的就是'
              '「下拉刷新时吸顶日期条变色」');
    }
    // (a) 自动墨色翻档这条排除了：四个阶段量到的 ink 是同一个。
    expect(inks.values.toSet(), hasLength(1),
        reason: '刷新期间自动墨色翻了档：$inks');

    expect(glassElement, isNotNull);
    expect(layerElement, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
