import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_tab_bar_contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidGlassSettings;

// 「复杂背景下未选中文字看不清」的验收：
//   1. 底衬先稳：胶囊 scrim 76%/82% + blur 24，背后内容的权重只剩 24%/18%；
//   2. 文字再校准：未选中色对**极端背景**（纯白/纯黑/高饱和红/高饱和蓝）的
//      合成底衬都必须 ≥ 4.5:1，浅色深色各跑一遍；
//   3. 玻璃档位不影响这组数（premium 与磨砂回退同一份 scrim）；
//   4. minimal / 无档位分支是不透明 bgSurface，本来就过线，断言保持不变。
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

  group('极端背景：未选中文字对合成底衬 ≥ 4.5', () {
    for (final dark in <bool>[false, true]) {
      final mode = dark ? '深色' : '浅色';

      for (final backdrop in appTabBarExtremeBackdrops) {
        test('$mode：${backdrop.label}背景（${_hex(backdrop.color)}）', () {
          AppColors.setDark(dark);

          // 底衬 = scrim 按 alpha-over 压在纯色背景上；先确认它是不透明色，
          // 半透明色单独算对比度没有意义。
          final backplate = appTabBarBackplateOver(backdrop.color);
          expect(backplate.a, 1.0);

          // scrim 必须够厚：背后内容权重 ≤ 30%，否则底衬又开始跟着内容漂。
          expect(appTabBarScrimAlpha(), greaterThanOrEqualTo(0.70));
          expect(appTabBarScrimAlpha(), lessThan(1.0),
              reason: '不要做成不透明白底：玻璃还得透出来');

          final ratio =
              AppAccent.contrastRatio(backplate, appTabBarInactiveColor);
          expect(ratio, greaterThanOrEqualTo(appTabBarMinContrast),
              reason: '$mode ${backdrop.label} 背景：底衬 ${_hex(backplate)}、'
                  '文字 ${_hex(appTabBarInactiveColor)}，对比度只 '
                  '${ratio.toStringAsFixed(2)}');

          // 玻璃 tint 与 scrim 的真实层序（tint 在下、scrim 在上）也要过线：
          // 包的 tint 现在是 adaptive（亮度还给背景），这一条是防回退用的。
          final tinted = AppAccent.compositeOver(
            appTabBarScrimColor(),
            AppAccent.compositeOver(appGlassTintColor, backdrop.color),
          );
          expect(
            AppAccent.contrastRatio(tinted, appTabBarInactiveColor),
            greaterThanOrEqualTo(appTabBarMinContrast),
            reason: '$mode ${backdrop.label}：加上玻璃 tint 后仍要 ≥ 4.5',
          );
        });
      }
    }
  });

  test('四种极端背景的底衬亮度已经收得很拢（不再随照片跳）', () {
    for (final dark in <bool>[false, true]) {
      AppColors.setDark(dark);
      final lums = appTabBarExtremeBackdrops
          .map((b) => AppAccent.relativeLuminance(appTabBarBackplateOver(b.color)))
          .toList();
      final spread = lums.reduce((a, b) => a > b ? a : b) -
          lums.reduce((a, b) => a < b ? a : b);
      expect(spread, lessThanOrEqualTo(0.50),
          reason: 'dark=$dark：白/黑照片的底衬亮度差 ${spread.toStringAsFixed(3)}');
      // 最亮与最暗的底衬之间也不该拉开一档以上的对比度。
      final worst = appTabBarExtremeBackdrops
          .map((b) => appTabBarBackplateOver(b.color))
          .toList();
      expect(AppAccent.contrastRatio(worst.first, worst[1]), lessThanOrEqualTo(2.0),
          reason: 'dark=$dark：白底与黑底之间仍要算「同一块颜色」');
      expect(appTabBarWorstContrast(), greaterThanOrEqualTo(appTabBarMinContrast));
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
        expect(scrim.r, closeTo(AppColors.bgPage.r, 1e-9),
            reason: 'scrim 用的是页面底色，不是另一种灰');
        expect(_surfaceSettings(tester).blur, appTabBarBlur,
            reason: 'dark=$dark quality=$quality');
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
          reason: 'minimal 档的底子是不透明 bgSurface（dark=$dark）',
        );
        // 玻璃档那边最坏的一条（四种极端背景）同样要过线。
        expect(
          appTabBarWorstContrast(),
          greaterThanOrEqualTo(appTabBarMinContrast),
          reason: '玻璃档的极端背景最坏对比度（dark=$dark）：'
              '${appTabBarWorstContrast().toStringAsFixed(2)}',
        );
      }
      AppColors.setDark(false);
    }
  });
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
