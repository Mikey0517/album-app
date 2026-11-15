import 'dart:async';
import 'dart:convert';

import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/text_styles.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/custom_albums_page.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/features/profile/profile_page.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/models/post.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_card.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassAdaptiveScope, GlassContainer, GlassQuality;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';
import 'support/glass_contrast.dart';

// 问题 A / B 的回归测试：
// A - 材质不许自动回退：档位是静态的，跑慢帧也不降；刷新期间卡片换同色不透明
//     表面、刷新一结束回到 premium（档位本身不变）。
// B - 玻璃上的小字对玻璃合成底色 ≥ 4.5:1（浅色/深色各一条），并且两处已知
//     位置（「新建相册」、我的页右侧数值）真的用了那个 token。

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

Post _post() => Post(
      id: 1,
      authorId: 2,
      authorNickname: '妈妈',
      content: '周末去了公园',
      postedAt: DateTime(2026, 1, 1, 10),
      medias: const [],
    );

/// 第一块玻璃的档位/参数（列表里可能有多张卡片，取第一张就够断言）。
GlassContainer _glass(WidgetTester tester) =>
    tester.widget<GlassContainer>(find.byType(GlassContainer).first);

Widget _markApp(GlassQuality quality, Widget home) => AppGlassScope(
      quality: quality,
      child: MaterialApp(theme: buildAppTheme(), home: home),
    );

String _feedJson() => jsonEncode({
      'items': [
        for (var i = 0; i < 3; i++)
          {
            'id': i + 1,
            'author_id': 1,
            'author_nickname': '妈妈',
            'content': '第 $i 条动态',
            'posted_at': '2026-01-0${i + 1}T10:00:00Z',
            'medias': <dynamic>[],
          },
      ],
      'next_cursor': null,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppGlassRefreshHold.reset();
    CurrentUser.notifier.value = const AppUser(
      id: 1,
      userId: 'mikey',
      nickname: 'Mikey',
    );
  });

  tearDown(() {
    AppGlassRefreshHold.reset();
    CurrentUser.notifier.value = null;
    // buildAppTheme 会改 AppColors 的全局明暗标记，别留给下一个用例。
    buildAppTheme();
  });

  group('A1 档位是静态的：不会自动降档', () {
    test('静态档位只由平台能力决定，没有任何性能/时间输入', () {
      // shader 在、平台不封顶 → premium（真机 Impeller 就这一档）。
      expect(
        appGlassStaticQualityFor(
          shaderFilterSupported: true,
          premiumCappedPlatform: false,
        ),
        GlassQuality.premium,
      );
      // 平台把 premium 封顶（Web/桌面）→ 磨砂档，玻璃还在。
      expect(
        appGlassStaticQualityFor(
          shaderFilterSupported: true,
          premiumCappedPlatform: true,
        ),
        GlassQuality.standard,
      );
      // 连 shader filter 都没有 → 不透明表面（这是唯一「不能画玻璃」的退路）。
      expect(
        appGlassStaticQualityFor(
          shaderFilterSupported: false,
          premiumCappedPlatform: false,
        ),
        GlassQuality.minimal,
      );
    });

    testWidgets('根节点不再插入自适应 scope：连跑 60 帧慢帧仍是 premium',
        (tester) async {
      await tester.pumpWidget(appGlassRoot(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: AppCard(glass: true, child: Text('卡片')),
            ),
          ),
        ),
        quality: GlassQuality.premium,
      ));
      await tester.pump();

      // 旧版 wrap(adaptiveQuality: true) 就是在这里插一个 GlassAdaptiveScope，
      // 它的 Phase 3 会按 P95 掉帧往下降档——现在整棵树里不该有它。
      expect(
        find.byType(GlassAdaptiveScope),
        findsNothing,
        reason: '没有自适应 scope 就没有自动降档的入口',
      );

      // 60 帧、每帧 40ms：足够触发旧版的降档判定（P95 > 1.5 × 16ms 连续 3 窗）。
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      final container = _glass(tester);
      expect(container.quality, GlassQuality.premium,
          reason: '掉帧不许改档位');
      expect(container.settings!.thickness, 28,
          reason: '仍是 premium 那一套光学参数（不是磨砂的 12）');
      expect(AppGlassRefreshHold.isActive, isFalse);
    });
  });

  group('A2 刷新期间：卡片换同色不透明表面，结束回 premium', () {
    testWidgets('PostCard：刷新保持期间没有玻璃，释放后回到 premium', (tester) async {
      await tester.pumpWidget(_markApp(
        GlassQuality.premium,
        Scaffold(
          body: ListView(
            children: [
              PostCard(
                post: _post(),
                onOpenMedia: (_, __) {},
                onDeleted: () {},
              ),
            ],
          ),
        ),
      ));
      await tester.pump();

      expect(_glass(tester).quality, GlassQuality.premium);

      AppGlassRefreshHold.begin();
      await tester.pump();

      expect(find.byType(GlassContainer), findsNothing,
          reason: '刷新这几帧不画玻璃，避免采样到不稳定的 backdrop');
      final opaque = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(AppGlassSurface),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((e) => e.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color == AppColors.bgSurface);
      expect(opaque, isNotEmpty, reason: '换成同色不透明表面，布局不变');

      AppGlassRefreshHold.end();
      await tester.pump();

      final restored = _glass(tester);
      expect(restored.quality, GlassQuality.premium, reason: '刷新结束回到 premium');
      expect(restored.settings!.thickness, 28, reason: '同一套 premium 参数');
      expect(tester.takeException(), isNull);
    });

    testWidgets('底部胶囊是静态 chrome：刷新保持期间照样是 premium 玻璃',
        (tester) async {
      await tester.pumpWidget(_markApp(
        GlassQuality.premium,
        Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: AppBottomTabBar(
            selectedIndex: 0,
            onSelected: (_) {},
            items: _tabs,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      AppGlassRefreshHold.begin();
      await tester.pump();

      expect(find.byType(GlassContainer), findsOneWidget,
          reason: '胶囊背后是页面底图，不跟刷新一起抖，不需要暂停');
      expect(_glass(tester).quality, GlassQuality.premium);
      AppGlassRefreshHold.end();
    });

    testWidgets('appGlassWhileRefreshing：任务期间保持，完成/抛异常都释放',
        (tester) async {
      final gate = Completer<void>();
      final running = appGlassWhileRefreshing<void>(() => gate.future);
      expect(AppGlassRefreshHold.isActive, isTrue);
      gate.complete();
      await running;
      expect(AppGlassRefreshHold.isActive, isFalse);

      await expectLater(
        appGlassWhileRefreshing<void>(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(AppGlassRefreshHold.isActive, isFalse, reason: '异常也要释放，别把卡片钉在不透明面上');
    });

    testWidgets('FeedPage 的 onRefresh：刷新全程暂停卡片玻璃，结束后 premium',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(installFakeApi(json: _feedJson()));

      await tester.pumpWidget(_markApp(GlassQuality.premium, const FeedPage()));
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsWidgets);
      expect(_glass(tester).quality, GlassQuality.premium);

      // 用 RefreshIndicator 真正会调用的那个回调，等于走一遍下拉刷新的刷新段。
      final refresh =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      final future = refresh.onRefresh();
      await tester.pump();

      expect(AppGlassRefreshHold.isActive, isTrue,
          reason: '刷新段一开始就暂停玻璃');
      expect(find.byType(GlassContainer), findsNothing);

      // 刷新回包靠 pump 推进（widget 测试里时间是假的，不能干等 future）。
      for (var i = 0; i < 40 && AppGlassRefreshHold.isActive; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      await future;

      expect(AppGlassRefreshHold.isActive, isFalse);
      expect(_glass(tester).quality, GlassQuality.premium,
          reason: '刷新前后档位不变，仍是 premium');
      expect(tester.takeException(), isNull);
    });
  });

  group('B 玻璃上的小字：对比度 ≥ 4.5', () {
    test('浅色/深色两档，玻璃小字 token 都达标', () {
      expectGlassTextReadable(
        () => AppText.captionOnGlass,
        label: 'AppText.captionOnGlass',
      );
      // 深色一档单独再点一次名：这条断言就是验收里的「深色一条」。
      AppColors.setDark(true);
      expect(
        AppAccent.contrastRatio(
          appGlassCardBackplate(),
          AppText.captionOnGlass.color!,
        ),
        greaterThanOrEqualTo(4.5),
      );
      // 浅色一档同理。
      AppColors.setDark(false);
      expect(
        AppAccent.contrastRatio(
          appGlassCardBackplate(),
          AppText.captionOnGlass.color!,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('回归：原来的 caption（#8A93A6）在浅色玻璃上只有 ~2.8:1', () {
      AppColors.setDark(false);
      final ratio = AppAccent.contrastRatio(
        appGlassCardBackplate(),
        AppText.caption.color!,
      );
      expect(ratio, lessThan(4.5),
          reason: '这就是「浅色主题下小字看不清」的量化原因');
      expect(ratio, lessThan(3.0));
    });

    testWidgets('「新建相册」按钮的文字与图标都用玻璃上的 token', (tester) async {
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

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: CustomAlbumsPage(scope: AlbumScope.family),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final card = find.byKey(newAlbumCardKey);
      expect(card, findsOneWidget);
      final label = tester.widget<Text>(
        find.descendant(of: card, matching: find.text('新建相册')),
      );
      expect(label.style!.color, AppColors.textOnGlass);
      final icon = tester.widget<Icon>(
        find.descendant(of: card, matching: find.byIcon(Icons.add)),
      );
      expect(icon.color, AppColors.textOnGlass);
    });

    testWidgets('「我的」页右侧数值（版本号等）用玻璃上的 token', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // 存储接口失败不影响这一组卡片渲染。
      addTearDown(installFakeApi());

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: ProfilePage(onLogout: () {}),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      for (final title in <String>['检查更新', '页面背景', '服务器状态']) {
        final tile = find.widgetWithText(ListTile, title);
        expect(tile, findsOneWidget, reason: '「$title」这一行要在');
        final texts = tester.widgetList<Text>(
          find.descendant(of: tile, matching: find.byType(Text)),
        );
        final values = texts.where((t) => t.style?.color == AppColors.textOnGlass);
        expect(values, isNotEmpty,
            reason: '「$title」右侧的数值要用玻璃上的深一档 token');
        // 反证：右侧数值不再用 #8A93A6 的 caption。
        expect(
          texts.where((t) => t.style?.color == AppText.caption.color),
          isEmpty,
          reason: '「$title」右侧不该再出现原来的 caption 颜色',
        );
      }
    });
  });
}
