import 'dart:convert';

import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/custom_albums_page.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/features/profile/profile_page.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/models/post.dart';
import 'package:album_app/widgets/app_card.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

// 卡片的材质只有一块：**外框 = 内容 + padding，玻璃铺满整个外框，内容再内缩。**
//
// 这条几何一旦被破坏（padding 跑到玻璃外侧、或者装饰层被 padding 缩进一圈），
// 卡片上就同时出现两种底色：内容区一块、留白一块，看着像两块拼起来的。
// 这里三处逐一对齐：朋友圈的 PostCard、我的页的卡片组、相册页的卡片。

Post _post() => Post(
      id: 1,
      authorId: 2,
      authorNickname: '妈妈',
      content: '周末去了公园',
      postedAt: DateTime(2026, 1, 1, 10),
      medias: const [],
    );

// 默认注入 premium（上限放到最高）：卡片自己固定在 standard、不抓 capture
// （见 AppGlassSurface.kCardQuality），几何断言在 standard 这条路上成立。
// minimal / 无档位的退化用例自己显式传档位。
Widget _host(Widget child, {GlassQuality? quality = GlassQuality.premium}) {
  final app = MaterialApp(theme: buildAppTheme(), home: child);
  if (quality == null) return app;
  return AppGlassScope(quality: quality, child: app);
}

Widget _scaffoldBody(Widget child,
    {GlassQuality? quality = GlassQuality.premium}) {
  return _host(Scaffold(body: child), quality: quality);
}

/// 外框 = 内容 + padding：留白在玻璃里面，不是玻璃外面的一圈。
void _expectFrameContainsPadding(
  WidgetTester tester, {
  required Finder frame,
  required Finder content,
  required EdgeInsets padding,
}) {
  final f = tester.getRect(frame);
  final c = tester.getRect(content);
  expect(f.width, moreOrLessEquals(c.width + padding.horizontal, epsilon: 0.01),
      reason: '外框宽 = 内容宽 + 左右 padding');
  expect(f.height, moreOrLessEquals(c.height + padding.vertical, epsilon: 0.01),
      reason: '外框高 = 内容高 + 上下 padding');
  expect(f.center.dx, moreOrLessEquals(c.center.dx, epsilon: 0.01));
  expect(f.center.dy, moreOrLessEquals(c.center.dy, epsilon: 0.01));
}

/// 卡片上的装饰层（scrim / 顶部内高光）也必须铺满外框，不能被 padding 缩进——
/// 缩进去就会在外框上留下一条没有装饰的边，那正是「两块材质」的观感来源。
///
/// 注意外框取的是玻璃（[GlassContainer]）的矩形：`AppGlassSurface` 带 margin 时
/// 它自己的矩形包含 margin，margin 本来就在玻璃外面。
void _expectLayersCoverFrame(WidgetTester tester, Finder surface) {
  final glass = find.descendant(
    of: surface,
    matching: find.byType(GlassContainer),
  );
  expect(glass, findsOneWidget);
  final frame = tester.getRect(glass);
  final highlight = find.descendant(
    of: surface,
    matching: find.byKey(AppGlassSurface.highlightKey),
  );
  expect(highlight, findsOneWidget);
  expect(tester.getRect(highlight), frame,
      reason: '装饰层要铺满玻璃所在的整个外框，不能被 padding 缩进一圈');
}

/// 外框和内容之间不许再夹一层不透明底（那就是第二块材质）。
void _expectNoOpaqueBoxBetween(
  WidgetTester tester, {
  required Finder frame,
  required Finder content,
}) {
  final frameElement = tester.element(frame);
  tester.element(content).visitAncestorElements((element) {
    if (identical(element, frameElement)) return false;
    final widget = element.widget;
    if (widget is DecoratedBox) {
      final decoration = widget.decoration;
      final color = decoration is BoxDecoration ? decoration.color : null;
      if (color != null) {
        expect(color.a, lessThan(1.0),
            reason: '外框和内容之间不该有不透明的底色块');
      }
    }
    return true;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('PostCard：外框 = 内容 + padding，玻璃铺满整个外框', (tester) async {
    await tester.pumpWidget(_scaffoldBody(
      ListView(
        children: [
          PostCard(post: _post(), onOpenMedia: (_, __) {}, onDeleted: () {}),
        ],
      ),
    ));
    await tester.pump();

    final surface = find.byType(AppGlassSurface).first;
    final content = find
        .descendant(of: find.byType(PostCard), matching: find.byType(Column))
        .first;
    _expectFrameContainsPadding(
      tester,
      frame: surface,
      content: content,
      padding: const EdgeInsets.all(16),
    );

    // 玻璃（GlassContainer）和外框同尺寸：留白处也是玻璃，不是页面底色。
    expect(tester.getRect(find.byType(GlassContainer)), tester.getRect(surface));
    // 卡片固定 standard：白雾磨砂参数（blur 20 / tint 37% / 折射归零），
    // 不做 premium 的 capture。
    final container =
        tester.widget<GlassContainer>(find.byType(GlassContainer));
    expect(container.quality, GlassQuality.standard,
        reason: 'premium 的 capture 会在列表重建那一帧画出黑块');
    expect(container.settings!.thickness, 12, reason: '斜面仍是磨砂那档');
    expect(container.settings!.blur, appCardFrostBlur);
    expect(container.settings!.blur, inInclusiveRange(18, 24));
    expect(container.settings!.glassColor, appCardFrostTintColor);
    expect(container.useOwnLayer, isFalse);
    _expectLayersCoverFrame(tester, surface);
    _expectNoOpaqueBoxBetween(tester, frame: surface, content: content);
  });

  testWidgets('AppCard(glass)：外框包含 padding，玻璃铺满，内容只是内缩', (tester) async {
    await tester.pumpWidget(_scaffoldBody(
      const AppCard(
        glass: true,
        padding: EdgeInsets.all(16),
        child: SizedBox(key: Key('card-content'), width: 100, height: 40),
      ),
    ));
    await tester.pump();

    const content = Key('card-content');
    // 100x40 + 16 一周 = 132x72：padding 算进外框，不是外框外面的一圈。
    expect(tester.getSize(find.byType(AppCard)), const Size(132, 72));
    _expectFrameContainsPadding(
      tester,
      frame: find.byType(AppCard),
      content: find.byKey(content),
      padding: const EdgeInsets.all(16),
    );
    expect(
      tester.getRect(find.byType(GlassContainer)),
      tester.getRect(find.byType(AppCard)),
    );
    _expectLayersCoverFrame(tester, find.byType(AppCard));
    _expectNoOpaqueBoxBetween(
      tester,
      frame: find.byType(AppCard),
      content: find.byKey(content),
    );
  });

  testWidgets('我的页卡片组：每块玻璃都铺满外框，padding 在玻璃里面', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CurrentUser.notifier.value = const AppUser(
      id: 1,
      userId: 'mikey',
      nickname: 'Mikey',
    );
    addTearDown(() => CurrentUser.notifier.value = null);
    addTearDown(installFakeApi());

    await tester.pumpWidget(
      _host(ProfilePage(onLogout: () {})),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final surfaces = find.byType(AppGlassSurface);
    expect(surfaces.evaluate().length, greaterThanOrEqualTo(2),
        reason: '头像卡 + 存储卡/设置组至少两块玻璃');
    for (var i = 0; i < surfaces.evaluate().length; i++) {
      _expectLayersCoverFrame(tester, surfaces.at(i));
    }

    // 头像卡 padding 20：玻璃比内容四周各大 20。
    final avatar = surfaces.first;
    final avatarGlass = find.descendant(
      of: avatar,
      matching: find.byType(GlassContainer),
    );
    final row = find.descendant(of: avatar, matching: find.byType(Row)).first;
    _expectFrameContainsPadding(
      tester,
      frame: avatarGlass,
      content: row,
      padding: const EdgeInsets.all(20),
    );
  });

  testWidgets('相册页：新建相册卡片和另两处走同一条材质路径', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(installFakeApi(
      json: jsonEncode({
        'items': [
          {
            'id': 7,
            'title': '夏天',
            'media_count': 3,
            'visibility': 'family',
            'created_at': '2026-01-01T00:00:00Z',
          },
        ],
      }),
    ));

    await tester.pumpWidget(
      _host(const CustomAlbumsPage(scope: AlbumScope.family)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final card = find.widgetWithText(AppCard, '新建相册');
    expect(card, findsOneWidget,
        reason: '相册页唯一的卡片要和我的页/朋友圈共用 AppCard 这条材质路径');
    expect(
      tester.getRect(
        find.descendant(of: card, matching: find.byType(GlassContainer)),
      ),
      tester.getRect(card),
      reason: '玻璃铺满整个外框（含 padding）',
    );
    _expectLayersCoverFrame(tester, card);
  });

  testWidgets('minimal 档：padding 仍然在底子内部，外框 = 内容 + padding', (tester) async {
    await tester.pumpWidget(_scaffoldBody(
      const AppGlassSurface(
        radius: 16,
        padding: EdgeInsets.all(12),
        child: SizedBox(key: Key('plain-content'), width: 80, height: 24),
      ),
      quality: GlassQuality.minimal,
    ));

    expect(find.byType(GlassContainer), findsNothing);
    _expectFrameContainsPadding(
      tester,
      frame: find.byType(AppGlassSurface),
      content: find.byKey(const Key('plain-content')),
      padding: const EdgeInsets.all(12),
    );
    // 不透明底子的绘制区域就是外框：留白处不会被换成另一种底色。
    expect(
      tester.getRect(
        find
            .descendant(
              of: find.byType(AppGlassSurface),
              matching: find.byType(DecoratedBox),
            )
            .first,
      ),
      tester.getRect(find.byType(AppGlassSurface)),
    );
  });
}
