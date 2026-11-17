import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_glass_tone.dart';
import 'package:album_app/widgets/app_tab_bar_contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 方案 C：折射保持 45%，未选中文字/图标的墨色**按背景合成亮度自动换**。
//
// 守四件事：
//   1. 两套墨色 + 阈值都是常量，且阈值是它们的交叉点；
//   2. 四种极端背景 × 明暗：自动选出来的墨色都 ≥ 4.5:1；
//   3. 采样不可用时按主题回退，照样 ≥ 4.5:1；
//   4. 采样器真的从 spec 取代表色（纯色 / 双色渐变 / 默认渐变 / 图片丢了）。
//
// 「固定一套中性灰」那一档的静态度量（2.62 / 2.19）留在 footer_contrast_test.dart：
// 那是**材料**层面的记录（scrim 0.55 的代价），也是甲/乙 两个方案不可行的证据。

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

/// 注意：buildAppTheme(dark:) 自己会调 AppColors.setDark，别在外面手动设——
/// 否则 pumpWidget 一构建主题就被重置成浅色（这坑踩过一次）。
Widget _tabBar({bool dark = false}) => AppGlassScope(
      quality: GlassQuality.premium,
      child: MaterialApp(
        theme: buildAppTheme(dark: dark),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: AppBottomTabBar(
            selectedIndex: 0,
            onSelected: (_) {},
            items: _tabs,
          ),
        ),
      ),
    );

/// 某个亮度上、某套墨色的对比度（只用亮度算，不造颜色）。
double _ratioAtLuminance(double lum, Color ink) {
  final l = AppAccent.relativeLuminance(ink);
  final hi = lum > l ? lum : l;
  final lo = lum > l ? l : lum;
  return (hi + 0.05) / (lo + 0.05);
}


void main() {
  tearDown(() {
    AppColors.setDark(false);
    AppBackdropSample.reset();
    PageBackdropController.spec.value = const PageBackdropSpec.defaultGradient();
  });

  group('两套墨色与阈值', () {
    test('阈值是两套墨色的交叉点：两边都 ≥4.5，谁也不吃亏', () {
      // 阈值两侧各取一点：上面用深墨、下面用白。
      expect(appGlassToneInkForLuminance(appGlassToneThreshold + 0.001),
          appGlassToneInkDark);
      expect(appGlassToneInkForLuminance(appGlassToneThreshold - 0.001),
          appGlassToneInkLight);

      final dark = _ratioAtLuminance(appGlassToneThreshold, appGlassToneInkDark);
      final light = _ratioAtLuminance(appGlassToneThreshold, appGlassToneInkLight);
      expect(dark, closeTo(light, 0.05),
          reason: '阈值要落在两条曲线的交点上：深墨 '
              '${dark.toStringAsFixed(2)} vs 白 ${light.toStringAsFixed(2)}');
      expect(dark, greaterThanOrEqualTo(4.5));
      expect(light, greaterThanOrEqualTo(4.5));

      // 不是直觉的 0.5：0.5 会让「浅色模式 + 纯黑照片」（底衬亮度 0.248）
      // 选到白，只剩 3.53:1。
      expect(appGlassToneThreshold, lessThan(0.5));
      expect(
        _ratioAtLuminance(
          appGlassToneBackplateLuminance(const Color(0xFF000000)),
          appGlassToneInkLight,
        ),
        lessThan(4.5),
        reason: '浅色/纯黑照片用白只有 3.53——这就是 0.5 阈值不可用的证据',
      );
    });

    test('任意底衬亮度（0~1 扫一遍）都有 ≥4.5 的那一套', () {
      var worst = 5.0;
      var worstLum = 0.0;
      for (var i = 0; i <= 1000; i++) {
        final lum = i / 1000;
        final ratio = _ratioAtLuminance(lum, appGlassToneInkForLuminance(lum));
        if (ratio < worst) {
          worst = ratio;
          worstLum = lum;
        }
      }
      expect(worst, greaterThanOrEqualTo(4.5),
          reason: '最坏出现在底衬亮度 ${worstLum.toStringAsFixed(3)}：'
              '${worst.toStringAsFixed(2)}:1');
    });

    test('没有采样时按主题回退：页面底色底衬上两档都 ≥4.5', () {
      for (final dark in <bool>[false, true]) {
        AppColors.setDark(dark);
        final ink = appGlassToneInkForBackdrop(null);
        expect(ink,
            dark ? appGlassToneFallbackDarkTheme : appGlassToneFallbackLightTheme);
        final backplate = appGlassToneBackplate(AppColors.bgPage);
        final ratio = AppAccent.contrastRatio(backplate, ink);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '${dark ? '深色' : '浅色'}回退墨色对页面底色底衬：'
                '${ratio.toStringAsFixed(2)}:1');
      }
    });
  });

  group('四种极端背景 × 明暗：自动选出来的墨色 ≥ 4.5', () {
    for (final dark in <bool>[false, true]) {
      final mode = dark ? '深色' : '浅色';
      for (final backdrop in appTabBarExtremeBackdrops) {
        test('$mode：${backdrop.label}背景', () {
          AppColors.setDark(dark);
          final backplate = appGlassToneBackplate(backdrop.color);
          final ink = appGlassToneInkForBackdrop(backdrop.color);
          final ratio = AppAccent.contrastRatio(backplate, ink);

          expect(ink, anyOf(appGlassToneInkDark, appGlassToneInkLight));
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: '$mode ${backdrop.label}：底衬亮度 '
                  '${AppAccent.relativeLuminance(backplate).toStringAsFixed(3)}、'
                  '选中 ${ink == appGlassToneInkDark ? '深墨' : '白'}，'
                  '对比度 ${ratio.toStringAsFixed(2)}:1');

          // 换确实是按亮度换的：浅色模式四张背景的底衬都在阈值之上（scrim 是
          // 页面底色，几乎不压暗），全部走深墨；深色模式的纯白照片仍在阈值
          // 之上（0.202）也走深墨，其余三张更暗的走白。
          if (!dark) {
            expect(ink, appGlassToneInkDark, reason: '浅色：底衬都被 scrim 抬到阈值之上');
          } else if (backdrop.label == '纯白') {
            expect(ink, appGlassToneInkDark, reason: '深色/纯白照片的底衬 0.202 在阈值之上');
          } else {
            expect(ink, appGlassToneInkLight, reason: '深色：其余背景底衬都在阈值之下');
          }
        });
      }
    }
  });

  group('渲染出来的就是那一套', () {
    testWidgets('浅色模式：两张极端背景都落在深墨（底衬被 scrim 抬过阈值）', (tester) async {
      AppColors.setDark(false);
      AppBackdropSample.report(const Color(0xFFFFFFFF));
      await tester.pumpWidget(_tabBar());
      await tester.pump();
      expect(tester.widget<Text>(find.text('相册')).style!.color,
          appGlassToneInkDark);

      AppBackdropSample.report(const Color(0xFF000000));
      await tester.pump();
      expect(tester.widget<Text>(find.text('相册')).style!.color,
          appGlassToneInkDark,
          reason: '浅色/纯黑照片的底衬 #88888A 亮度 0.248，仍在阈值之上');

      // 选中态不跟墨色走：始终主题色。
      expect(tester.widget<Text>(find.text('朋友圈')).style!.color, AppColors.primary);
      expect(tester.widget<Icon>(find.byIcon(Icons.people)).color, AppColors.primary);
      // 图标与文字同一套墨色（对比保护描边也是同色）。
      expect(tester.widget<Icon>(find.byIcon(Icons.photo_library_outlined)).color,
          appGlassToneInkDark);
    });

    testWidgets('深色模式：纯白照片 → 深墨，纯黑照片 → 白，清掉采样 → 主题回退',
        (tester) async {
      AppBackdropSample.report(const Color(0xFFFFFFFF));
      await tester.pumpWidget(_tabBar(dark: true));
      await tester.pump();
      expect(tester.widget<Text>(find.text('相册')).style!.color,
          appGlassToneInkDark,
          reason: '深色/纯白照片的底衬 #7A7C80：纯黑 5.03:1 比白 4.17:1 好');

      AppBackdropSample.report(const Color(0xFF000000));
      await tester.pump();
      expect(tester.widget<Text>(find.text('相册')).style!.color,
          appGlassToneInkLight);

      AppBackdropSample.report(null);
      await tester.pump();
      expect(tester.widget<Text>(find.text('相册')).style!.color,
          appGlassToneFallbackDarkTheme);
      expect(tester.takeException(), isNull);
    });
  });

  group('采样器：代表色从 spec 来', () {
    testWidgets('默认渐变 ≈ 页面底色；纯色就是那个色；双色渐变取中点',
        (tester) async {
      AppBackdropSample.reset();
      await tester.pumpWidget(
        const MaterialApp(home: AppGlassBackdrop(child: SizedBox.expand())),
      );
      await tester.pump();
      expect(AppBackdropSample.color.value, AppColors.bgPage,
          reason: '默认渐变里主题色只有 6%~10% 的透明度，代表色就是页面底色');

      PageBackdropController.spec.value =
          const PageBackdropSpec.solid(Color(0xFF203040));
      await tester.pump();
      expect(AppBackdropSample.color.value, const Color(0xFF203040));

      PageBackdropController.spec.value = const PageBackdropSpec.gradient(
        start: Color(0xFF000000),
        end: Color(0xFFFFFFFF),
      );
      await tester.pump();
      final mid = AppBackdropSample.color.value!;
      expect(mid.r, closeTo(0.5, 0.02), reason: '两个色标的中点');
      expect(tester.takeException(), isNull);
    });

    testWidgets('图片丢了：按默认渐变回退，不抛异常', (tester) async {
      AppBackdropSample.reset();
      await tester.pumpWidget(
        const MaterialApp(home: AppGlassBackdrop(child: SizedBox.expand())),
      );
      await tester.pump();
      PageBackdropController.spec.value =
          const PageBackdropSpec.image('/no/such/backdrop.jpg');
      await tester.pump();
      expect(AppBackdropSample.color.value, AppColors.bgPage);
      expect(tester.takeException(), isNull);
    });
  });
}
