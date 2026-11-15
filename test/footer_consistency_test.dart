import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_tab_page.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/features/home/home_page.dart';
import 'package:album_app/features/profile/profile_page.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

// 底部 footer 三个页面必须「一模一样」：同一个组件、同一组参数、同一套 scrim
// 与玻璃档位，多选态用同一种处理（隐藏）。这里守的是结构——footer 只在
// HomePage 里渲染一次，三个页面自己一行 footer 代码都没有；参数只有
// AppBottomTabBar.preferredQuality / usesOwnLayer 两个常量做来源。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(WidgetTester tester) async {
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
      MaterialApp(theme: buildAppTheme(), home: HomePage(onLogout: () {})),
    );
    // 三个页面都在 IndexedStack 里加载（只有一页可见），给它们几帧。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder barSurface() => find.descendant(
        of: find.byType(AppBottomTabBar),
        matching: find.byType(AppGlassSurface),
      );

  testWidgets('三页共用同一块 footer：全树只有一个 AppBottomTabBar', (tester) async {
    await pumpHome(tester);

    // IndexedStack 里只有当前页是 onstage：另外两页要显式 skipOffstage: false。
    expect(find.byType(FeedPage), findsOneWidget);
    expect(find.byType(AlbumTabPage, skipOffstage: false), findsOneWidget);
    expect(find.byType(ProfilePage, skipOffstage: false), findsOneWidget);
    expect(find.byType(AppBottomTabBar), findsOneWidget,
        reason: 'footer 是 HomePage 的一份 chrome，不是每个页面各画一条');

    for (final page in <Type>[FeedPage, AlbumTabPage, ProfilePage]) {
      expect(
        find.descendant(
          of: find.byType(page, skipOffstage: false),
          matching: find.byType(AppBottomTabBar, skipOffstage: false),
          skipOffstage: false,
        ),
        findsNothing,
        reason: '$page 自己不许再画 footer（否则参数迟早会分叉）',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一个组件、同一组参数：档位 / scrim / 圆角只有一个来源', (tester) async {
    await pumpHome(tester);

    // 参数来源：底部胶囊的常量就是「三页共用的那一份」。
    expect(AppBottomTabBar.preferredQuality, GlassQuality.premium);
    expect(AppBottomTabBar.usesOwnLayer, isTrue);

    final surfaceFinder = barSurface();
    expect(surfaceFinder, findsOneWidget);
    final surface = tester.widget<AppGlassSurface>(surfaceFinder);
    expect(surface.preferPremium, isTrue, reason: '三页的胶囊都优先 premium');
    expect(surface.requestedQuality, AppBottomTabBar.preferredQuality,
        reason: '档位不许两页两样');
    expect(surface.useOwnLayer, AppBottomTabBar.usesOwnLayer,
        reason: '自建层的开关也不许分叉');
    expect(surface.scrim, isTrue, reason: '三页都叠同一层 scrim');
    expect(surface.radius, AppBottomTabBar.barHeight / 2);

    // 切到另外两页：还是同一块 footer、同一组参数（切页不重建参数）。
    for (final index in <int>[1, 2, 0]) {
      await tester.tap(find.byKey(AppBottomTabBar.tabKey(index)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(AppBottomTabBar), findsOneWidget);
      final again = tester.widget<AppGlassSurface>(barSurface());
      expect(again.preferPremium, surface.preferPremium);
      expect(again.requestedQuality, surface.requestedQuality);
      expect(again.useOwnLayer, surface.useOwnLayer);
      expect(again.scrim, surface.scrim);
    }
  });

  testWidgets('多选态统一策略：隐藏——三页都不留胶囊、也不变形成选择栏', (tester) async {
    await pumpHome(tester);

    // 相册页进入多选态：它回报给 HomePage，footer 整条收起。
    final album = tester.widget<AlbumTabPage>(
      find.byType(AlbumTabPage, skipOffstage: false),
    );
    album.onEditingChanged!(true);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AppBottomTabBar), findsNothing,
        reason: '多选态统一是「隐藏」，三页同一个标志位');
    // 隐藏的是整条胶囊：不会留下半条、也不是变形出来的选择栏。
    expect(barSurface(), findsNothing);

    album.onEditingChanged!(false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(AppBottomTabBar), findsOneWidget,
        reason: '退出多选态后原样回来，参数不变');
    final back = tester.widget<AppGlassSurface>(barSurface());
    expect(back.preferPremium, isTrue);
    expect(back.requestedQuality, AppBottomTabBar.preferredQuality);
  });
}