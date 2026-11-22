import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/feed_view_settings.dart';
import 'package:album_app/features/profile/profile_page.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/widgets/app_card.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 直接给现成用户，ProfilePage 就不会去打 AuthApi.me。
    CurrentUser.notifier.value = const AppUser(
      id: 1,
      userId: 'mikey',
      nickname: 'Mikey',
    );
  });

  tearDown(() {
    CurrentUser.notifier.value = null;
  });

  Widget host({GlassQuality? quality}) {
    final app = MaterialApp(
      theme: buildAppTheme(),
      home: ProfilePage(onLogout: () {}),
    );
    return quality == null
        ? app
        : AppGlassScope(quality: quality, child: app);
  }

  Future<void> pumpProfile(WidgetTester tester, {GlassQuality? quality}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 服务器存储接口失败也不影响断言：卡片照样渲染。
    addTearDown(installFakeApi());
    await tester.pumpWidget(host(quality: quality));
    // 存储接口在 initState 里就发出去了：多推几帧，让 dio 的 0 延时定时器
    // 走完、失败回包落到 setState，测试结束时才不会报「Timer is still pending」。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('玻璃档位可用时，每一项卡片都是玻璃底子', (tester) async {
    await pumpProfile(tester, quality: GlassQuality.standard);

    final cards = tester.widgetList<AppCard>(find.byType(AppCard)).toList();
    expect(cards, isNotEmpty);
    for (final card in cards) {
      expect(card.glass, isTrue, reason: '「我的」里的卡片都要玻璃底子');
    }
    // 头像卡 + 服务器存储卡 + 设置组卡：三块玻璃底子。
    expect(find.byType(GlassContainer), findsNWidgets(3));
    expect(find.text('服务器状态'), findsOneWidget);
    expect(find.text('主题色'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('注入 premium：卡片仍然固定在 standard（不抓 capture）', (tester) async {
    await pumpProfile(tester, quality: GlassQuality.premium);

    final containers =
        tester.widgetList<GlassContainer>(find.byType(GlassContainer)).toList();
    expect(containers.length, 3, reason: '头像卡 + 服务器存储卡 + 设置组卡');
    for (final container in containers) {
      // 卡片档位只有一处来源（AppGlassSurface.kCardQuality = standard）：
      // premium 要抓 capture，列表重建那一帧会整块发黑，所以上限给到 premium
      // 也不改变卡片。
      expect(container.quality, GlassQuality.standard);
      expect(container.settings!.thickness, 12);
      expect(container.settings!.blur, appCardFrostBlur,
          reason: '我的页卡片也是白雾磨砂');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimal 档：同样的卡片全部退化成不透明表面', (tester) async {
    await pumpProfile(tester, quality: GlassQuality.minimal);

    expect(find.byType(GlassContainer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    // 分组结构不变，只是底色换成不透明 bgSurface。
    expect(find.text('服务器状态'), findsOneWidget);
    expect(find.text('存储空间'), findsOneWidget);
    expect(tester.widgetList<AppCard>(find.byType(AppCard)), isNotEmpty);
    final decorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((e) => e.decoration)
        .whereType<BoxDecoration>();
    expect(
      decorations.where((d) => d.color == AppColors.bgSurface).length,
      greaterThanOrEqualTo(2),
      reason: '头像卡 + 设置组卡都用 bgSurface',
    );
  });

  testWidgets('朋友圈大屏模式：默认关闭，开关切到打开', (tester) async {
    FeedViewSettings.widescreen.value = false;
    addTearDown(() => FeedViewSettings.widescreen.value = false);
    await pumpProfile(tester);

    final tile = find.byKey(const Key('profile-feed-widescreen'));
    expect(tile, findsOneWidget);
    expect(find.text('朋友圈大屏模式'), findsOneWidget);

    final toggle = find.descendant(of: tile, matching: find.byType(Switch));
    expect(tester.widget<Switch>(toggle).value, isFalse, reason: '默认关闭（九宫格）');

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(FeedViewSettings.widescreen.value, isTrue);
    expect(tester.widget<Switch>(toggle).value, isTrue);

    // 整行也能点：点标题和点开关走同一个开关。
    await tester.tap(find.text('朋友圈大屏模式'));
    await tester.pump();
    expect(FeedViewSettings.widescreen.value, isFalse);
  });
}
