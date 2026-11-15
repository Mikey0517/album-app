import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/radius.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/models/post.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_card.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        AnimatedGlassIndicator,
        GlassContainer,
        GlassQuality,
        GlassTabBar,
        LiquidRoundedSuperellipse;

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

/// 底部栏放进真实 Scaffold 的 bottomNavigationBar 位置。
Widget _barHost(
  Widget bar, {
  GlassQuality? quality,
}) {
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
      requestedQuality: quality,
    ),
    quality: quality,
  );
}

BoxDecoration _firstDecorationUnder(WidgetTester tester, Type type) {
  final decorated = tester.widgetList<DecoratedBox>(
    find.descendant(of: find.byType(type), matching: find.byType(DecoratedBox)),
  );
  return decorated.first.decoration as BoxDecoration;
}

void main() {
  group('底部栏：玻璃在底子上', () {
    testWidgets('整条栏是一块玻璃，没有滑块/指示器，三个 tab 等宽可点', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tapped = <int>[];
      await tester.pumpWidget(
        _tabBar(GlassQuality.standard, onSelected: tapped.add),
      );

      // 玻璃铺满整个胶囊：只有一块玻璃表面，且不属于任何一个 tab。
      expect(find.byType(GlassContainer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBottomTabBar),
          matching: find.byType(GlassContainer),
        ),
        findsOneWidget,
        reason: '玻璃包着整条栏，而不是某一项',
      );
      // 没有「选中项胶囊」：包的 tab bar 与它的指示器一个都不在。
      expect(find.byType(GlassTabBar), findsNothing);
      expect(find.byType(AnimatedGlassIndicator), findsNothing);

      // 胶囊本身还是 56 高；整条栏多出来的是离底边距。
      final pill = tester.getSize(find.byType(AppGlassSurface).first);
      expect(pill.height, AppBottomTabBar.barHeight);
      expect(pill.height, 56);
      expect(tester.getSize(find.byType(AppBottomTabBar)).height,
          AppBottomTabBar.barHeight + AppBottomTabBar.bottomGap);

      // 点下去只有颜色变化：没有 InkWell / InkResponse 就没有水波纹。
      expect(
        find.descendant(
          of: find.byType(AppBottomTabBar),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AppBottomTabBar),
          matching: find.byType(InkResponse),
        ),
        findsNothing,
      );

      final widths = [
        for (var index = 0; index < _tabs.length; index++)
          tester.getSize(find.byKey(AppBottomTabBar.tabKey(index))).width,
      ];
      final pillWidth = pill.width;
      expect(widths, [pillWidth / 3, pillWidth / 3, pillWidth / 3]);

      await tester.tap(find.text('相册'));
      await tester.tap(find.text('我的'));
      expect(tapped, [1, 2]);
      // 点完也没有多出涟漪/高亮层。
      expect(find.byType(InkWell), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('胶囊几何：左右 16~20、圆角 = 高度/2、底部离安全区 8~12',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);

      await tester.pumpWidget(_tabBar(GlassQuality.standard));

      final barRect = tester.getRect(find.byType(AppBottomTabBar));
      final pillRect = tester.getRect(find.byType(AppGlassSurface).first);

      // 左右各留边距，不再贴边通栏。
      final leftGap = pillRect.left - barRect.left;
      final rightGap = barRect.right - pillRect.right;
      expect(leftGap, greaterThan(0));
      expect(rightGap, greaterThan(0));
      expect(leftGap, inInclusiveRange(16, 20));
      expect(rightGap, leftGap);
      // 圆角 = 高度/2，四角是 pill。
      expect(pillRect.height, 56);
      expect(AppBottomTabBar.radius, AppBottomTabBar.barHeight / 2);
      final surface =
          tester.widget<AppGlassSurface>(find.byType(AppGlassSurface).first);
      expect(surface.radius, pillRect.height / 2);
      final shape = tester
          .widget<GlassContainer>(find.byType(GlassContainer))
          .shape as LiquidRoundedSuperellipse;
      expect(shape.borderRadius, pillRect.height / 2);
      // 底部：离安全区还有 8~12，安全区自身不算在胶囊里。
      final bottomGap = barRect.bottom - pillRect.bottom - 34;
      expect(bottomGap, inInclusiveRange(8, 12));
      expect(barRect.bottom - pillRect.bottom,
          AppBottomTabBar.bottomGap + 34);
    });

    testWidgets('选中=主题色实心图标，未选中=中性灰线框', (tester) async {
      await tester.pumpWidget(_tabBar(GlassQuality.standard));

      expect(tester.widget<Icon>(find.byIcon(Icons.people)).color,
          AppColors.primary);
      expect(tester.widget<Text>(find.text('朋友圈')).style!.color,
          AppColors.primary);
      expect(
          tester.widget<Icon>(find.byIcon(Icons.photo_library_outlined)).color,
          appTabBarInactiveColor);
      expect(tester.widget<Text>(find.text('相册')).style!.color,
          appTabBarInactiveColor);
      // 未选中是线框，不会同时出现实心变体。
      expect(find.byIcon(Icons.photo_library), findsNothing);

      // 切换选中项后颜色跟着换。
      await tester.pumpWidget(_tabBar(GlassQuality.standard, selectedIndex: 1));
      expect(tester.widget<Icon>(find.byIcon(Icons.photo_library)).color,
          AppColors.primary);
      expect(
          tester.widget<Icon>(find.byIcon(Icons.people_outline)).color,
          appTabBarInactiveColor);
      // 选中态只动颜色与图标变体，不叠任何背景层。
      expect(
        find.descendant(
          of: find.byType(AppBottomTabBar),
          matching: find.byType(Material),
        ),
        findsNothing,
      );
    });

    testWidgets('minimal 档：退化成同圆角的不透明胶囊 + 1px 细边', (tester) async {
      await tester.pumpWidget(_tabBar(GlassQuality.minimal));

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing, reason: 'minimal 不加模糊');
      // 玻璃分支的两层装饰在 minimal 下不出现。
      expect(find.byKey(AppGlassSurface.strokeKey), findsNothing);
      expect(find.byKey(AppGlassSurface.highlightKey), findsNothing);

      final decoration = _firstDecorationUnder(tester, AppBottomTabBar);
      expect(decoration.color, AppColors.bgSurface);
      // 退化也是胶囊：同样的圆角和边距，不退回通栏。
      expect(decoration.borderRadius,
          BorderRadius.circular(AppBottomTabBar.radius));
      final border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.bottom.width, 1);
      expect(border.left.width, 1);
      expect(border.top.color, AppColors.divider);

      // 布局不变：胶囊还是 56 高，三个等宽 tab 都在。
      expect(
        tester.getSize(find.byKey(AppBottomTabBar.tabKey(0))).height,
        56,
      );
      expect(find.byKey(AppBottomTabBar.tabKey(0)), findsOneWidget);
      expect(find.byKey(AppBottomTabBar.tabKey(1)), findsOneWidget);
      expect(find.byKey(AppBottomTabBar.tabKey(2)), findsOneWidget);
      expect(find.byType(GlassTabBar), findsNothing);
    });

    testWidgets('玻璃不可用（没有任何档位）时同样是不透明胶囊', (tester) async {
      await tester.pumpWidget(_barHost(
        AppBottomTabBar(
          selectedIndex: 0,
          onSelected: (_) {},
          items: _tabs,
        ),
      ));

      expect(find.byType(GlassContainer), findsNothing);
      final decoration = _firstDecorationUnder(tester, AppBottomTabBar);
      expect(decoration.color, AppColors.bgSurface);
      expect(decoration.borderRadius,
          BorderRadius.circular(AppBottomTabBar.radius));
      expect(
        tester.getSize(find.byKey(AppBottomTabBar.tabKey(0))).height,
        56,
      );
    });
  });

  group('卡片：玻璃只在卡片本体', () {
    Widget host(Widget child, GlassQuality? quality) {
      final app = MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      );
      return quality == null
          ? app
          : AppGlassScope(quality: quality, child: app);
    }

    testWidgets('minimal 档：卡片与「我的」项都不走玻璃分支', (tester) async {
      await tester.pumpWidget(host(
        const Column(
          children: [
            AppCard(glass: true, child: Text('服务器状态')),
            SizedBox(height: 12),
            AppGlassSurface(child: Text('我的')),
          ],
        ),
        GlassQuality.minimal,
      ));

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      // 描边/高光叠层只在玻璃分支出现。
      expect(find.byKey(AppGlassSurface.strokeKey), findsNothing);
      expect(find.byKey(AppGlassSurface.highlightKey), findsNothing);
      // 两张卡片都画的是不透明表面。
      for (final decoration in tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((e) => e.decoration)
          .whereType<BoxDecoration>()) {
        expect(decoration.color, AppColors.bgSurface);
      }
    });

    testWidgets('玻璃不可用时卡片也是不透明表面', (tester) async {
      await tester.pumpWidget(host(
        const AppCard(glass: true, child: Text('服务器状态')),
        null,
      ));

      expect(find.byType(GlassContainer), findsNothing);
      expect(_firstDecorationUnder(tester, AppCard).color, AppColors.bgSurface);
      expect(find.byKey(AppGlassSurface.strokeKey), findsNothing);
    });

    testWidgets('上限降到 standard：卡片退回磨砂档，仍然是一块玻璃', (tester) async {
      await tester.pumpWidget(host(
        const AppCard(glass: true, child: Text('服务器状态')),
        GlassQuality.standard,
      ));

      expect(find.byType(GlassContainer), findsOneWidget);
      expect(
        tester
            .widget<GlassContainer>(find.byType(GlassContainer))
            .settings!
            .thickness,
        12,
        reason: '拿不到 premium 就整块回到磨砂参数，不留半套',
      );
      expect(find.text('服务器状态'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('玻璃表面有 1px 描边 + 顶部内高光，且不吃布局尺寸', (tester) async {
      await tester.pumpWidget(host(
        const AppCard(glass: true, child: Text('服务器状态')),
        GlassQuality.standard,
      ));

      // 描边：前景 DecoratedBox，1px，圆角和卡片一致。
      final stroke = tester.widget<DecoratedBox>(
        find.byKey(AppGlassSurface.strokeKey),
      );
      expect(stroke.position, DecorationPosition.foreground);
      final strokeDecoration = stroke.decoration as BoxDecoration;
      final border = strokeDecoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.right.width, 1);
      expect(border.bottom.width, 1);
      expect(border.left.width, 1);
      expect(border.top.color.a, lessThan(1.0), reason: '半透明描边');
      expect(strokeDecoration.borderRadius,
          BorderRadius.circular(AppRadius.lg));

      // 高光：白色 appGlassHighlightAlpha() → 0 的线性渐变，
      // IgnorePointer 盖在内容上不挡点击。
      final highlight = tester.widget<DecoratedBox>(
        find.byKey(AppGlassSurface.highlightKey),
      );
      final gradient =
          (highlight.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.first.a, closeTo(appGlassHighlightAlpha(), 1e-9));
      expect(gradient.colors.first.a, greaterThan(0.12),
          reason: 'tint 压下去之后高光要更亮，玻璃才不至于「看不见」');
      expect(gradient.colors.last.a, 0.0);
      expect(gradient.begin, Alignment.topCenter);
      // 高光层最近的 IgnorePointer 一定在忽略命中（点击照样落到 tab/卡片）。
      final pointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byKey(AppGlassSurface.highlightKey),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(pointer.ignoring, isTrue);

      // 描边是前景绘制：卡片高度不受它影响，56 高的胶囊也变不成 58。
      expect(find.text('服务器状态'), findsOneWidget);
    });

    testWidgets('未开 glass 的卡片仍然是不透明卡片', (tester) async {
      await tester.pumpWidget(host(
        const AppCard(child: Text('相册')),
        GlassQuality.standard,
      ));

      expect(find.byType(GlassContainer), findsNothing);
      expect(_firstDecorationUnder(tester, AppCard).color, AppColors.bgSurface);
    });
  });

  group('朋友圈卡片：玻璃只包卡片本体', () {
    Post post() => Post(
          id: 1,
          authorId: 2,
          authorNickname: '妈妈',
          content: '周末去了公园',
          postedAt: DateTime(2026, 1, 1, 10),
          medias: const [],
        );

    Widget host(GlassQuality? quality) {
      final app = MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              PostCard(
                post: post(),
                onOpenMedia: (_, __) {},
                onDeleted: () {},
              ),
            ],
          ),
        ),
      );
      return quality == null
          ? app
          : AppGlassScope(quality: quality, child: app);
    }

    testWidgets('卡片底子是玻璃，列表/页面背景不动', (tester) async {
      await tester.pumpWidget(host(GlassQuality.standard));
      await tester.pump();

      expect(find.byType(GlassContainer), findsOneWidget);
      expect(find.text('周末去了公园'), findsOneWidget);
      // 玻璃只包卡片：外面那层 ListView/页面没有玻璃。
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(GlassContainer),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).body,
          isNot(isA<GlassContainer>()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('每张卡片复用外层 backdrop、与 footer 同档 premium，内容有 RepaintBoundary',
        (tester) async {
      await tester.pumpWidget(host(GlassQuality.premium));
      await tester.pump();

      final surface =
          tester.widget<AppGlassSurface>(find.byType(AppGlassSurface).first);
      expect(surface.useOwnLayer, isFalse, reason: '别让每张卡片各开一层玻璃');
      expect(surface.wantedQuality, AppGlassSurface.kCardQuality,
          reason: '卡片档位只有一个来源：AppGlassSurface.kCardQuality');
      expect(AppGlassSurface.kCardQuality, AppBottomTabBar.preferredQuality,
          reason: '卡片和 footer 是同一档（premium）');

      final container =
          tester.widget<GlassContainer>(find.byType(GlassContainer));
      expect(container.useOwnLayer, isFalse);
      expect(container.quality, GlassQuality.premium);
      // 光学参数与 footer 完全相同：28 / 1.38 / 0.10 / 3。
      final settings = container.settings!;
      expect(settings.thickness, 28);
      expect(settings.refractiveIndex, 1.38);
      expect(settings.chromaticAberration, 0.10);
      expect(settings.blur, 3);
      // 滚动时只重绘玻璃层，卡片内容走缓存。
      expect(
        find.descendant(
          of: find.byType(GlassContainer),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });

    testWidgets('上限降到 standard：卡片退回磨砂参数，仍然是玻璃', (tester) async {
      await tester.pumpWidget(host(GlassQuality.standard));
      await tester.pump();

      final container =
          tester.widget<GlassContainer>(find.byType(GlassContainer));
      expect(container.quality, GlassQuality.standard);
      expect(container.settings!.thickness, 12, reason: '磨砂那套光学参数');
      expect(container.settings!.blur, 8);
      expect(find.text('周末去了公园'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('minimal 档：卡片退化成不透明 bgSurface，没有模糊', (tester) async {
      await tester.pumpWidget(host(GlassQuality.minimal));

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      final decorations = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((e) => e.decoration)
          .whereType<BoxDecoration>();
      expect(decorations.where((d) => d.color == AppColors.bgSurface),
          isNotEmpty);
      expect(find.text('周末去了公园'), findsOneWidget);
    });
  });
}
