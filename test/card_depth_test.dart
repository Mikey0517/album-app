import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/radius.dart';
import 'package:album_app/core/design/shadow.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/models/post.dart';
import 'package:album_app/widgets/app_card.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality;

// 卡片 / 列表的立体感：双层阴影 + 顶部内高光 + 1px 半透明描边。
//
// 三条硬约束：
// 1. 玻璃档仍是 standard（不回到 premium 的 capture），层次全靠静态绘制；
// 2. minimal / 无档位画的是同一套阴影与描边，只是没有模糊——低端机也有层次；
// 3. 圆角取现有 token，按下 / 悬浮不做位移动画（列表不会抖）。

Widget _host(
  Widget child, {
  GlassQuality? quality = GlassQuality.premium,
  bool dark = false,
}) {
  final app = MaterialApp(
    theme: buildAppTheme(dark: dark),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
  return quality == null ? app : AppGlassScope(quality: quality, child: app);
}

/// 卡片上那层阴影装饰（[AppGlassSurface.shadowKey]）。
BoxDecoration _shadowDecoration(WidgetTester tester, Finder card) {
  final layer = tester.widget<DecoratedBox>(
    find
        .descendant(of: card, matching: find.byKey(AppGlassSurface.shadowKey))
        .first,
  );
  return layer.decoration as BoxDecoration;
}

/// 近层 / 远层都要落在约定范围内，且远层更远、更淡。
void _expectTwoLayerShadow(List<BoxShadow> shadows, {required bool dark}) {
  expect(shadows, hasLength(2), reason: '一层近距离 + 一层远距离');
  final near = shadows[0];
  final far = shadows[1];
  // 近层：blur 8~12 / y 2~4 / alpha 0.06~0.10（深色再提高一档）。
  expect(near.blurRadius, inInclusiveRange(8, 12));
  expect(near.offset.dx, 0);
  expect(near.offset.dy, inInclusiveRange(2, 4));
  // 远层：blur 24~32 / y 10~16 / alpha 0.04~0.06。
  expect(far.blurRadius, inInclusiveRange(24, 32));
  expect(far.offset.dx, 0);
  expect(far.offset.dy, inInclusiveRange(10, 16));
  expect(far.blurRadius, greaterThan(near.blurRadius));
  expect(far.offset.dy, greaterThan(near.offset.dy));
  if (dark) {
    expect(near.color.a, inInclusiveRange(0.10, 0.20),
        reason: '深色模式近层 alpha 适度提高');
    expect(far.color.a, inInclusiveRange(0.06, 0.14),
        reason: '深色模式远层 alpha 适度提高');
  } else {
    expect(near.color.a, inInclusiveRange(0.06, 0.10));
    expect(far.color.a, inInclusiveRange(0.04, 0.06));
  }
  // 两层都是黑色阴影，远层比近层更淡（越远越散）。
  expect(near.color.r, 0.0);
  expect(far.color.a, lessThan(near.color.a));
}

void _expectCardLayers(WidgetTester tester, Finder card, {bool dark = false}) {
  final decoration = _shadowDecoration(tester, card);
  _expectTwoLayerShadow(decoration.boxShadow!, dark: dark);
  // 阴影跟着圆角走，圆角仍是现有 token。
  expect(decoration.borderRadius, BorderRadius.circular(AppRadius.lg));

  // 顶部内高光：白 6% → 0 的极淡渐变（磨砂不靠反光），IgnorePointer 不挡点击。
  final highlight = tester.widget<DecoratedBox>(
    find
        .descendant(of: card, matching: find.byKey(AppGlassSurface.highlightKey))
        .first,
  );
  final gradient =
      (highlight.decoration as BoxDecoration).gradient! as LinearGradient;
  expect(gradient.begin, Alignment.topCenter);
  expect(gradient.colors.first.a, closeTo(appCardHighlightAlpha(), 1e-9));
  expect(gradient.colors.first.a, inInclusiveRange(0.04, 0.08));
  expect(gradient.colors.last.a, 0.0);
  expect(
    tester
        .widget<IgnorePointer>(
          find
              .ancestor(
                of: find
                    .descendant(
                        of: card,
                        matching: find.byKey(AppGlassSurface.highlightKey))
                    .first,
                matching: find.byType(IgnorePointer),
              )
              .first,
        )
        .ignoring,
    isTrue,
  );

  // 1px 半透明描边：前景绘制，不吃布局；浅色黑 8% / 深色白 12%。
  final stroke = tester.widget<DecoratedBox>(
    find
        .descendant(of: card, matching: find.byKey(AppGlassSurface.strokeKey))
        .first,
  );
  expect(stroke.position, DecorationPosition.foreground);
  final strokeDecoration = stroke.decoration as BoxDecoration;
  final border = strokeDecoration.border! as Border;
  for (final side in [border.top, border.right, border.bottom, border.left]) {
    expect(side.width, 1);
    expect(side.color.a, lessThan(1.0));
  }
  expect(border.top.color,
      dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08));
  expect(strokeDecoration.borderRadius, BorderRadius.circular(AppRadius.lg));

  // 不做位移动画：按下 / 悬浮不会平移或缩放卡片（列表不抖）。
  // 只查「改位置/尺寸」的那几类；AnimatedContainer 那种纯换色的装饰动画不算。
  for (final type in <Type>[
    AnimatedScale,
    AnimatedSlide,
    AnimatedPositioned,
    AnimatedPadding,
  ]) {
    expect(
      find.descendant(of: card, matching: find.byType(type)),
      findsNothing,
      reason: '卡片按下/悬浮不做位移动画：$type',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppColors.setDark(false));

  testWidgets('standard 玻璃卡片：两层阴影 + 顶部高光 + 1px 描边', (tester) async {
    AppColors.setDark(false);
    await tester.pumpWidget(
      _host(const AppCard(glass: true, child: Text('服务器状态'))),
    );
    await tester.pump();

    // 玻璃仍是 standard：不抓 capture，立体感全在静态绘制里。
    expect(AppGlassSurface.kCardQuality, GlassQuality.standard);
    expect(
      tester.widget<GlassContainer>(find.byType(GlassContainer)).quality,
      GlassQuality.standard,
    );
    _expectCardLayers(tester, find.byType(AppCard));

    // 高光/描边都不吃布局：卡片高度只由内容 + padding 决定。
    expect(tester.getSize(find.byType(AppCard)).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色模式：阴影 alpha 提高、描边换成白 12%', (tester) async {
    AppColors.setDark(false);
    final light = AppShadow.card;
    AppColors.setDark(true);
    final dark = AppShadow.card;
    expect(dark[0].color.a, greaterThan(light[0].color.a),
        reason: '深色底上黑影更难看见，近层要更实');
    expect(dark[1].color.a, greaterThan(light[1].color.a),
        reason: '远层同理');
    // 两层的位置/模糊不随明暗变，只是 alpha 提高。
    expect(dark[0].blurRadius, light[0].blurRadius);
    expect(dark[0].offset, light[0].offset);
    expect(dark[1].blurRadius, light[1].blurRadius);
    expect(dark[1].offset, light[1].offset);

    await tester.pumpWidget(
      _host(
        const AppCard(glass: true, child: Text('服务器状态')),
        dark: true,
      ),
    );
    await tester.pump();
    _expectCardLayers(tester, find.byType(AppCard), dark: true);
  });

  testWidgets('minimal 档：卡片仍有阴影与描边，但没有模糊', (tester) async {
    AppColors.setDark(false);
    await tester.pumpWidget(
      _host(
        const AppCard(glass: true, child: Text('服务器状态')),
        quality: GlassQuality.minimal,
      ),
    );

    expect(find.byType(GlassContainer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing, reason: 'minimal 不加模糊');
    // 同样的阴影 / 高光 / 描边：低端机上卡片也有层次。
    _expectCardLayers(tester, find.byType(AppCard));
    // 底子还是不透明卡片，不是透明塑料片。
    expect(
      tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(AppCard),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.color != null)
          .every((decoration) => decoration.color == AppColors.bgSurface),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有任何玻璃档位：同样有阴影与描边，没有 BackdropFilter', (tester) async {
    AppColors.setDark(false);
    await tester.pumpWidget(
      _host(
        const AppCard(glass: true, child: Text('服务器状态')),
        quality: null,
      ),
    );

    expect(find.byType(GlassContainer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    _expectCardLayers(tester, find.byType(AppCard));
  });

  testWidgets('不透明 AppCard 与玻璃卡走同一套立体感', (tester) async {
    AppColors.setDark(false);
    await tester.pumpWidget(
      _host(const AppCard(child: Text('相册'))),
    );
    expect(find.byType(GlassContainer), findsNothing);
    _expectCardLayers(tester, find.byType(AppCard));
    // 底子仍是原来的不透明卡片色。
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
      decorations.any((decoration) => decoration.color == AppColors.bgSurface),
      isTrue,
    );
  });

  testWidgets('朋友圈卡片（列表项）也有同一套立体感', (tester) async {
    AppColors.setDark(false);
    await tester.pumpWidget(
      _host(
        ListView(
          children: [
            PostCard(
              post: Post(
                id: 1,
                authorId: 2,
                authorNickname: '妈妈',
                content: '周末去了公园',
                postedAt: DateTime(2026, 1, 1, 10),
                medias: const [],
              ),
              onOpenMedia: (_, __) {},
              onDeleted: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    _expectCardLayers(tester, find.byType(PostCard));
    expect(tester.takeException(), isNull);
  });
}
