import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/models/post.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_card.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show AnimatedGlassIndicator, GlassContainer, GlassQuality, GlassTabBar;

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

      // 玻璃铺满整条栏：只有一块玻璃表面，且不属于任何一个 tab。
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

      final bar = tester.getSize(find.byType(AppBottomTabBar));
      expect(bar.height, AppBottomTabBar.barHeight);
      expect(bar.height, 56);

      final cells = find.byType(InkWell);
      expect(cells, findsNWidgets(3));
      final widths = [
        for (final element in cells.evaluate())
          tester.getSize(find.byWidget(element.widget)).width,
      ];
      expect(widths, [bar.width / 3, bar.width / 3, bar.width / 3]);

      await tester.tap(find.text('相册'));
      await tester.tap(find.text('我的'));
      expect(tapped, [1, 2]);
    });

    testWidgets('选中=主题色实心图标，未选中=中性灰线框', (tester) async {
      await tester.pumpWidget(_tabBar(GlassQuality.standard));

      expect(tester.widget<Icon>(find.byIcon(Icons.people)).color,
          AppColors.primary);
      expect(tester.widget<Text>(find.text('朋友圈')).style!.color,
          AppColors.primary);
      expect(
          tester.widget<Icon>(find.byIcon(Icons.photo_library_outlined)).color,
          AppColors.textSecondary);
      expect(tester.widget<Text>(find.text('相册')).style!.color,
          AppColors.textSecondary);
      // 未选中是线框，不会同时出现实心变体。
      expect(find.byIcon(Icons.photo_library), findsNothing);

      // 切换选中项后颜色跟着换。
      await tester.pumpWidget(_tabBar(GlassQuality.standard, selectedIndex: 1));
      expect(tester.widget<Icon>(find.byIcon(Icons.photo_library)).color,
          AppColors.primary);
      expect(
          tester.widget<Icon>(find.byIcon(Icons.people_outline)).color,
          AppColors.textSecondary);
    });

    testWidgets('minimal 档：整条栏退化成不透明 bgSurface + 顶部 1px 分隔线',
        (tester) async {
      await tester.pumpWidget(_tabBar(GlassQuality.minimal));

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing, reason: 'minimal 不加模糊');

      final decoration = _firstDecorationUnder(tester, AppBottomTabBar);
      expect(decoration.color, AppColors.bgSurface);
      final border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, AppColors.divider);

      // 布局不变：还是 56 高、三个等宽 tab。
      expect(tester.getSize(find.byType(AppBottomTabBar)).height, 56);
      expect(find.byType(InkWell), findsNWidgets(3));
      expect(find.byType(GlassTabBar), findsNothing);
    });

    testWidgets('玻璃不可用（没有任何档位）时同样是不透明表面', (tester) async {
      await tester.pumpWidget(_barHost(
        AppBottomTabBar(
          selectedIndex: 0,
          onSelected: (_) {},
          items: _tabs,
        ),
      ));

      expect(find.byType(GlassContainer), findsNothing);
      expect(_firstDecorationUnder(tester, AppBottomTabBar).color,
          AppColors.bgSurface);
      expect(tester.getSize(find.byType(AppBottomTabBar)).height, 56);
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
    });

    testWidgets('standard 档：卡片本体是玻璃，内容还在', (tester) async {
      await tester.pumpWidget(host(
        const AppCard(glass: true, child: Text('服务器状态')),
        GlassQuality.standard,
      ));

      expect(find.byType(GlassContainer), findsOneWidget);
      expect(find.text('服务器状态'), findsOneWidget);
      expect(tester.takeException(), isNull);
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

    testWidgets('每张卡片复用外层 backdrop、要 standard 档，内容有 RepaintBoundary',
        (tester) async {
      await tester.pumpWidget(host(GlassQuality.standard));
      await tester.pump();

      final surface =
          tester.widget<AppGlassSurface>(find.byType(AppGlassSurface).first);
      expect(surface.useOwnLayer, isFalse, reason: '别让每张卡片各开一层玻璃');
      expect(surface.requestedQuality, GlassQuality.standard,
          reason: 'premium 会每帧抓全屏纹理，列表里不能用');

      final container =
          tester.widget<GlassContainer>(find.byType(GlassContainer));
      expect(container.useOwnLayer, isFalse);
      expect(container.quality, GlassQuality.standard);
      // 滚动时只重绘玻璃层，卡片内容走缓存。
      expect(
        find.descendant(
          of: find.byType(GlassContainer),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
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
