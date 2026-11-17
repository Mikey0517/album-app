import 'package:album_app/core/app_accent_controller.dart';
import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/profile/theme_accent_picker_page.dart';
import 'package:album_app/features/profile/theme_accent_sheet.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_glass_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppAccentController.seed.value = AppAccent.brand;
    AppColors.setDark(false);
  });

  group('主题色可配置', () {
    test('切换预设色后 AppColors.primary 跟着变，并写入持久化', () async {
      expect(AppColors.primary, AppAccent.brand, reason: '默认沿用品牌色');

      const preset = Color(0xFF2FA84F);
      await AppAccentController.setSeed(preset);

      expect(AppColors.primary, preset);
      // 按钮、链接、进度条等走 ColorScheme 的地方也一起换。
      expect(buildAppTheme().colorScheme.primary, preset);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('app_accent_color'), preset.toARGB32());
    });

    test('冷启动从 SharedPreferences 恢复上次选的颜色', () async {
      SharedPreferences.setMockInitialValues({'app_accent_color': 0xFFFF7A45});
      AppAccentController.seed.value = AppAccent.brand;

      await AppAccentController.init();

      expect(AppAccentController.seed.value, const Color(0xFFFF7A45));
      expect(AppColors.primary, const Color(0xFFFF7A45));
    });

    test('持久化内容读不出来时退回品牌默认色', () async {
      SharedPreferences.setMockInitialValues({'app_accent_color': 'broken'});
      AppAccentController.seed.value = const Color(0xFF2FA84F);

      await AppAccentController.init();

      expect(AppAccentController.seed.value, AppAccent.brand);
      expect(AppColors.primary, AppAccent.brand);
    });

    test('自定义 HSV 越界值被 clamp 到合法区间', () {
      expect(
        AppAccent.fromHsv(hue: 420, saturation: 2.5, value: 1.8),
        AppAccent.fromHsv(hue: 360, saturation: 1, value: 1),
      );
      expect(
        AppAccent.fromHsv(hue: -30, saturation: -1, value: -0.4),
        const Color(0xFF000000),
        reason: '负值全部夹到 0',
      );
      expect(
        AppAccent.fromHsv(
          hue: double.nan,
          saturation: double.nan,
          value: double.nan,
        ),
        const Color(0xFF000000),
        reason: 'NaN 不能炸掉取色器',
      );
    });

    test('落盘颜色去掉 alpha，半透明自定义色不会穿透背景', () async {
      await AppAccentController.setSeed(const Color(0x80123456));

      expect(AppAccentController.seed.value, const Color(0xFF123456));
      expect(AppColors.primary, const Color(0xFF123456));
    });

    test('深色模式把主色提亮到深色背景可读', () {
      AppColors.setDark(false);
      final lightPrimary = AppColors.primary;
      AppColors.setDark(true);
      final darkPrimary = AppColors.primary;

      expect(
        AppAccent.relativeLuminance(darkPrimary),
        greaterThan(AppAccent.relativeLuminance(lightPrimary)),
      );
      expect(
        AppAccent.contrastRatio(AppColors.bgPage, AppColors.primary),
        greaterThanOrEqualTo(4.5),
        reason: '深色页面底色上主色要能当文字/图标色',
      );
    });

    test('深色模式对自定义色同样做亮度调整', () {
      const seed = Color(0xFF7C5CFF);
      const darkPage = Color(0xFF0E1118);
      final darkPrimary =
          AppAccent.primary(seed, isDark: true, pageBg: darkPage);

      expect(AppAccent.relativeLuminance(darkPrimary),
          greaterThan(AppAccent.relativeLuminance(seed)));
      expect(AppAccent.contrastRatio(darkPage, darkPrimary),
          greaterThanOrEqualTo(4.5));
      expect(AppAccent.primary(seed, isDark: false, pageBg: Colors.white),
          seed,
          reason: '浅色模式尊重用户选的颜色');
    });
  });

  group('底部 tab', () {
    Future<void> pumpBar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: AppBottomTabBar(
              selectedIndex: 0,
              onSelected: (_) {},
              items: const [
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
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('等宽三格、胶囊 56 高、无涟漪，退化后仍是细边胶囊', (tester) async {
      await pumpBar(tester);

      // 整条栏 = 胶囊 56 + 离底边距 8（这个 host 没有底部安全区）。
      final bar = tester.getSize(find.byType(AppBottomTabBar));
      expect(bar.height, AppBottomTabBar.barHeight + AppBottomTabBar.bottomGap);
      expect(AppBottomTabBar.barHeight, 56);
      expect(find.byType(NavigationBar), findsNothing);

      // 三格等宽，但没有 InkWell：点下去不该有水波纹。
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(InkResponse), findsNothing);
      final cells = find.byType(GestureDetector);
      expect(cells, findsNWidgets(3));
      final pillWidth =
          bar.width - AppBottomTabBar.sideInset * 2;
      final widths = [
        for (final element in cells.evaluate())
          tester.getSize(find.byWidget(element.widget)).width,
      ];
      expect(widths, [pillWidth / 3, pillWidth / 3, pillWidth / 3]);

      // 这个 host 没有玻璃档位 → 退化分支：不透明底 + 一圈 1px 细边。
      final decorated = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AppBottomTabBar),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = decorated.decoration as BoxDecoration;
      expect(decoration.color, AppColors.bgSurface);
      expect(decoration.borderRadius,
          BorderRadius.circular(AppBottomTabBar.radius));
      final border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, AppColors.divider);
    });

    testWidgets('选中项图标与文字都用主色，未选中用中性灰', (tester) async {
      await pumpBar(tester);

      expect(tester.widget<Icon>(find.byIcon(Icons.people)).color,
          AppColors.primary);
      final selectedText = tester.widget<Text>(find.text('朋友圈'));
      expect(selectedText.style!.color, AppColors.primary);

      final idleIcon =
          tester.widget<Icon>(find.byIcon(Icons.photo_library_outlined));
      // 未选中不再是固定中性灰：墨色按背景合成亮度自动选（方案 C，见
      // app_glass_tone.dart）。没有背景采样时按主题回退（浅色 → 深墨）。
      expect(idleIcon.color, appGlassToneInk());
      expect(idleIcon.color, appGlassToneInkForBackdrop(null));
      expect(idleIcon.color, isNot(AppColors.primary));
      final idleText = tester.widget<Text>(find.text('相册'));
      expect(idleText.style!.color, isNot(AppColors.primary));
      expect(idleText.style!.color, appGlassToneInk());

      expect(selectedText.style!.fontSize, inInclusiveRange(10, 11));
      expect(idleText.style!.fontSize, inInclusiveRange(10, 11));
      // 选中用实心图标，未选中用线框，同一个 icon 的两个变体。
      expect(find.byIcon(Icons.people_outline), findsNothing);
      expect(find.byIcon(Icons.photo_library), findsNothing);
    });

    testWidgets('换主题色后选中态颜色立刻跟着变', (tester) async {
      await pumpBar(tester);
      const preset = Color(0xFF7C5CFF);

      await AppAccentController.setSeed(preset);
      await pumpBar(tester);

      expect(AppColors.primary, preset);
      expect(
          tester.widget<Icon>(find.byIcon(Icons.people)).color, AppColors.primary);
      expect(tester.widget<Text>(find.text('朋友圈')).style!.color,
          AppColors.primary);
    });
  });

  group('设置入口', () {
    testWidgets('主题色面板点预设立即生效并落盘', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showThemeAccentSheet(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('主题色'), findsOneWidget);
      expect(find.text('自定义'), findsOneWidget);

      await tester.tap(find.byTooltip('暖橙'));
      await tester.pumpAndSettle();

      expect(AppColors.primary, const Color(0xFFFF7A45));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('app_accent_color'), 0xFFFF7A45);
      expect(find.text('主题色'), findsNothing, reason: '选完就关掉面板');
    });

    testWidgets('自定义取色器用三条 Slider，保存后写回主题色', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ThemeAccentPickerPage(),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNWidgets(3));
      expect(find.text('色相'), findsOneWidget);
      expect(find.text('饱和度'), findsOneWidget);
      expect(find.text('明度'), findsOneWidget);

      // 拖色相滑块，颜色必须随之变化。
      await tester.drag(find.byType(Slider).first, const Offset(90, 0));
      await tester.pump();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(AppAccentController.seed.value, isNot(AppAccent.brand));
      expect(AppColors.primary, isNot(AppAccent.brand));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('app_accent_color'),
        AppAccentController.seed.value.toARGB32(),
      );
      expect(AppColors.primary.toARGB32() & 0xFF000000, 0xFF000000);
    });
  });
}
