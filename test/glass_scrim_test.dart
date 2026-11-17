import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_tab_bar_contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 底部胶囊的「读得清」两条：
//   1. 玻璃内部叠一层**重** scrim（页面底色 76%/82%，见 appTabBarScrimAlpha），
//      底衬先稳下来，未选中的灰字才有一块不随滚动内容跳的底；
//   2. 未选中文字/图标带一圈同色 1px 描边（10%），内容颜色跳到极端时边缘不糊。
// 这里把「读得清」变成可断言的数：未选中色与 scrim 合成后的底衬对比度 ≥ 4.5，
// 浅色深色都要成立。四种极端背景（白/黑/红/蓝）逐条见 footer_contrast_test.dart。

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

Widget _tabBar(
  GlassQuality? quality, {
  int selectedIndex = 0,
  ValueChanged<int>? onSelected,
}) {
  return _barHost(
    AppBottomTabBar(
      selectedIndex: selectedIndex,
      onSelected: onSelected ?? (_) {},
      items: _tabs,
    ),
    quality: quality,
  );
}

/// 剥掉 Positioned / IgnorePointer 包装，拿出这一层的 DecoratedBox key。
Key? _layerKey(Widget layer) {
  if (layer is Positioned) return _layerKey(layer.child);
  if (layer is IgnorePointer) return _layerKey(layer.child!);
  if (layer is DecoratedBox) return layer.key;
  return null;
}

void main() {
  tearDown(() => AppColors.setDark(false));

  for (final dark in <bool>[false, true]) {
    final mode = dark ? '深色' : '浅色';

    testWidgets('$mode：未选中文字与胶囊 scrim 合成后的底衬对比度 ≥ 4.5', (tester) async {
      AppColors.setDark(dark);

      // 胶囊自己那层 scrim：够厚（背后内容权重 ≤ 30%）但仍不是一块不透明白。
      expect(appTabBarScrimAlpha(), greaterThanOrEqualTo(0.70));
      expect(appTabBarScrimAlpha(), lessThan(1.0),
          reason: '不要做成不透明白底：玻璃还得透出来');
      expect(appTabBarScrimColor().a, closeTo(appTabBarScrimAlpha(), 1e-9));
      expect(appTabBarScrimColor().r, closeTo(AppColors.bgPage.r, 1e-9),
          reason: 'scrim 用的是页面底色，不是另一种灰');

      // 别的浮层（相册详情条 / 多选底栏）仍用 app_glass 那一档，没被连带改掉。
      expect(appGlassScrimAlpha(), inInclusiveRange(0.35, 0.5));

      // 底衬 = scrim 叠在背景上；半透明色先合成成不透明色。
      final backplate = appTabBarBackplateOver(AppColors.bgPage);
      expect(backplate.a, 1.0, reason: '算对比度前必须是不透明色');

      final ratio = AppAccent.contrastRatio(backplate, appTabBarInactiveColor);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: '未选中文字对 scrim 底衬的对比度（$mode）：${ratio.toStringAsFixed(2)}');

      // 四种极端背景里最坏的一条也要过线（逐条断言在 footer_contrast_test.dart）。
      expect(appTabBarWorstContrast(), greaterThanOrEqualTo(4.5),
          reason: '极端背景下最坏的对比度（$mode）：'
              '${appTabBarWorstContrast().toStringAsFixed(2)}');

      // 退化档是不透明 bgSurface，同一个文字色也得过线。
      expect(AppAccent.contrastRatio(AppColors.bgSurface, appTabBarInactiveColor),
          greaterThanOrEqualTo(4.5),
          reason: 'minimal 档的底子是不透明 bgSurface（$mode）');

      // 对照：不加对比保护（裸 textSecondary）一定更低——压深那一档不是白加的。
      expect(
        ratio,
        greaterThan(
          AppAccent.contrastRatio(backplate, AppColors.textSecondary),
        ),
        reason: '对比保护要比中性灰更清楚（$mode）',
      );
    });
  }

  testWidgets('胶囊的 scrim 铺满整个外框、垫在内容下面、不挡点击', (tester) async {
    AppColors.setDark(false);
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tapped = <int>[];
    await tester.pumpWidget(
      _tabBar(GlassQuality.standard, onSelected: tapped.add),
    );

    final pill = tester.getRect(find.byType(AppGlassSurface).first);
    final scrim = find.byKey(AppGlassSurface.scrimKey);
    expect(scrim, findsOneWidget);
    expect(tester.getRect(scrim), pill,
        reason: 'scrim 和外框同尺寸：留白处也要有底衬');

    final decoration =
        tester.widget<DecoratedBox>(scrim).decoration as BoxDecoration;
    final color = decoration.color!;
    expect(color.a, closeTo(appTabBarScrimAlpha(), 1e-9));
    expect(decoration.borderRadius,
        BorderRadius.circular(AppBottomTabBar.radius));

    // 层序：scrim → 内容 → 高光。scrim 压在内容下面，文字才立得起来。
    final stack = tester.widget<Stack>(
      find
          .ancestor(of: scrim, matching: find.byType(Stack))
          .first,
    );
    expect(stack.children, hasLength(3));
    expect(_layerKey(stack.children[0]), AppGlassSurface.scrimKey);
    expect(_layerKey(stack.children[2]), AppGlassSurface.highlightKey);

    // 不挡点击：scrim 层是 IgnorePointer。
    expect(
      tester
          .widget<IgnorePointer>(
            find.ancestor(of: scrim, matching: find.byType(IgnorePointer)).first,
          )
          .ignoring,
      isTrue,
    );
    await tester.tap(find.text('相册'));
    expect(tapped, [1]);
  });

  testWidgets('minimal 档不叠 scrim：底子本来就不透明', (tester) async {
    await tester.pumpWidget(_tabBar(GlassQuality.minimal));

    expect(find.byKey(AppGlassSurface.scrimKey), findsNothing);
    // 退化分支仍然是不透明胶囊：底子自己就够，不需要再压一层。
    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      tester.getSize(find.byKey(AppBottomTabBar.tabKey(0))).height,
      AppBottomTabBar.barHeight,
    );
  });

  testWidgets('未选中项带同色 ≤12% 描边，没有发光、没有背景块', (tester) async {
    await tester.pumpWidget(_tabBar(GlassQuality.standard));

    final idleText = tester.widget<Text>(find.text('相册'));
    final color = idleText.style!.color!;
    expect(color, appTabBarInactiveColor);

    final shadows = idleText.style!.shadows!;
    expect(shadows, hasLength(1));
    final halo = shadows.single;
    expect(halo.color.a, greaterThan(0));
    expect(halo.color.a, lessThanOrEqualTo(0.12),
        reason: '对比保护是极轻的描边，不是发光');
    expect(halo.color.a, closeTo(appTabBarHaloAlpha, 1e-9));
    expect(halo.color.r, closeTo(color.r, 1e-9), reason: '描边是同色');
    expect(halo.color.g, closeTo(color.g, 1e-9));
    expect(halo.color.b, closeTo(color.b, 1e-9));
    expect(halo.offset, Offset.zero);
    expect(halo.blurRadius, lessThanOrEqualTo(1.5));

    final idleIcon =
        tester.widget<Icon>(find.byIcon(Icons.photo_library_outlined));
    expect(idleIcon.shadows, isNotNull);
    expect(idleIcon.shadows!.single.color.a, closeTo(appTabBarHaloAlpha, 1e-9));
    expect(idleIcon.shadows!.single.color.a, lessThanOrEqualTo(0.12));

    // 「描边」不是「加一块底」：胶囊里没有 Material 底块，也没有水波纹。
    expect(
      find.descendant(
        of: find.byType(AppBottomTabBar),
        matching: find.byType(Material),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(AppBottomTabBar),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });
}
