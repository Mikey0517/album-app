import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_card.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality;

// 底部胶囊要「透亮 + 折射」：premium 档 + 自建渲染层 + 薄 scrim。
// premium 拿不到时（非 Impeller / 自适应降档 / minimal / 玻璃未初始化）
// 必须整块退回原来的磨砂实现——参数一起换回来，不留半套 premium 参数，
// 也不能白屏或抛异常。这里把两条分支都钉死。

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

Widget _tabBar({GlassQuality? quality}) {
  final app = MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: AppBottomTabBar(
        selectedIndex: 0,
        onSelected: (_) {},
        items: _tabs,
      ),
    ),
  );
  return quality == null ? app : AppGlassScope(quality: quality, child: app);
}

GlassContainer _container(WidgetTester tester) =>
    tester.widget<GlassContainer>(find.byType(GlassContainer));

BoxDecoration _scrimDecoration(WidgetTester tester) =>
    tester.widget<DecoratedBox>(find.byKey(AppGlassSurface.scrimKey))
        .decoration as BoxDecoration;

void main() {
  tearDown(() => AppColors.setDark(false));

  group('premium 决策：三输入摊平', () {
    test('注入优先：注入什么就是什么上限', () {
      expect(
        appGlassPremiumDecision(
          injected: GlassQuality.premium,
          ceiling: GlassQuality.minimal,
          platformSupported: false,
        ),
        isTrue,
        reason: '注入 premium = 模拟一台 premium 上限的机器（测试钩子）',
      );
      expect(
        appGlassPremiumDecision(
          injected: GlassQuality.standard,
          ceiling: GlassQuality.premium,
          platformSupported: true,
        ),
        isFalse,
      );
      expect(
        appGlassPremiumDecision(
          injected: GlassQuality.minimal,
          ceiling: GlassQuality.premium,
          platformSupported: true,
        ),
        isFalse,
      );
    });

    test('无注入：自适应上限不是 premium 就没有 premium', () {
      expect(
        appGlassPremiumDecision(
          injected: null,
          ceiling: GlassQuality.standard,
          platformSupported: true,
        ),
        isFalse,
        reason: '自适应降档（过热/掉帧）后自动回到磨砂实现',
      );
      expect(
        appGlassPremiumDecision(
          injected: null,
          ceiling: GlassQuality.minimal,
          platformSupported: true,
        ),
        isFalse,
      );
      expect(
        appGlassPremiumDecision(
          injected: null,
          ceiling: null,
          platformSupported: true,
        ),
        isFalse,
        reason: '没有任何档位来源（initialize 失败）= 玻璃都不可用',
      );
    });

    test('非 Impeller / Web：上限到了 premium 也要退回磨砂', () {
      expect(
        appGlassPremiumDecision(
          injected: null,
          ceiling: GlassQuality.premium,
          platformSupported: false,
        ),
        isFalse,
        reason: 'premium 是 Impeller 全管线，平台不支持就没有折射可看',
      );
      expect(
        appGlassPremiumDecision(
          injected: null,
          ceiling: GlassQuality.premium,
          platformSupported: true,
        ),
        isTrue,
      );
    });
  });

  group('premium 分支：胶囊真的用 premium + 自建层 + 薄 scrim', () {
    testWidgets('档位、自建层、光学参数都是 premium 那一套', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_tabBar(quality: GlassQuality.premium));
      await tester.pump(const Duration(milliseconds: 50));

      final container = _container(tester);
      expect(container.quality, GlassQuality.premium);
      expect(container.useOwnLayer, isTrue,
          reason: 'premium 的 per-widget settings 只在自建层里生效');

      final settings = container.settings!;
      final fallback = appGlassChromeSettings(
        tester.element(find.byType(AppBottomTabBar)),
      );
      expect(settings.thickness, fallback.thickness);
      expect(settings.thickness, greaterThan(20),
          reason: '斜面要深，边缘才有能被看见的 displacement');
      expect(settings.refractiveIndex, greaterThan(1.3),
          reason: '折射率低就看不出弯折');
      expect(settings.chromaticAberration, greaterThanOrEqualTo(0.08),
          reason: 'premium 的色散要在边缘看得出来');
      expect(settings.blur, lessThan(5), reason: '折射优先，模糊压到最低');
      expect(settings.glassColor.a, closeTo(appGlassChromeTintColor.a, 1e-9));
      expect(settings.glassColor.a, lessThan(appGlassTintColor.a),
          reason: '胶囊的 tint 比卡片还淡：底色交给折射采进来的背景');
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrim 变薄（折射不被糊成灰板），对比度仍然 ≥ 4.5', (tester) async {
      await tester.pumpWidget(_tabBar(quality: GlassQuality.premium));
      await tester.pump(const Duration(milliseconds: 50));

      final color = _scrimDecoration(tester).color!;
      expect(color.a, closeTo(appGlassPremiumScrimAlpha(), 1e-9));
      expect(color.a, lessThan(appGlassScrimAlpha()),
          reason: 'premium 的 scrim 必须比磨砂回退那层薄');
      expect(color.a, lessThan(0.35), reason: '再厚就把折射糊掉了');

      for (final dark in <bool>[false, true]) {
        AppColors.setDark(dark);
        final ratio = AppAccent.contrastRatio(
          appGlassPremiumScrimBackplate(),
          appTabBarInactiveColor,
        );
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '未选中灰字对 premium 底衬的对比度（dark=$dark）：'
                '${ratio.toStringAsFixed(2)}');
      }
    });
  });

  group('回退分支：premium 不可用时整块回到磨砂实现', () {
    testWidgets('注入 standard：档位回到 standard，scrim 回到 42%/50%', (tester) async {
      await tester.pumpWidget(_tabBar(quality: GlassQuality.standard));

      final container = _container(tester);
      expect(container.quality, GlassQuality.standard);
      expect(container.useOwnLayer, isTrue,
          reason: '胶囊本来就要自建层（参数只有一个来源），与档位无关');

      final settings = container.settings!;
      expect(settings.thickness, 12, reason: '磨砂那套光学参数');
      expect(settings.blur, 8);
      expect(settings.glassColor.a, closeTo(appGlassTintColor.a, 1e-9));

      final color = _scrimDecoration(tester).color!;
      expect(color.a, closeTo(appGlassScrimAlpha(), 1e-9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('注入 minimal：退化成不透明胶囊，没有玻璃也没有 scrim', (tester) async {
      await tester.pumpWidget(_tabBar(quality: GlassQuality.minimal));

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byKey(AppGlassSurface.scrimKey), findsNothing);
      expect(find.byKey(AppGlassSurface.highlightKey), findsNothing);
      expect(tester.getSize(find.byKey(AppBottomTabBar.tabKey(0))).height,
          AppBottomTabBar.barHeight);
      expect(tester.takeException(), isNull, reason: '降档不许抛异常/白屏');
    });

    testWidgets('玻璃完全不可用（没有任何档位）：同样是不透明胶囊', (tester) async {
      await tester.pumpWidget(_tabBar());

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byKey(AppGlassSurface.scrimKey), findsNothing);
      expect(tester.getSize(find.byKey(AppBottomTabBar.tabKey(0))).height,
          AppBottomTabBar.barHeight);
      expect(tester.takeException(), isNull);
    });
  });

  group('卡片与胶囊同档：一套 premium 参数', () {
    Widget cardHost({GlassQuality? quality}) {
      final app = MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: AppCard(glass: true, child: Text('卡片')),
          ),
        ),
      );
      return quality == null
          ? app
          : AppGlassScope(quality: quality, child: app);
    }

    testWidgets('注入 premium：卡片的档位与光学参数和 footer 完全一致', (tester) async {
      await tester.pumpWidget(cardHost(quality: GlassQuality.premium));
      await tester.pump(const Duration(milliseconds: 50));

      final card = _container(tester);
      expect(card.quality, GlassQuality.premium);
      expect(card.useOwnLayer, isFalse,
          reason: '卡片不自建层（列表里另有 RepaintBoundary 兜着）');

      // footer 那一套：thickness 28 / 折射 1.38 / 色散 0.10 / blur 3。
      final settings = card.settings!;
      expect(settings.thickness, 28);
      expect(settings.refractiveIndex, 1.38);
      expect(settings.chromaticAberration, 0.10);
      expect(settings.blur, 3);
      expect(settings.glassColor.a, closeTo(appGlassChromeTintColor.a, 1e-9),
          reason: '连 tint 都是胶囊那一份（比磨砂更淡）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('上限降到 standard：卡片退回磨砂参数，不白屏也不抛异常', (tester) async {
      await tester.pumpWidget(cardHost(quality: GlassQuality.standard));

      final card = _container(tester);
      expect(card.quality, GlassQuality.standard);
      expect(card.settings!.thickness, 12, reason: '磨砂那套光学参数');
      expect(card.settings!.blur, 8);
      expect(card.settings!.glassColor.a, closeTo(appGlassTintColor.a, 1e-9));
      expect(find.text('卡片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
