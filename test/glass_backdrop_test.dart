import 'dart:convert';

import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/features/profile/profile_page.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer;
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
    // buildAppTheme 会改 AppColors 的全局明暗标记，别把它留给下一个用例。
    buildAppTheme();
  });

  Widget host(Widget page, {GlassQuality? quality, bool dark = false}) {
    final app = MaterialApp(theme: buildAppTheme(dark: dark), home: page);
    return quality == null
        ? app
        : AppGlassScope(quality: quality, child: app);
  }

  Future<void> pumpPage(WidgetTester tester, Widget page,
      {GlassQuality? quality, bool dark = false}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(page, quality: quality, dark: dark));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  BoxDecoration gradientDecoration(WidgetTester tester) {
    final decorated = tester.widget<DecoratedBox>(
      find.byKey(AppGlassBackdrop.gradientKey),
    );
    return decorated.decoration as BoxDecoration;
  }

  group('页面背景：玻璃背后得有东西可模糊', () {
    testWidgets('朋友圈页最底层是渐变背景，玻璃卡片浮在它上面', (tester) async {
      addTearDown(
        installFakeApi(json: jsonEncode({'items': [], 'next_cursor': null})),
      );
      await pumpPage(tester, const FeedPage(), quality: GlassQuality.standard);

      // 渐变背景层存在，且铺在整页最底层（Scaffold 在它里面）。
      expect(find.byType(AppGlassBackdrop), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppGlassBackdrop),
          matching: find.byType(Scaffold),
        ),
        findsOneWidget,
      );
      final decoration = gradientDecoration(tester);
      final gradient = decoration.gradient! as LinearGradient;
      // 克制的对角线渐变：主题色 0~7%，中间直接透明。
      expect(gradient.begin, Alignment.topLeft);
      expect(gradient.end, Alignment.bottomRight);
      expect(gradient.colors.first.a, closeTo(0.042, 0.002));
      expect(gradient.colors[1].a, 0.0);
      expect(gradient.colors.last.a, closeTo(0.07, 0.002));
      // 两团径向光斑。
      expect(find.byKey(AppGlassBackdrop.blobKey), findsNWidgets(2));
      for (final blob in tester
          .widgetList<DecoratedBox>(find.byKey(AppGlassBackdrop.blobKey))) {
        expect((blob.decoration as BoxDecoration).gradient, isA<RadialGradient>());
      }
      // 底色还是不透明页面色，且背景层不吃模糊（不额外开 BackdropFilter）。
      final base = tester.widget<DecoratedBox>(
        find.byKey(AppGlassBackdrop.baseKey),
      );
      expect((base.decoration as BoxDecoration).color, AppColors.bgPage);
      expect(
        find.descendant(
          of: find.byType(AppGlassBackdrop),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
    });

    testWidgets('minimal 档：背景照样在，只是卡片退化成不透明', (tester) async {
      addTearDown(
        installFakeApi(json: jsonEncode({'items': [], 'next_cursor': null})),
      );
      await pumpPage(tester, const FeedPage(), quality: GlassQuality.minimal);

      expect(find.byKey(AppGlassBackdrop.gradientKey), findsOneWidget);
      expect(find.byKey(AppGlassBackdrop.blobKey), findsNWidgets(2));
      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('「我的」页最底层也是渐变背景', (tester) async {
      addTearDown(installFakeApi());
      await pumpPage(tester, ProfilePage(onLogout: () {}),
          quality: GlassQuality.standard);

      expect(find.byType(AppGlassBackdrop), findsOneWidget);
      final gradient = gradientDecoration(tester).gradient! as LinearGradient;
      expect(gradient.colors.last.a, greaterThan(0));
      expect(find.byKey(AppGlassBackdrop.blobKey), findsNWidgets(2));
      // 卡片玻璃在背景之上：这页的玻璃底子照旧。
      expect(find.byType(GlassContainer), findsWidgets);
    });

    testWidgets('「我的」页 minimal 档：背景仍在，玻璃一个都不画', (tester) async {
      addTearDown(installFakeApi());
      await pumpPage(tester, ProfilePage(onLogout: () {}),
          quality: GlassQuality.minimal);

      expect(find.byKey(AppGlassBackdrop.gradientKey), findsOneWidget);
      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('深色模式用压暗的近似色，不拿亮主色照亮夜间页面', (tester) async {
      addTearDown(installFakeApi());
      await pumpPage(tester, ProfilePage(onLogout: () {}),
          quality: GlassQuality.standard, dark: true);

      final gradient = gradientDecoration(tester).gradient! as LinearGradient;
      final expected = Color.lerp(AppColors.primary, AppColors.bgPage, 0.55)!
          .withValues(alpha: 0.18);
      expect(gradient.colors.last, expected);
      final base = tester.widget<DecoratedBox>(
        find.byKey(AppGlassBackdrop.baseKey),
      );
      expect((base.decoration as BoxDecoration).color, AppColors.bgPage);
    });
  });
}
