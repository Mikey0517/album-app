import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_glass_tone.dart';
import 'package:album_app/widgets/app_tab_bar_contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidGlassSettings;

// 「折射可见度 45%」的代价实测。
//
// **已被方案 C 取代的部分**：用户选了「保留 45% 折射 + 自动切换文字明暗」，
// 未选中文字/图标不再用固定中性灰 [appTabBarInactiveColor]，而是按背景合成
// 亮度在两套墨色里挑（见 app_glass_tone.dart 与 test/glass_tone_test.dart）。
// 本文件保留三样东西，都有用：
//   1. **材料**层面的静态度量：scrim 0.55 时底衬本身的对比度（2.62 / 2.19），
//      它是「文字色怎么选」这件事的前提，也是下面两条补偿方案的分母；
//   2. 甲（同色 halo）/ 乙（压深固定色）为什么不行——数字摆在这里，别再绕回去；
//   3. 一条桥接断言：同一组极端背景下，C 的自动墨色 ≥ 4.5（材料不动，只换文字色）。
//
// 上一轮为了让未选中文字在复杂背景下读得清，把胶囊 scrim 提到 76%/82%
// （折射可见度 24%/18%，真机上折射几乎看不见）。这一轮按需求把 scrim 让到
// 0.55（可见度 45%），文字就重新坐在「会漂的底衬」上。这份测试负责把代价
// 变成可核对的数，而不是删断言或假装它过线：
//   1. scrim 只有一个来源（[appGlassChromeScrimAlpha] = 0.55 = 可见度 45%）；
//   2. 四种极端背景（纯白/纯黑/高饱和红/高饱和蓝）× 明暗：**实测值**逐条钉住。
//      它们**低于** WCAG AA 的 4.5:1（浅色最坏 2.62、深色最坏 2.19），
//      这是这一轮的代价，不是漏改；
//   3. 底衬亮度重新跟着照片跳（上一轮 ≤ 0.17，现在 0.72 / 0.20）：同代价；
//   4. 两个补偿方案的效果预估也在本文件里算（甲：同色 halo；乙：压深未选中
//      色），全部用真实函数算，等产品选定后再改实现。
//
// 合成方式按 alpha-over：result = scrim * a + backdrop * (1 - a)，见
// app_tab_bar_contrast.dart 的 appTabBarBackplateOver。

const List<AppBottomTabItem> _tabs = [
  AppBottomTabItem(
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    label: '朋友圈',
  ),
  AppBottomTabItem(
    icon: Icons.photo_library_outlined,
    selectedIcon: Icons.photo_library,
    label: '相册',
  ),
  AppBottomTabItem(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: '我的',
  ),
];

/// 45% 折射可见度（scrim 0.55）下**实测**的未选中文字对比度（固定中性灰，
/// 即方案 C 之前的取法）：这是材料本身的代价，C 只换了文字色，没动它。
///
/// 索引 0 = 浅色、1 = 深色；键与 [appTabBarExtremeBackdrops] 的 label 对齐。
/// 每个数都低于 [appTabBarMinContrast]（4.5）。钉住它们有三重作用：
/// - 报告里的数字和测试里的是同一份；
/// - 谁偷偷把 scrim 抬回 0.7x「让测试过线」，这里会红；
/// - 补偿方案（甲/乙）落地后，只需要改这张表。
const Map<String, List<double>> _measuredContrast = <String, List<double>>{
  '纯白': <double>[8.93, 2.19],
  '纯黑': <double>[2.62, 10.45],
  '高饱和红': <double>[3.96, 5.87],
  '高饱和蓝': <double>[3.08, 8.11],
};

/// 同一组背景，但按真实层序（玻璃 tint 在下、scrim 在上）再叠一次 tint。
///
/// tint 是 10%/7% 的冷白（[appGlassChromeTintColor]），它把底衬往白推一点：
/// 最暗的底衬（浅色/纯黑照片）反而从 2.62 抬到 3.16，而最亮的（深色/纯黑照片）
/// 从 10.45 降到 9.60——**方向取决于底衬本身**，所以这两层必须分开实测，
/// 不能只算「scrim 叠背景」那一条。
const Map<String, List<double>> _measuredTintedContrast = <String, List<double>>{
  '纯白': <double>[8.75, 2.19],
  '纯黑': <double>[3.16, 9.60],
  '高饱和红': <double>[4.34, 5.65],
  '高饱和蓝': <double>[3.57, 7.63],
};

/// 实测底衬亮度：白/黑照片的亮度差，以及两块底衬之间的对比度（dark 索引）。
const List<double> _measuredSpread = <double>[0.718, 0.199];
const List<double> _measuredWhiteBlackRatio = <double>[3.41, 4.77];

/// 补偿方案甲：同色 halo 的那一圈（`text@alpha` 叠在底衬上）对底衬的对比度。
///
/// **甲 为什么改变不了那个数**：字形填充是不透明色、halo 是同色的，WCAG 比的
/// 是「文字色 vs 底衬」，所以 2.62 / 2.19 一点不动。halo 真正改变的只是紧贴
/// 字形的那一圈及其外侧过渡带，实测（底衬为最坏那张极端背景）：
/// - alpha 0.12 → 环比底衬 1.11:1、文字比环 2.36:1（浅）/ 1.97:1（深）；
/// - alpha 0.16 → 环比底衬 1.15:1、文字比环 2.27:1（浅）/ 1.91:1（深）。
/// 它把「文字 → 底衬」的一步跳变拆成两步，换来等效笔画宽度 +2px（blur 1，
/// 左右各 1px）——观感更「实」，但**不是**对比度补偿。
double _haloRingRatio(Color backplate, Color text, double alpha) =>
    AppAccent.contrastRatio(
      AppAccent.compositeOver(text.withValues(alpha: alpha), backplate),
      backplate,
    );

/// 补偿方案乙：保持 45% 可见度，把未选中色往 [AppColors.textPrimary] 再压一档
/// （旋钮是 [appTabBarInactiveContrastStepLight] / [...Dark]）。
///
/// 实测（scrim 0.55，四种极端背景取最坏）：
/// - 浅色：0.50（#434853）→ 2.62；0.85 → 4.08；**0.95（#1E212B）→ 4.54**，
///   才刚过 4.5，而 0.95 的观感与 textPrimary 已无区别（未选中态消失）；
/// - 深色：0.18（#B5BCCA）→ 2.19；一路压到 1.00（= textPrimary）→ 3.79，
///   **仍不到 4.5**。深色模式在 45% 可见度下没有任何文字色能过 AA：纯白照片
///   把底衬抬到 #7A7C80，纯白字的理论上限只有 4.19:1。
double _worstContrastAtStep(double step) {
  final text = Color.lerp(AppColors.textSecondary, AppColors.textPrimary, step)!;
  return appTabBarExtremeBackdrops
      .map((backdrop) => AppAccent.contrastRatio(
            appTabBarBackplateOver(backdrop.color),
            text,
          ))
      .reduce((a, b) => a < b ? a : b);
}

/// 「回到 AA 4.5」所需的 scrim 不透明度（保持现在的未选中色）。
///
/// 实测 0.730（浅）/ 0.755（深），即折射可见度 27% / 24.5%——正好回到上一轮
/// 那一档。这就是「4.5 与 45% 不可兼得」的定量说法。
double _minScrimForAa() {
  var alpha = 0.0;
  while (alpha <= 1.0) {
    final worst = appTabBarExtremeBackdrops
        .map((backdrop) => AppAccent.contrastRatio(
              AppAccent.compositeOver(
                AppColors.bgPage.withValues(alpha: alpha),
                backdrop.color,
              ),
              appTabBarInactiveColor,
            ))
        .reduce((a, b) => a < b ? a : b);
    if (worst >= appTabBarMinContrast) return alpha;
    alpha += 0.005;
  }
  return 1.0;
}

Widget _barHost(Widget bar, {GlassQuality? quality}) {
  final app = MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: bar,
    ),
  );
  if (quality == null) return app;
  return AppGlassScope(quality: quality, child: app);
}

Widget _tabBar(GlassQuality? quality) => _barHost(
      AppBottomTabBar(
        selectedIndex: 0,
        onSelected: (_) {},
        items: _tabs,
      ),
      quality: quality,
    );

BoxDecoration _scrimDecoration(WidgetTester tester) =>
    tester.widget<DecoratedBox>(find.byKey(AppGlassSurface.scrimKey))
        .decoration as BoxDecoration;

LiquidGlassSettings _surfaceSettings(WidgetTester tester) =>
    tester.widget<GlassContainer>(find.byType(GlassContainer)).settings!;

void main() {
  tearDown(() => AppColors.setDark(false));

  group('极端背景：未选中文字对合成底衬的实测值（45% 折射可见度）', () {
    for (final dark in <bool>[false, true]) {
      final mode = dark ? '深色' : '浅色';

      for (final backdrop in appTabBarExtremeBackdrops) {
        test('$mode：${backdrop.label}背景（${_hex(backdrop.color)}）', () {
          AppColors.setDark(dark);

          // 底衬 = scrim 按 alpha-over 压在纯色背景上；先确认它是不透明色，
          // 半透明色单独算对比度没有意义。
          final backplate = appTabBarBackplateOver(backdrop.color);
          expect(backplate.a, 1.0);

          // scrim 是「45% 折射可见度」的那一档，且与其余 chrome 同一个来源。
          expect(appTabBarScrimAlpha(), appGlassChromeScrimAlpha());
          expect(appGlassChromeRefractionVisibility(), closeTo(0.45, 1e-9));
          expect(appTabBarScrimAlpha(), lessThan(1.0),
              reason: '不要做成不透明白底：玻璃还得透出来');

          final ratio =
              AppAccent.contrastRatio(backplate, appTabBarInactiveColor);
          final expected = _measuredContrast[backdrop.label]![dark ? 1 : 0];
          expect(ratio, closeTo(expected, 0.02),
              reason: '$mode ${backdrop.label} 背景：底衬 ${_hex(backplate)}、'
                  '文字 ${_hex(appTabBarInactiveColor)}，实测 '
                  '${ratio.toStringAsFixed(2)}:1（AA 目标 '
                  '${appTabBarMinContrast.toStringAsFixed(1)}）');
          // 每种模式各有两张背景过不了线：浅色的纯黑/高饱和蓝（2.62 / 3.08），
          // 深色的纯白（2.19）。这是 45% 可见度的直接代价，不是漏改——要过线
          // 请走补偿方案（本文件末尾那组测试），不要偷偷加厚 scrim。
          final failing = dark
              ? backdrop.label == '纯白'
              : backdrop.label == '纯黑' || backdrop.label == '高饱和蓝';
          if (failing) {
            expect(ratio, lessThan(appTabBarMinContrast),
                reason: '$mode ${backdrop.label}：这一格**本来就不该**过 4.5；'
                    '过了说明 scrim 又被抬回去了');
          }

          // 玻璃 tint 与 scrim 的真实层序（tint 在下、scrim 在上）也实测一遍：
          // tint 是 10%/7% 的冷白，浅色模式里会把最暗的底衬抬亮一点。
          final tinted = AppAccent.compositeOver(
            appTabBarScrimColor(),
            AppAccent.compositeOver(appGlassTintColor, backdrop.color),
          );
          final tintedRatio =
              AppAccent.contrastRatio(tinted, appTabBarInactiveColor);
          expect(
              tintedRatio,
              closeTo(_measuredTintedContrast[backdrop.label]![dark ? 1 : 0],
                  0.02),
              reason: '$mode ${backdrop.label}：真实层序（tint 在下、scrim 在上）'
                  '的实测值 ${tintedRatio.toStringAsFixed(2)}:1——tint 的方向'
                  '取决于底衬，不能只看 scrim 那一条');
        });
      }
    }
  });

  test('四种极端背景的底衬重新跟着照片跳（45% 可见度的代价）', () {
    for (final dark in <bool>[false, true]) {
      AppColors.setDark(dark);
      final index = dark ? 1 : 0;
      final lums = appTabBarExtremeBackdrops
          .map((b) => AppAccent.relativeLuminance(appTabBarBackplateOver(b.color)))
          .toList();
      final spread = lums.reduce((a, b) => a > b ? a : b) -
          lums.reduce((a, b) => a < b ? a : b);
      // 上一轮 scrim 0.76/0.82 时这条是「亮度差 ≤ 0.50、白/黑底衬 ≤ 2.0:1」，
      // 也就是底衬基本恒定。scrim 让到 0.55 之后必然不成立：白墙照片与夜景
      // 照片下面，胶囊是两块明显不同的底色——这正是 45% 折射可见度的对价。
      expect(spread, closeTo(_measuredSpread[index], 0.01),
          reason: 'dark=$dark：白/黑照片的底衬亮度差 '
              '${spread.toStringAsFixed(3)}（上一轮 ≤ 0.17）');

      final white = appTabBarBackplateOver(appTabBarExtremeBackdrops[0].color);
      final black = appTabBarBackplateOver(appTabBarExtremeBackdrops[1].color);
      final whiteBlackRatio = AppAccent.contrastRatio(white, black);
      expect(whiteBlackRatio,
          closeTo(_measuredWhiteBlackRatio[index], 0.02),
          reason: 'dark=$dark：白底与黑底之间已经拉不到「同一块颜色」了');
      expect(whiteBlackRatio, greaterThan(2.0),
          reason: '上一轮 ≤ 2.0 的「底衬恒定」在这一档已经不成立');

      expect(appTabBarWorstContrast(), closeTo(dark ? 2.19 : 2.62, 0.02));
    }
  });

  testWidgets('两档玻璃的胶囊用同一份 scrim 与模糊（切档底色不漂）',
      (tester) async {
    for (final dark in <bool>[false, true]) {
      AppColors.setDark(dark);
      for (final quality in <GlassQuality>[
        GlassQuality.premium,
        GlassQuality.standard,
      ]) {
        await tester.pumpWidget(_tabBar(quality));
        await tester.pump(const Duration(milliseconds: 50));

        // scrim 与档位无关：premium 的折射再深，文字底衬也是同一块颜色。
        final scrim = _scrimDecoration(tester).color!;
        expect(scrim.a, closeTo(appTabBarScrimAlpha(), 1e-9),
            reason: 'dark=$dark quality=$quality');
        expect(scrim.a, closeTo(0.55, 1e-9),
            reason: '45% 折射可见度：scrim 0.55，四处 chrome 同一个数');
        expect(scrim.r, closeTo(AppColors.bgPage.r, 1e-9),
            reason: 'scrim 用的是页面底色，不是另一种灰');
        expect(_surfaceSettings(tester).blur, appTabBarBlur,
            reason: 'dark=$dark quality=$quality');
        expect(_surfaceSettings(tester).blur, appGlassChromeBlur,
            reason: '模糊与 chrome 同一档（2）：剩下的 45% 是留给折射的');
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('minimal / 无档位：不透明 bgSurface，未选中文字本来就过线',
      (tester) async {
    for (final quality in <GlassQuality?>[GlassQuality.minimal, null]) {
      await tester.pumpWidget(_tabBar(quality));
      await tester.pump();

      // 不透明分支没有玻璃、也没有 scrim：底子自己就是不透明 bgSurface。
      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byKey(AppGlassSurface.scrimKey), findsNothing);
      final decoration = tester
          .widgetList<DecoratedBox>(find.descendant(
            of: find.byType(AppBottomTabBar),
            matching: find.byType(DecoratedBox),
          ))
          .first
          .decoration as BoxDecoration;
      expect(decoration.color, AppColors.bgSurface);
      expect(
        tester.getSize(find.byKey(AppBottomTabBar.tabKey(0))).height,
        AppBottomTabBar.barHeight,
        reason: '退化不许跳版',
      );

      for (final dark in <bool>[false, true]) {
        AppColors.setDark(dark);
        expect(
          AppAccent.contrastRatio(AppColors.bgSurface, appTabBarInactiveColor),
          greaterThanOrEqualTo(appTabBarMinContrast),
          reason: 'minimal 档的底子是不透明 bgSurface（dark=$dark）：'
              '这一条不受 scrim 影响，仍然过线',
        );
        // 玻璃档那边最坏的一条（四种极端背景）照样钉住实测值。
        expect(
          appTabBarWorstContrast(),
          closeTo(dark ? 2.19 : 2.62, 0.02),
          reason: '玻璃档的极端背景最坏对比度（dark=$dark）：'
              '${appTabBarWorstContrast().toStringAsFixed(2)}',
        );
      }
      AppColors.setDark(false);
    }
  });

  group('补偿方案的效果预估（甲 halo / 乙 压深未选中色）', () {
    test('甲：同色 halo 不改变填充对比度，只把边缘拆成两步', () {
      for (final dark in <bool>[false, true]) {
        AppColors.setDark(dark);
        // 各模式最坏的那张极端背景：浅色是纯黑照片、深色是纯白照片。
        final worstBackdrop = dark
            ? appTabBarExtremeBackdrops[0].color // 纯白
            : appTabBarExtremeBackdrops[1].color; // 纯黑
        final backplate = appTabBarBackplateOver(worstBackdrop);
        final fill = AppAccent.contrastRatio(backplate, appTabBarInactiveColor);
        expect(fill, closeTo(dark ? 2.19 : 2.62, 0.02),
            reason: '未选中文字与底衬的填充对比度（dark=$dark）');

        // 甲 的「收益」只在这一圈：环比底衬 1.11（0.12）/ 1.15（0.16）。
        expect(_haloRingRatio(backplate, appTabBarInactiveColor, 0.12),
            closeTo(1.11, 0.02),
            reason: 'halo 0.12 的环只比底衬亮/暗 11%：看得见边缘，撑不起对比度');
        expect(_haloRingRatio(backplate, appTabBarInactiveColor, 0.16),
            closeTo(1.15, 0.02),
            reason: 'halo 0.16 的环也只有 15%');
        // 而文字与这一圈之间反而更近：同色 halo 让「一步跳变」变「两步」。
        expect(
          AppAccent.contrastRatio(
            AppAccent.compositeOver(
              appTabBarInactiveColor.withValues(alpha: 0.12),
              backplate,
            ),
            appTabBarInactiveColor,
          ),
          lessThan(fill),
          reason: '甲的数是「不变」，不是「变好」（dark=$dark）',
        );
        // 结论：甲 一笔也补不上 4.5 的缺口。
        expect(fill, lessThan(appTabBarMinContrast));
      }
      AppColors.setDark(false);
    });

    test('乙：浅色压到 ≈textPrimary 才刚过 4.5；深色无论怎么压都过不了', () {
      // 浅色：0.50 → 2.62；0.85 → 4.08；0.95 → 4.54；1.00 → 4.77。
      AppColors.setDark(false);
      expect(_worstContrastAtStep(0.50), closeTo(2.62, 0.02),
          reason: '现在这一档（未选中的观感就是它）');
      expect(_worstContrastAtStep(0.85), closeTo(4.08, 0.02));
      expect(_worstContrastAtStep(0.95), closeTo(4.54, 0.02));
      expect(_worstContrastAtStep(0.95),
          greaterThanOrEqualTo(appTabBarMinContrast),
          reason: '浅色要压到 0.95（≈ textPrimary）才刚过线——未选中态就没区别了');
      expect(_worstContrastAtStep(1.00), closeTo(4.77, 0.02));

      // 深色：0.18 → 2.19；0.60 → 2.94；1.00 → 3.79。纯白照片把底衬抬到
      // #7A7C80，纯白字的上限也只有 4.19:1——乙 在深色模式不成立。
      AppColors.setDark(true);
      expect(_worstContrastAtStep(0.18), closeTo(2.19, 0.02));
      expect(_worstContrastAtStep(0.60), closeTo(2.94, 0.02));
      expect(_worstContrastAtStep(1.00), closeTo(3.79, 0.02));
      expect(_worstContrastAtStep(1.00), lessThan(appTabBarMinContrast),
          reason: '深色模式在 45% 可见度下没有任何未选中色能过 AA');
      AppColors.setDark(false);
    });

    test('想回到 AA 4.5：scrim 得退回 0.73（浅）/ 0.755（深）——即放弃 45%', () {
      AppColors.setDark(false);
      expect(_minScrimForAa(), closeTo(0.730, 0.006),
          reason: '浅色：scrim ≥ 0.73（可见度 27%）才重新过线');
      AppColors.setDark(true);
      expect(_minScrimForAa(), closeTo(0.755, 0.006),
          reason: '深色：scrim ≥ 0.755（可见度 24.5%）才重新过线');
      AppColors.setDark(false);
    });

    test('桥接：同一组极端背景，方案 C 的自动墨色 ≥ 4.5（材料不动，只换文字色）',
        () {
      // 材料还是上面那套 scrim 0.55（2.62 / 2.19 的代价照旧），换的只是文字的
      // 明暗。这条断言把「材料代价」与「C 的补救」钉在同一组格子上：谁把墨色
      // 阈值改回 0.5、或者把两套色值改浅，这里和 glass_tone_test.dart 会一起红。
      for (final dark in <bool>[false, true]) {
        AppColors.setDark(dark);
        for (final backdrop in appTabBarExtremeBackdrops) {
          final backplate = appGlassToneBackplate(backdrop.color);
          final ink = appGlassToneInkForBackdrop(backdrop.color);
          final ratio = AppAccent.contrastRatio(backplate, ink);
          expect(ratio, greaterThanOrEqualTo(appTabBarMinContrast),
              reason: '${dark ? '深色' : '浅色'} ${backdrop.label}：自动选'
                  '${ink == appGlassToneInkDark ? '深墨' : '白'}，'
                  '对比度 ${ratio.toStringAsFixed(2)}:1');
        }
      }
      AppColors.setDark(false);
    });
  });
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
