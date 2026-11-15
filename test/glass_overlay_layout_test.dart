import 'dart:convert';

import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_tab_page.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/features/profile/profile_page.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

/// 悬浮胶囊不是「页面让出一块空地」：内容要真的滚到胶囊底下，磨砂后面才有
/// 东西可模糊。这一组测试守的是这条几何关系——页面背景透明、没有为胶囊留
/// 高度的内边距、滚到底时内容确实越过了胶囊上沿。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 十条纯文字动态：内容一定比视口长，能滚到底。
  String feedJson() {
    return jsonEncode({
      'items': [
        for (var i = 0; i < 10; i++)
          {
            'id': i + 1,
            'author_id': 1,
            'author_nickname': '妈妈',
            'content': '第 $i 条动态，周末去了公园，拍了一下午照片。',
            'posted_at':
                '2026-01-${(i + 1).toString().padLeft(2, '0')}T10:00:00Z',
            'medias': <dynamic>[],
          },
      ],
      'next_cursor': null,
    });
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('朋友圈：滚到底时最后一条动态越过胶囊上沿，页面底色是渐变不是纯白', (tester) async {
    phone(tester);
    addTearDown(installFakeApi(json: feedJson()));

    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const FeedPage()),
    );
    await tester.pumpAndSettle();

    // 背景：Scaffold 自己不上色，底色交给 AppGlassBackdrop 的渐变。
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.transparent);
    expect(scaffold.extendBody, isTrue, reason: 'body 要一直铺到屏幕底边，胶囊才能盖在内容上');
    expect(find.byType(AppGlassBackdrop), findsOneWidget);

    final context = tester.element(find.byType(FeedPage));
    final capsuleTop = 780 - AppBottomTabBar.overlayInset(context);

    // 视口一直铺到屏幕底边：旧版给 body 套了 Padding(bottom: 胶囊高度)，
    // 视口底边被抬到胶囊上沿，胶囊正下方永远没有内容。
    expect(tester.getRect(find.byType(CustomScrollView)).bottom, 780);

    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;

    // 往下滚一段：最后一条动态的下沿越过胶囊上沿，整张卡片压在胶囊带里。
    position.jumpTo(position.maxScrollExtent - 140);
    await tester.pump();
    final lastCard = find.byType(PostCard).last;
    final cardRect = tester.getRect(lastCard);
    expect(
      cardRect.bottom,
      greaterThan(capsuleTop),
      reason: '最后一条动态要能滑进胶囊盖住的那条带子，胶囊底下才有内容',
    );
    expect(
      cardRect.top,
      lessThan(capsuleTop),
      reason: '卡片要真的和胶囊重叠，不是刚好贴在它上沿',
    );

    // 滚到底：末尾只留「已经到底啦」那点留白（36，≈半个胶囊高），
    // 内容仍然在胶囊带里，不是整条缩回胶囊上方。
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final footer = find.text('已经到底啦');
    expect(footer, findsOneWidget);
    expect(
      tester.getRect(footer).bottom,
      greaterThan(capsuleTop),
      reason: '滚到底时胶囊底下也得有内容，否则磨砂后面又只剩空底色',
    );
  });

  testWidgets('相册：背景透明 + 渐变铺底，网格不再被为胶囊留的 Padding 抬高', (tester) async {
    phone(tester);
    addTearDown(installFakeApi());

    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const AlbumTabPage()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, Colors.transparent);
    expect(scaffold.extendBody, isTrue);
    expect(find.byType(AppGlassBackdrop), findsOneWidget);

    // 头部也是透明的、无底色：和朋友圈 / 我的同一套，分类标题直接浮在
    // AppGlassBackdrop 那层渐变/背景图上，不再是一条不透明的页面底色。
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.transparent,
        reason: '相册总页头部不许有底色（要求：背景透上来）');
    expect(appBar.surfaceTintColor, Colors.transparent);
    expect(appBar.scrolledUnderElevation, 0,
        reason: '滚动时 M3 的「变色」也要关掉，背景不许被整块遮住');
    expect(appBar.elevation, 0, reason: '头部不投阴影');
    // 头部那一块 AppBar 自己的 Material 也不上色，背景才透得上来。
    final headerMaterial = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AppBar),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(headerMaterial.color, Colors.transparent,
        reason: 'AppBar 的 Material 一旦上色就整块盖住背景');

    // 页面 body 直接就是内容分栏：多选态（胶囊隐藏）时也不会留下空隙，
    // 因为这里根本没有为胶囊预留高度的内边距。
    final body = scaffold.body!;
    expect(body, isA<GestureDetector>());
    expect(
      (body as GestureDetector).child,
      isA<IndexedStack>(),
      reason: 'body 外面套 Padding(bottom: 胶囊高度) 会把网格整块抬高，胶囊下面变回空底',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的：背景透明 + 渐变铺底，卡片滚到胶囊底下', (tester) async {
    phone(tester);
    CurrentUser.notifier.value = const AppUser(
      id: 1,
      userId: 'mikey',
      nickname: 'Mikey',
    );
    addTearDown(() => CurrentUser.notifier.value = null);
    addTearDown(installFakeApi());

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ProfilePage(onLogout: () {}),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.transparent);
    expect(scaffold.extendBody, isTrue);
    expect(find.byType(AppGlassBackdrop), findsOneWidget);

    // 滚动区只留半个胶囊高：不是整块让出 overlayInset。
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );
    final padding = scroll.padding as EdgeInsets;
    expect(padding.bottom, 24 + AppBottomTabBar.contentBottomInset);
    expect(
      padding.bottom,
      lessThan(AppBottomTabBar.overlayInset(
          tester.element(find.byType(ProfilePage)))),
      reason: '让出整个胶囊高度就等于胶囊正下方没有内容可模糊',
    );
  });
}
