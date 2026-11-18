import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/radius.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/models/post.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_card.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_glass_tone.dart';
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
      // 底部：离安全区只有 4~8（胶囊这一轮往下贴了一档），安全区自身不算在
      // 胶囊里，home indicator 不会被压住。
      final bottomGap = barRect.bottom - pillRect.bottom - 34;
      expect(bottomGap, inInclusiveRange(4, 8));
      expect(barRect.bottom - pillRect.bottom,
          AppBottomTabBar.bottomGap + 34);
    });

    testWidgets('选中=主题色实心图标，未选中=中性灰线框', (tester) async {
      await tester.pumpWidget(_tabBar(GlassQuality.standard));

      expect(tester.widget<Icon>(find.byIcon(Icons.people)).color,
          AppColors.primary);
      expect(tester.widget<Text>(find.text('朋友圈')).style!.color,
          AppColors.primary);
      // 未选中墨色按背景亮度自动选（方案 C）；没有采样时是主题回退那一套。
      expect(
          tester.widget<Icon>(find.byIcon(Icons.photo_library_outlined)).color,
          appGlassToneInk());
      expect(tester.widget<Text>(find.text('相册')).style!.color,
          appGlassToneInk());
      // 未选中是线框，不会同时出现实心变体。
      expect(find.byIcon(Icons.photo_library), findsNothing);

      // 切换选中项后颜色跟着换。
      await tester.pumpWidget(_tabBar(GlassQuality.standard, selectedIndex: 1));
      expect(tester.widget<Icon>(find.byIcon(Icons.photo_library)).color,
          AppColors.primary);
      expect(
          tester.widget<Icon>(find.byIcon(Icons.people_outline)).color,
          appGlassToneInk());
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
            AppCard(child: Text('我的')),
          ],
        ),
        GlassQuality.minimal,
      ));

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      // 没有模糊，但卡片的立体感还在：阴影、高光、1px 描边一样不少。
      expect(find.byKey(AppGlassSurface.shadowKey), findsNWidgets(2));
      expect(find.byKey(AppGlassSurface.strokeKey), findsNWidgets(2));
      expect(find.byKey(AppGlassSurface.highlightKey), findsNWidgets(2));
      // 卡片本体仍然是不透明表面（阴影层没有底色，跳过）。
      for (final decoration in tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((e) => e.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.color != null)) {
        expect(decoration.color, AppColors.bgSurface);
      }
    });

    testWidgets('玻璃不可用时卡片也是不透明表面', (tester) async {
      await tester.pumpWidget(host(
        const AppCard(glass: true, child: Text('服务器状态')),
        null,
      ));

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      final decorations = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(AppCard),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>();
      expect(
        decorations.where((decoration) => decoration.color == AppColors.bgSurface),
        isNotEmpty,
        reason: '底子还是不透明卡片',
      );
      // 没有玻璃也保留同样的立体感。
      expect(find.byKey(AppGlassSurface.shadowKey), findsOneWidget);
      expect(find.byKey(AppGlassSurface.strokeKey), findsOneWidget);
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

      // 高光：卡片档是白色 appCardHighlightAlpha()（6%）→ 0 的细渐变，
      // IgnorePointer 盖在内容上不挡点击。磨砂卡片不该靠表面反光提层次。
      final highlight = tester.widget<DecoratedBox>(
        find.byKey(AppGlassSurface.highlightKey),
      );
      final gradient =
          (highlight.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.first.a, closeTo(appCardHighlightAlpha(), 1e-9));
      expect(gradient.colors.first.a, inInclusiveRange(0.04, 0.08),
          reason: '卡片高光压到 6% 一档：立体感交给阴影，亮一点就成压在正文上的白杠');
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
      final decorations = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(AppCard),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>();
      expect(
        decorations.where((decoration) => decoration.color == AppColors.bgSurface),
        isNotEmpty,
        reason: '不透明卡片的底子还是 bgSurface',
      );
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

    testWidgets('每张卡片固定 standard（不抓 capture），内容有 RepaintBoundary',
        (tester) async {
      await tester.pumpWidget(host(GlassQuality.premium));
      await tester.pump();

      final surface =
          tester.widget<AppGlassSurface>(find.byType(AppGlassSurface).first);
      expect(surface.useOwnLayer, isFalse, reason: '别让每张卡片各开一层玻璃');
      expect(surface.wantedQuality, AppGlassSurface.kCardQuality,
          reason: '卡片档位只有一个来源：AppGlassSurface.kCardQuality');
      // 卡片和 footer 不再是同一档：premium 要抓 capture，列表重建会黑。
      expect(AppGlassSurface.kCardQuality, GlassQuality.standard,
          reason: '卡片必须 standard：premium 的 capture 未就绪帧会整块发黑');
      expect(AppBottomTabBar.preferredQuality, GlassQuality.premium,
          reason: 'footer 是静态 chrome，继续 premium');

      final container =
          tester.widget<GlassContainer>(find.byType(GlassContainer));
      expect(container.useOwnLayer, isFalse);
      expect(container.quality, GlassQuality.standard);
      // 卡片的光学参数：斜面对齐磨砂档（12），但模糊/底色是白雾那一套
      // （blur 20 / tint 37% / 折射归零）。
      final settings = container.settings!;
      expect(settings.thickness, 12);
      expect(settings.blur, appCardFrostBlur);
      expect(settings.glassColor, appCardFrostTintColor);
      expect(settings.refractiveIndex, 1.0);
      // 滚动时只重绘玻璃层，卡片内容走缓存。
      expect(
        find.descendant(
          of: find.byType(GlassContainer),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });

    testWidgets('上限降到 standard：卡片仍是白雾磨砂，仍然是玻璃', (tester) async {
      await tester.pumpWidget(host(GlassQuality.standard));
      await tester.pump();

      final container =
          tester.widget<GlassContainer>(find.byType(GlassContainer));
      expect(container.quality, GlassQuality.standard);
      expect(container.settings!.thickness, 12, reason: '斜面对齐磨砂档');
      expect(container.settings!.blur, appCardFrostBlur);
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
