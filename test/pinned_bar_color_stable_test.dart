import 'dart:ui' as ui;

import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/widgets/app_chrome_glass_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, LightweightLiquidGlass;

// **吸顶条「下拉刷新时变色」的定位 + 回归。**
//
// 现象：真机上下拉刷新，吸顶日期条的颜色会变一下（不是发黑，是变浅/变深）。
//
// 定位：
// (a) 自动墨色翻档 —— 排除。墨色只由 [AppBackdropSample] 决定，而它只在「换背
//     景图 / 切明暗」时重采（_BackdropSampleScope 的 signature = spec + 明暗），
//     刷新不动它：refresh_black_bar_test.dart 的四个阶段量到的 ink 逐帧相同。
// (b) 背后内容位移 —— 就是它。玻璃的 scrim 只压 0.55，剩下 45% 的背景权重直接
//     采条带背后的像素；下拉刷新时列表整体下移，条带底下从「卡片白」换到「页面
//     底色」甚至照片，合成色就跟着漂。
//
// 实测（premium 档，含玻璃本体；背景换成纯白 / 纯黑 / 页面底色各渲染一次）：
//   · 不画底衬：白 [243,244,246] / 黑 [148,148,150]，最大通道差 **96/255**；
//   · 0.9 底衬：白 [247,248,250] / 黑 [237,238,240]，差 **10/255**；
//     真实页面内的「页面底色 ↔ 卡片白」只剩 **1/255**。
//
// 修法：吸顶条在玻璃**之上、内容之下**加一层「页面底色 + 0.9」的固定底衬
// （[AppChromeGlassBar.pinned] / [kAppChromePinnedBackplateAlpha]）。可漂移权重
// 从 45% 压到 (1 - 0.9) x 45% ≈ 4.5%，玻璃本体（折射/模糊/scrim）仍在它上面，
// 不换材质、不重建 Element；footer 不画这层，观感不变。
//
// 阈值为什么是 3/255：修复前「页面底色 ↔ 卡片白」这一档实测就是 3/255
// （0.45 x 8）——3 正好是「真实页面内容之间不许再出现看得见的漂移」这条线，
// 而人眼在这条 36px 高的柔和条带上分辨不出 ≤3 的差（约 1.2% 亮度）。极端档
// （纯黑 ↔ 纯白照片）修复前 96/255，加底衬后 10/255；要把它也压到 3 以下得把
// 底衬提到 0.97，那时吸顶条就是一块不透明的页面底色，玻璃也就没了。

const Key _pageKey = Key('pinned-color-page');

/// 条带在「背后内容换了」时允许的最大通道差：3/255（依据见文件头）。
const int kPinnedBandColorDeltaLimit = 3;

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
    return Color.fromARGB(255, bytes[offset], bytes[offset + 1], bytes[offset + 2]);
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
  final shot = _Shot(data.buffer.asUint8List(), image.width, image.height, origin);
  image.dispose();
  return shot;
}

/// 两个颜色之间最大的通道差（0~255）。
int maxChannelDelta(Color a, Color b) {
  int channel(double v) => (v * 255).round();
  final deltas = <int>[
    (channel(a.r) - channel(b.r)).abs(),
    (channel(a.g) - channel(b.g)).abs(),
    (channel(a.b) - channel(b.b)).abs(),
  ];
  return deltas.reduce((x, y) => x > y ? x : y);
}

/// 两帧里同一批采样点的最大通道差。
int maxBandDelta(List<Color> a, List<Color> b) {
  var worst = 0;
  for (var i = 0; i < a.length; i++) {
    final delta = maxChannelDelta(a[i], b[i]);
    if (delta > worst) worst = delta;
  }
  return worst;
}

/// 条带的采样点：只取左侧内边距那一条（文字从 16 起，避开字），
/// 量到的就是「底衬」本身。
List<Offset> _bandPoints(Rect band) => <Offset>[
      for (var dx = 3.0; dx <= 10.0; dx += 1)
        for (var dy = 2.0; dy <= band.height - 2; dy += 4)
          Offset(band.left + dx, band.top + dy),
    ];

/// 一块 36 高的吸顶条，浮在一块纯色背景上（模拟「条带背后是什么内容」）。
///
/// 注入 premium 档：只有这样才会真的走玻璃分支（[GlassContainer] 存在），
/// 否则 AppGlassSurface 退化成不透明表面，量到的就不是「合成色会不会漂」。
Widget _host(
  Color backdrop, {
  double backplateAlpha = kAppChromePinnedBackplateAlpha,
}) =>
    RepaintBoundary(
      key: _pageKey,
      child: AppGlassScope(
        quality: GlassQuality.premium,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: backdrop)),
                Align(
                  alignment: Alignment.topCenter,
                  child: AppChromeGlassBar(
                    radius: kAppChromePinnedRadius,
                    showBorder: false,
                    showHighlight: false,
                    backplateAlpha: backplateAlpha,
                    builder: (context, ink) => SizedBox(
                      height: 36,
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '8月20日',
                            style: appChromeLabelStyle(ink),
                          ),
                        ),
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

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 300);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 在 [backdrop] 上渲染一次吸顶条，返回条带采样点的颜色。
Future<List<Color>> _bandOver(
  WidgetTester tester,
  Color backdrop, {
  double backplateAlpha = kAppChromePinnedBackplateAlpha,
}) async {
  await tester.pumpWidget(_host(backdrop, backplateAlpha: backplateAlpha));
  await tester.pump(const Duration(milliseconds: 50));
  // 真的是玻璃分支才算数（否则量到的是一块不透明底，测不出漂移）。
  expect(find.byType(GlassContainer), findsOneWidget,
      reason: '测试环境没有走玻璃分支：这条用例量不到合成色');
  final band = tester.getRect(find.byType(AppChromeGlassBar));
  final shot = await _shoot(tester);
  return [for (final point in _bandPoints(band)) shot.at(point)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppColors.setDark(false);
  });
  tearDown(() {
    AppColors.setDark(false);
  });

  testWidgets('固定底衬：背后从「卡片白」换到「页面底色」，条带只差 1/255',
      (tester) async {
    _phone(tester);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());

    final onCard = await _bandOver(tester, const Color(0xFFFFFFFF));
    final onPage = await _bandOver(tester, AppColors.bgPage);

    final delta = maxBandDelta(onCard, onPage);
    expect(delta, lessThanOrEqualTo(kPinnedBandColorDeltaLimit),
        reason: '条带跟着背后内容漂了 $delta/255（页面底色 ↔ 卡片白）：'
            '这层固定底衬没起作用，真机上就是「下拉刷新时吸顶日期条变色」');
    expect(tester.takeException(), isNull);
  });

  testWidgets('极端背景（纯黑照片）：加底衬后 10/255，不加底衬 96/255',
      (tester) async {
    _phone(tester);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());

    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);

    // 加底衬（吸顶条现在就是这样）。
    final onWhite = await _bandOver(tester, white);
    final onBlack = await _bandOver(tester, black);
    final withBackplate = maxBandDelta(onWhite, onBlack);
    expect(withBackplate, lessThanOrEqualTo(12),
        reason: '加了 0.9 底衬仍有 $withBackplate/255 的漂移（上一轮实测 96/255）');

    // 对照：同一块玻璃、不画底衬——这就是修复前真机上看到的那次变色。
    final bareWhite = await _bandOver(tester, white, backplateAlpha: 0);
    final bareBlack = await _bandOver(tester, black, backplateAlpha: 0);
    final withoutBackplate = maxBandDelta(bareWhite, bareBlack);
    expect(withoutBackplate, greaterThanOrEqualTo(30),
        reason: '对照组居然不漂（$withoutBackplate/255）：这条用例测不出东西'
            '（玻璃没画上去，或者底衬被谁加回来了）');
    // 底衬把漂移压了一个数量级。
    expect(withBackplate, lessThan(withoutBackplate / 4));
    expect(tester.takeException(), isNull);
  });

  test('底衬与圆角只有一份来源', () {
    // 三个调用点用的是同一组数（AppChromeGlassBar.pinned 写死，见
    // test/pinned_chrome_bar_test.dart：三条带子逐项量到同一个底衬/圆角，
    // 还包括「底衬铺满外框、贴边不留缝」）。
    expect(kAppChromePinnedBackplateAlpha, 0.9);
    expect(kAppChromePinnedRadius, 0);
  });
}
