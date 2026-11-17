
import 'dart:ui' as ui;

import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/bar_tint.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/features/album/album_media_filter.dart';
import 'package:album_app/features/album/album_media_filter_bar.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
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

// 相册分类筛选条（「全部 / 照片 / 动态照片 / 视频」那条 46 高的带子）的底衬：
// 从「透明 + blur 8」换成**与日期条同一套主题色浅渐变**。
//
// 为什么改：用户先报「日期条模糊透明有点奇怪」，改完又说「分类条也是一样」。
// 两条横条现在共用一份参数（[BarTint]）：
// - 浅色：alpha 0.10 → 0.02；深色：alpha 0.14 → 0.04，纵向（上沿 → 下沿）；
// - 没有 [BackdropFilter]、没有模糊层、没有玻璃：整条只有一个渐变。
//
// 分类条**不再包玻璃胶囊**：它原来走 premium 档（capture 背景纹理那条管线），
// 真机下拉刷新时会整块发黑。渐变底衬已经承担材质，玻璃这一层是重复的，于是
// 整层删掉——没有玻璃就没有 capture，也就不可能再黑（复现见
// test/refresh_black_bar_test.dart）。
//
// 这份文件守四件事：
// 1. 底衬与日期条是**同一份**渐变（颜色取自 [AppColors.primary]、最大 alpha
//    ≤ 0.16），不是各写各的第二份；
// 2. 条带里没有 GlassContainer / BackdropFilter：材质只有渐变这一层；
// 3. 页面背景仍从渐变里透上来；滚过的内容只被染淡、不被揉开（没有模糊）；
// 4. 文字与数量的对比度逐条量出来（浅/深各一遍），选中用的主题色为什么不
//    到 4.5 也写在里面。

const Key _pageKey = Key('segmented-backdrop-page');

/// 页面背景的替身：条带只要不是实底，就该透出这块绿。
const Color _backdropGreen = Color(0xFF2E7D32);

/// 条带下面「照片纹理」的替身：4px 黑白竖条纹。
Widget _stripes() => SizedBox(
      height: 44,
      child: Row(
        children: [
          for (var i = 0; i < 90; i++)
            Container(
              width: 4,
              color:
                  i.isEven ? const Color(0xFF121212) : const Color(0xFFEFEFEF),
            ),
        ],
      ),
    );

/// 铺满整块的条纹：合成「背景是照片纹理」的那一块用（不会撑破页面）。
Widget _fullStripes() => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 90; i++)
          Expanded(
            child: ColoredBox(
              color:
                  i.isEven ? const Color(0xFF121212) : const Color(0xFFEFEFEF),
            ),
          ),
      ],
    );

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

/// 一条水平扫描线上相邻像素的平均亮度差：0 = 纯色，越大 = 内容纹理越清楚。
double _localContrast(_Shot shot, double y, double fromX, double toX) {
  var sum = 0.0;
  var count = 0;
  var previous = shot.luminanceAt(Offset(fromX, y));
  for (var x = fromX + 1; x < toX; x += 1) {
    final value = shot.luminanceAt(Offset(x, y));
    sum += (value - previous).abs();
    count++;
    previous = value;
  }
  return count == 0 ? 0 : sum / count;
}

int _channel(double a, double b) => ((a - b).abs() * 255).round();

/// 一条带筛选条的相册页：220 高的占位 + 吸顶筛选条 + 一屏条纹。
Widget _page({ScrollController? controller}) => RepaintBoundary(
      key: _pageKey,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: AppGlassBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: CustomScrollView(
              controller: controller,
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 220)),
                const AlbumMediaFilterSliver(
                  counts: AlbumMediaCounts(
                    stillPhotos: 12,
                    livePhotos: 3,
                    videos: 2,
                  ),
                  selected: AlbumMediaFilter.all,
                  onChanged: _noop,
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _stripes(),
                    childCount: 30,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

void _noop(AlbumMediaFilter _) {}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppColors.setDark(false);
  });
  tearDown(() {
    PageBackdropController.spec.value = const PageBackdropSpec.defaultGradient();
    AppColors.setDark(false);
  });

  test('底衬与日期条是同一份渐变：主题色、纵向、最大 alpha ≤ 0.16', () {
    const surface = AppSegmentedBarSurface(child: SizedBox.shrink());
    const header = DateHeader(text: '今天 · 11月15日');
    for (final dark in <bool>[false, true]) {
      AppColors.setDark(dark);
      final gradient = surface.gradient;
      final primary = AppColors.primary;
      expect(gradient, isA<LinearGradient>());
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      for (final color in gradient.colors) {
        expect(color.r, closeTo(primary.r, 1e-9),
            reason: '分类条底衬颜色必须来自主题色（dark=$dark）');
        expect(color.g, closeTo(primary.g, 1e-9));
        expect(color.b, closeTo(primary.b, 1e-9));
      }
      expect(gradient.colors.first.a, closeTo(dark ? 0.14 : 0.10, 1e-9));
      expect(gradient.colors.last.a, closeTo(dark ? 0.04 : 0.02, 1e-9));
      expect(gradient.colors.first.a, lessThanOrEqualTo(BarTint.maxAlpha));
      // 和日期条一模一样：两条横条不许各写一套参数。
      expect(gradient.colors, header.gradient.colors,
          reason: '分类条的渐变与日期条不一致（dark=$dark）：两份参数又分家了');
      expect(gradient.begin, header.gradient.begin);
      expect(gradient.end, header.gradient.end);
    }
  });

  testWidgets('分类条里没有玻璃、也没有模糊：只有一层渐变底衬', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    final pinned = tester.widget<PinnedBarSliver>(find.byType(PinnedBarSliver));
    expect(pinned.background, isNotNull);
    expect(pinned.background!.a, 0.0,
        reason: '吸顶 sliver 垫了不透明色：逐渐变会被截成一条白杠');

    final band = find.byType(AppSegmentedBarSurface);
    expect(band, findsOneWidget);
    final surface = tester.widget<AppSegmentedBarSurface>(band);
    expect(surface.gradient, BarTint.gradient);

    // 条带里没有玻璃：premium 的 capture 就是「刷新时整条发黑」的来源。
    expect(
      find.descendant(of: band, matching: find.byType(GlassContainer)),
      findsNothing,
      reason: '分类条里还有玻璃：premium 的 capture 就是「刷新时整条发黑」的来源',
    );
    expect(
      find.descendant(of: band, matching: find.byType(AppGlassSurface)),
      findsNothing,
    );
    // 底衬自己不含模糊：模糊是**吸顶专用**的一层，挂在条带外面（PinnedBandBlur）。
    expect(
      find.descendant(of: band, matching: find.byType(BackdropFilter)),
      findsNothing,
      reason: '底衬里还嵌着一层模糊：模糊只该是吸顶那一层，不参与底衬',
    );
    final blur = find.ancestor(of: band, matching: find.byType(PinnedBandBlur));
    expect(blur, findsOneWidget,
        reason: '吸顶分类条缺兜底模糊：浅渐变只压掉一成纹理，照片会一条条透出来');
    expect(tester.widget<PinnedBandBlur>(blur.first).blur, kPinnedBandBlur);
    expect(kPinnedBandBlur, inInclusiveRange(6, 8));

    // 几何不变：整条 46 高、铺满宽度，内容带 46 - 上下各 7 = 32。
    final rect = tester.getRect(band);
    expect(rect.height, kAppSegmentedBarHeight);
    expect(rect.width, 360, reason: '渐变要铺满整条（横贯整屏的窄带）');
    expect(
      tester.getRect(find.byKey(AppSegmentedBar.surfaceKey)).height,
      kAppSegmentedBarPillHeight,
    );
    // 四段文字与数量都还在。
    for (final label in ['全部', '照片', '动态照片', '视频']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('页面背景从渐变里透上来：不是实底，也不是纯透明', (tester) async {
    _phone(tester);
    PageBackdropController.spec.value =
        const PageBackdropSpec.solid(_backdropGreen);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    final band = tester.getRect(find.byType(AppSegmentedBarSurface));
    final shot = await _shoot(tester);
    // 取左边的内边距（内容从 12 起）：这一条就是「底衬」本身。
    final sample = Offset(band.left + 3, band.center.dy);
    final pixel = shot.at(sample);
    final t = (sample.dy - band.top) / band.height;
    final expected = BarTint.backplateAt(t, over: _backdropGreen);
    final pixelText = pixel.toString();
    expect(_channel(pixel.r, expected.r), lessThanOrEqualTo(3),
        reason: '条带里不是「渐变叠背景」（实测 $pixelText，期望 $expected）');
    expect(_channel(pixel.g, expected.g), lessThanOrEqualTo(3));
    expect(_channel(pixel.b, expected.b), lessThanOrEqualTo(3));
    expect(_channel(pixel.b, _backdropGreen.b), greaterThan(6),
        reason: '条带里看不到主题色：底衬没画（实测 $pixelText）');
    expect(_channel(pixel.r, AppColors.bgPage.r), greaterThan(20),
        reason: '条带又回到 bgPage 那块白底：实底会把页面背景截成一条白杠');
  });

  testWidgets('吸顶：滚过的纹理由兜底模糊揉开（残留 < 0.02）', (tester) async {
    _phone(tester);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());

    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_page(controller: controller));
    await tester.pumpAndSettle();

    controller.jumpTo(320);
    await tester.pumpAndSettle();

    final band = tester.getRect(find.byType(AppSegmentedBarSurface));
    final shot = await _shoot(tester);
    // 条带上沿 3px 那条（内容从 +7 开始）：整条都是「底衬」。
    final inBand = _localContrast(
      shot,
      band.top + 3,
      band.left + 4,
      band.right - 4,
    );
    // 对照组：条带下面 8px 处是没被遮住的同一条纹。
    final below = _localContrast(
      shot,
      band.bottom + 8,
      band.left + 4,
      band.right - 4,
    );
    final ratio = below == 0 ? 0.0 : inBand / below;

    final belowText = below.toStringAsFixed(4);
    final ratioText = ratio.toStringAsFixed(3);
    expect(below, greaterThan(0.1),
        reason: '对照组本身没有纹理，这条用例就测不出东西（below=$belowText）');
    expect(find.byType(PinnedBandBlur), findsOneWidget);
    // 吸顶条的验收口径：兜底模糊把纹理揉开，条带里只剩一层柔和色雾（< 0.02，
    // 纯渐变叠条纹时是 ≈0.19）。
    expect(inBand, lessThan(0.02),
        reason: '吸顶分类条里的照片纹理没被揉开（inBand=${inBand.toStringAsFixed(4)} / '
            'below=$belowText = $ratioText）：照片会一条条从字后面透出来');
    expect(ratio, lessThan(0.10),
        reason: '条带里的纹理残留太高（ratio=$ratioText）：兜底模糊没起作用');
  });

  testWidgets('非吸顶（封面选择页 AppBar 那一份）：纯渐变，纹理只被染淡 ≤ 0.9',
      (tester) async {
    _phone(tester);
    // 合成一块：条纹当背景，分类条只铺在上面（不吸顶、没有兜底模糊）。
    await tester.pumpWidget(
      RepaintBoundary(
        key: _pageKey,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                const Positioned.fill(child: SizedBox.shrink()),
                Positioned.fill(child: _fullStripes()),
                const Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: 220),
                    child: AppSegmentedBarSurface(
                      child: AlbumMediaFilterBar(
                        counts: AlbumMediaCounts(
                          stillPhotos: 12,
                          livePhotos: 3,
                          videos: 2,
                        ),
                        selected: AlbumMediaFilter.all,
                        onChanged: _noop,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final band = tester.getRect(find.byType(AppSegmentedBarSurface));
    // 不吸顶的那一份没有兜底模糊。
    expect(find.byType(PinnedBandBlur), findsNothing);
    final shot = await _shoot(tester);
    // 同一条 x 窗口（条纹是竖的，窗口相位才对得上）：条带里与条带下各取一条。
    // 内容从 12 起，4~11 这一段落在左右内边距里，只有底衬。
    // 取条带**最上沿**那一行（渐变最浓，alpha 0.10）：这是残留最低的一档。
    final inBand =
        _localContrast(shot, band.top + 3, band.left + 4, band.left + 11);
    final outside =
        _localContrast(shot, band.bottom + 8, band.left + 4, band.left + 11);
    final ratio = outside == 0 ? 0.0 : inBand / outside;
    final ratioText = ratio.toStringAsFixed(3);
    expect(outside, greaterThan(0.1),
        reason: '条带外面没有纹理，这条用例测不出东西（outside='
            '${outside.toStringAsFixed(4)}）');
    expect(ratio, lessThanOrEqualTo(0.95),
        reason: '非吸顶条的纹理残留 ratio=$ratioText 偏高：底衬被加了东西');
    expect(ratio, greaterThan(0.85),
        reason: '非吸顶条的纹理被压掉太多（ratio=$ratioText）：纯渐变只该染淡一成');
  });

  testWidgets('文字与数量的对比度：选中/未选中在浅色与深色下都 ≥ 4.5',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    // 选中段的文字色 = 主题色**在本条内**混黑 [kSegmentedSelectedInkDarken]。
    // 先钉住这条局部规则：全局主题色不动，只有这条带子里的选中色被加深。
    expect(kSegmentedSelectedInkDarken, 0.12);
    for (final dark in <bool>[false, true]) {
      AppColors.setDark(dark);
      final ink = segmentedSelectedInk;
      expect(ink.r, closeTo(AppColors.primary.r * 0.88, 1e-9),
          reason: '局部加深不是「主题色混黑 12%」（dark=$dark）');
      expect(ink.g, closeTo(AppColors.primary.g * 0.88, 1e-9));
      expect(ink.b, closeTo(AppColors.primary.b * 0.88, 1e-9));
    }
    // 全局主题色没被这条带子改掉：浅色仍是品牌蓝。
    AppColors.setDark(false);
    final bare = AppAccent.contrastRatio(AppColors.bgPage, AppColors.primary);
    expect(AppColors.primary, AppAccent.brand,
        reason: '全局主题色不许为这条带子改（底部 tab / 按钮都在用）');
    expect(bare, closeTo(4.13, 0.05),
        reason: '主题色本身对纯页面底色就只有 4.13:1，这是选中色要局部加深的原因');

    // 文字落在条带正中那一行（t = 0.5），最坏的一档是条带上沿（t = 0，alpha 最大）。
    final measured = <bool, Map<String, double>>{};
    for (final dark in <bool>[false, true]) {
      AppColors.setDark(dark);
      double atRow(double t, Color fg) =>
          AppAccent.contrastRatio(BarTint.backplateAt(t), fg);
      final ink = segmentedSelectedInk;
      measured[dark] = <String, double>{
        '选中文案@中线': atRow(0.5, ink),
        '选中文案@上沿': atRow(0, ink),
        '未选中文案@中线': atRow(0.5, appTabBarInactiveColor),
        '未选中数量@中线': atRow(0.5, AppColors.textOnGlass),
      };
      for (final entry in measured[dark]!.entries) {
        expect(
          entry.value,
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} 只有 ${entry.value.toStringAsFixed(2)}:1'
              '（dark=$dark）：低于 WCAG AA 4.5',
        );
      }
    }
    // 实测值钉住（浅色 / 深色）：参数被谁动过都会在这里露出来。
    expect(measured[false]!['选中文案@中线']!, closeTo(4.75, 0.05));
    expect(measured[false]!['选中文案@上沿']!, closeTo(4.52, 0.05));
    expect(measured[true]!['选中文案@中线']!, closeTo(5.46, 0.05));
    expect(measured[true]!['选中文案@上沿']!, closeTo(4.98, 0.05));
    expect(measured[false]!['未选中文案@中线']!, closeTo(8.08, 0.10));
    expect(measured[false]!['未选中数量@中线']!, closeTo(5.72, 0.05));
    expect(measured[true]!['未选中数量@中线']!, closeTo(7.60, 0.05));

    // 组件真的按这套颜色画：选中段与数量都是那个局部色，未选中是中性灰。
    AppColors.setDark(false);
    await tester.pump();
    expect(tester.widget<Text>(find.text('全部')).style!.color,
        segmentedSelectedInk,
        reason: '选中段没有用局部加深后的主题色');
    expect(tester.widget<Text>(find.text('照片')).style!.color,
        appTabBarInactiveColor);
    // 选中段的数量与文案同色（降透明度到 0.9 也只有 3.99:1，过不了 4.5）。
    final segmentTexts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(AppSegmentedBar.segmentKey(0)),
            matching: find.byType(Text),
          ),
        )
        .toList();
    expect(segmentTexts, hasLength(2), reason: '选中段应该是「文案 + 数量」两段文字');
    expect(segmentTexts[1].style!.color, segmentedSelectedInk,
        reason: '选中段的数量没有跟着局部色走：会掉回 2.6~3.9:1');
    expect(segmentTexts[1].style!.fontSize, lessThan(segmentTexts[0].style!.fontSize!),
        reason: '数量靠字号分主次，不靠把颜色调淡');
  });
}
