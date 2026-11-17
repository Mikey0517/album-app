import 'dart:convert';

import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/album_view_settings.dart';
import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/album/album_media_filter_bar.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_chrome_glass_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_glass_tone.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:album_app/widgets/date_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LiquidGlassSettings;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

// **三处吸顶悬浮条 = 底部 footer 的同一块玻璃**：朋友圈吸顶日期条、
// 相册吸顶分类条、相册吸顶日期条都走 [AppChromeGlassBar]，参数只在那里写一次。
//
// 这份文件守四件事：
// 1. 三处与 footer 的光学参数**逐项相等**（scrim / scrimAlpha / thickness /
//    chroma / blur / refractiveIndex / saturation / 档位 / 自建层），不是「看着
//    差不多」；
// 2. 圆角按各自形态取：footer 与分类条是胶囊（高度/2），日期条是满宽条带（0）；
// 3. 三处的文字是 footer **未激活**那一套：appGlassToneInk() 的自动墨色、
//    字号 / 行高 / 字重与 footer 标签完全相同（分类条的选中段仍是主题色）；
// 4. 自动墨色在四种极端背景 × 明暗下都 ≥ 4.5:1（WCAG AA）。
//
// 刷新全程不换材质（同一 Element + 最暗像素 > 0.5）钉在
// test/refresh_black_bar_test.dart 里。

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

/// 三处吸顶条都是静态 chrome：测试里注入 premium 档，量到的就是真机上那一套
/// 参数（不注入时 AppGlassSurface 会退化，参数取不到 chrome 那份）。
///
/// [dark] 走 [buildAppTheme]（它自己会调 AppColors.setDark，所以不能先 setDark
/// 再建主题——那样会被这一句重置回浅色）。
Widget _host(Widget home, {bool dark = false}) => AppGlassScope(
      quality: GlassQuality.premium,
      child: MaterialApp(theme: buildAppTheme(dark: dark), home: home),
    );

Widget _footerPage() => _host(
      Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: AppBottomTabBar(
          selectedIndex: 0,
          onSelected: (_) {},
          items: _tabs,
        ),
      ),
    );

Widget _albumPage({bool dark = false}) {
  final items = <Media>[
    for (var day = 1; day <= 3; day++)
      for (var i = 0; i < 8; i++)
        Media(
          id: day * 100 + i,
          type: 'image',
          thumbUrl: null,
          url: '',
          width: 1920,
          height: 1080,
          durationMs: null,
          takenAt: DateTime(2024, 11, day, 9, i),
          createdAt: DateTime(2024, 11, day, 9, i),
          postId: null,
        ),
  ];
  final album = Album(
    id: 7,
    title: '秋天到冬天',
    coverThumb: null,
    mediaCount: items.length,
    createdAt: DateTime(2020, 5, 1),
  );
  return _host(
    AlbumDetailPage(
      album: album,
      loader: (id) async => AlbumDetail(album: album, items: items),
    ),
    dark: dark,
  );
}

Widget _feedPage() => _host(const FeedPage());

String _feedJson() => jsonEncode({
      'items': [
        for (var i = 0; i < 6; i++)
          {
            'id': i + 1,
            'author_id': 1,
            'author_nickname': '妈妈',
            'content': '第 $i 条动态',
            'posted_at':
                '2026-01-${(i + 1).toString().padLeft(2, '0')}T10:00:00Z',
            'medias': <dynamic>[],
          },
      ],
      'next_cursor': null,
    });

/// 一条玻璃条量到的参数：**只比这些**，没有别的来源。
class _Chrome {
  _Chrome(this.name, this.surface);

  final String name;
  final AppGlassSurface surface;

  LiquidGlassSettings get settings => surface.settings!;

  bool get preferPremium => surface.preferPremium;
  bool get scrim => surface.scrim;
  bool get useOwnLayer => surface.useOwnLayer;
  GlassQuality? get quality => surface.requestedQuality;
  double get radius => surface.radius;
  double get scrimAlpha => surface.scrimColor!.a;
  double get thickness => settings.thickness;
  double get blur => settings.blur;
  double get chroma => settings.chromaticAberration;
  double get refractiveIndex => settings.refractiveIndex;
  double get saturation => settings.saturation;
}

_Chrome _chromeOf(WidgetTester tester, Finder bar, String name) {
  final surface = tester.widget<AppGlassSurface>(
    find.descendant(of: bar, matching: find.byType(AppGlassSurface)),
  );
  return _Chrome(name, surface);
}

Finder _footerBar() => find.descendant(
      of: find.byType(AppBottomTabBar),
      matching: find.byType(AppChromeGlassBar),
    );

Finder _filterBar() => find.descendant(
      of: find.byType(AlbumMediaFilterSliver),
      matching: find.byType(AppChromeGlassBar),
    );

/// 吸顶日期条那一块玻璃（内容流里的日期头是透明条，没有玻璃）。
Finder _pinnedDateBar() => find.descendant(
      of: find.byType(DateHeader),
      matching: find.byType(AppChromeGlassBar),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 把相册页滚到日期头吸住的位置：那一刻两条吸顶条都在屏上。
Future<void> _scrollAlbum(WidgetTester tester) async {
  final position =
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  position.jumpTo(260);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AlbumViewSettings.group.value = AlbumGroup.day;
    AppColors.setDark(false);
    AppBackdropSample.reset();
  });
  tearDown(() {
    AlbumViewSettings.group.value = AlbumGroup.day;
    PageBackdropController.spec.value = const PageBackdropSpec.defaultGradient();
    AppColors.setDark(false);
    AppBackdropSample.reset();
  });

  testWidgets('三处吸顶条与 footer 的光学参数逐项相等', (tester) async {
    _phone(tester);

    await tester.pumpWidget(_footerPage());
    await tester.pump(const Duration(milliseconds: 50));
    final footer = _chromeOf(tester, _footerBar(), 'footer');

    await tester.pumpWidget(_albumPage());
    await tester.pumpAndSettle();
    await _scrollAlbum(tester);
    final filter = _chromeOf(tester, _filterBar(), '相册吸顶分类条');
    final albumDate = _chromeOf(tester, _pinnedDateBar(), '相册吸顶日期条');

    addTearDown(installFakeApi(json: _feedJson()));
    await tester.pumpWidget(_feedPage());
    await tester.pumpAndSettle();
    final feedDate = _chromeOf(tester, _pinnedDateBar(), '朋友圈吸顶日期条');

    final sites = <_Chrome>[filter, albumDate, feedDate];

    // 1. 开关与 scrim：三处 = footer，逐项。
    for (final site in sites) {
      expect(site.preferPremium, footer.preferPremium,
          reason: '${site.name} 的 preferPremium 与 footer 不一致');
      expect(site.scrim, footer.scrim, reason: '${site.name} 的 scrim 与 footer 不一致');
      expect(site.useOwnLayer, footer.useOwnLayer,
          reason: '${site.name} 的自建层开关与 footer 不一致');
      expect(site.quality, footer.quality,
          reason: '${site.name} 的玻璃档位与 footer 不一致');
      expect(site.scrimAlpha, closeTo(footer.scrimAlpha, 1e-9),
          reason: '${site.name} 的 scrim 不透明度与 footer 不一致');
    }

    // 2. 光学参数：三处 = footer，一项一项比（不是「大致同一档」）。
    for (final site in sites) {
      expect(site.thickness, footer.thickness,
          reason: '${site.name} 的斜面厚度与 footer 不一致');
      expect(site.chroma, footer.chroma,
          reason: '${site.name} 的色散与 footer 不一致');
      expect(site.blur, footer.blur,
          reason: '${site.name} 的模糊半径与 footer 不一致');
      expect(site.refractiveIndex, footer.refractiveIndex,
          reason: '${site.name} 的折射率与 footer 不一致');
      expect(site.saturation, footer.saturation,
          reason: '${site.name} 的饱和度与 footer 不一致');
    }

    // 3. 而且就是 chrome 那一组常量（参数只有一份来源）。
    expect(footer.thickness, appGlassChromeThickness);
    expect(footer.thickness, 32);
    expect(footer.chroma, appGlassChromeChromaticAberration);
    expect(footer.chroma, 0.14);
    expect(footer.blur, appGlassChromeBlur);
    expect(footer.blur, 2);
    expect(footer.refractiveIndex, appGlassChromeRefractiveIndex);
    expect(footer.refractiveIndex, 1.38);
    expect(footer.saturation, appGlassChromeSaturation);
    expect(footer.saturation, 1.3);
    // scrim 0.55 = 折射可见度 45%。
    expect(footer.scrimAlpha, closeTo(0.55, 1e-9));
    expect(footer.scrimAlpha, closeTo(appGlassChromeScrimAlpha(), 1e-9));
    expect(appGlassChromeRefractionVisibility(), closeTo(0.45, 1e-9));

    // 4. 圆角按各自形态取：胶囊 / 条带。
    expect(footer.radius, AppBottomTabBar.radius);
    expect(footer.radius, AppBottomTabBar.barHeight / 2, reason: 'footer 是胶囊');
    expect(filter.radius, kAppSegmentedBarPillRadius, reason: '分类条也是胶囊');
    expect(albumDate.radius, kPinnedDateHeaderRadius);
    expect(feedDate.radius, kPinnedDateHeaderRadius);
    expect(kPinnedDateHeaderRadius, 0, reason: '日期条是满宽条带，四角不留圆弧');
    expect(tester.takeException(), isNull);
  });

  testWidgets('三处的未选中文字：自动墨色 + 与 footer 标签同一字号/字重',
      (tester) async {
    _phone(tester);
    // 背景换成「纯白照片」：自动墨色应该选深墨，三处跟着一起变。
    PageBackdropController.spec.value =
        const PageBackdropSpec.solid(Color(0xFFFFFFFF));

    await tester.pumpWidget(_footerPage());
    await tester.pump(const Duration(milliseconds: 50));
    // footer 的未选中标签就是这把尺子。
    final footerLabel = tester
        .widget<Text>(find.descendant(
          of: find.byType(AppBottomTabBar),
          matching: find.text('相册'),
        ))
        .style!;
    expect(footerLabel.fontSize, 10.5);
    expect(footerLabel.fontWeight, FontWeight.w500);
    expect(footerLabel.color, appGlassToneInk(),
        reason: 'footer 未选中标签用的是自动墨色');

    await tester.pumpWidget(_albumPage());
    await tester.pumpAndSettle();
    final albumInk = appGlassToneInk();
    expect(albumInk, footerLabel.color, reason: '同一份采样，墨色应该是同一个');

    // 相册吸顶分类条：未选中段 + 数量。
    final unselected = tester
        .widget<Text>(find.descendant(
          of: find.byKey(AppSegmentedBar.segmentKey(1)),
          matching: find.text('照片'),
        ))
        .style!;
    expect(unselected.color, albumInk,
        reason: '分类条未选中段没有用自动墨色');
    expect(unselected.color, isNot(appTabBarInactiveColor));
    expect(unselected.fontSize, footerLabel.fontSize);
    expect(unselected.fontWeight, footerLabel.fontWeight);
    expect(unselected.height, footerLabel.height);
    final countTexts = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(AppSegmentedBar.segmentKey(1)),
          matching: find.byType(Text),
        ))
        .toList();
    expect(countTexts, hasLength(2), reason: '未选中段应该是「文案 + 数量」两段文字');
    expect(countTexts[1].style!.color, albumInk,
        reason: '数量也要跟着 footer 未激活那一套走');
    expect(countTexts[1].style!.fontSize, footerLabel.fontSize);
    expect(countTexts[1].style!.fontWeight, footerLabel.fontWeight);
    // 选中段仍用主题色（本条内局部加深），字号/字重与 footer 同一档。
    final selected = tester
        .widget<Text>(find.descendant(
          of: find.byKey(AppSegmentedBar.segmentKey(0)),
          matching: find.text('全部'),
        ))
        .style!;
    expect(selected.color, segmentedSelectedInk);
    expect(selected.fontSize, footerLabel.fontSize);
    expect(selected.fontWeight, footerLabel.fontWeight);

    // 相册吸顶日期条：日期文字 + 那一组的张数。
    await _scrollAlbum(tester);
    final pinnedHeader = find.byType(DateHeader).evaluate().firstWhere(
          (element) => find
              .descendant(
                of: find.byElementPredicate((e) => e == element),
                matching: find.byType(AppChromeGlassBar),
              )
              .evaluate()
              .isNotEmpty,
        );
    final dateTexts = tester
        .widgetList<Text>(find.descendant(
          of: find.byElementPredicate((e) => e == pinnedHeader),
          matching: find.byType(Text),
        ))
        .toList();
    expect(dateTexts, isNotEmpty, reason: '吸顶日期条里得有文字');
    for (final text in dateTexts) {
      expect(text.style!.color, appGlassToneInk(),
          reason: '吸顶日期条的文字没有用自动墨色：「${text.data}」');
      expect(text.style!.fontSize, footerLabel.fontSize);
      expect(text.style!.fontWeight, footerLabel.fontWeight);
      expect(text.style!.height, footerLabel.height);
    }
    expect(dateTexts.length, 2, reason: '日期 + 张数两段文字');

    // 朋友圈吸顶日期条。
    addTearDown(installFakeApi(json: _feedJson()));
    await tester.pumpWidget(_feedPage());
    await tester.pumpAndSettle();
    final feedText = tester
        .widget<Text>(find.descendant(
          of: find.byType(DateHeader),
          matching: find.byType(Text),
        ));
    expect(feedText.style!.color, appGlassToneInk(),
        reason: '朋友圈吸顶日期条没有用自动墨色');
    expect(feedText.style!.fontSize, footerLabel.fontSize);
    expect(feedText.style!.fontWeight, footerLabel.fontWeight);
    expect(feedText.style!.height, footerLabel.height);
  });

  testWidgets('自动墨色：背景换了，吸顶条的文字跟着换（不是写死的颜色）',
      (tester) async {
    _phone(tester);
    // 深色主题：scrim 叠出来的底衬亮度刚好横跨阈值（0.179），墨色会真的翻档
    // ——浅色主题下 0.55 的页面底色把底衬钉在阈值以上，怎么换背景都是深墨。
    expect(AppColors.isDark, isFalse);

    PageBackdropController.spec.value =
        const PageBackdropSpec.solid(Color(0xFFFFFFFF));
    await tester.pumpWidget(_albumPage(dark: true));
    expect(AppColors.isDark, isTrue, reason: '深色主题要真的生效');
    await tester.pumpAndSettle();
    await _scrollAlbum(tester);
    final onWhite = tester.widget<Text>(find.text('照片')).style!.color;
    expect(onWhite, appGlassToneInk());
    expect(onWhite, appGlassToneInkForBackdrop(const Color(0xFFFFFFFF)));
    expect(onWhite, appGlassToneInkDark,
        reason: '深色主题 + 纯白照片：合成底衬偏亮，该用深墨');

    // 换成纯黑背景：墨色翻到另一套。
    PageBackdropController.spec.value =
        const PageBackdropSpec.solid(Color(0xFF000000));
    await tester.pump();
    await tester.pump();
    final onBlack = tester.widget<Text>(find.text('照片')).style!.color;
    expect(onBlack, appGlassToneInk());
    expect(onBlack, appGlassToneInkForBackdrop(const Color(0xFF000000)));
    expect(onBlack, appGlassToneInkLight);
    expect(onBlack, isNot(onWhite),
        reason: '背景从纯白换到纯黑，墨色却没变：这不是自动墨色');
    AppColors.setDark(false);
  });

  test('自动墨色在极端背景上 ≥ 4.5:1（浅/深各一条）', () {
    const extremes = <Color>[
      Color(0xFFFFFFFF),
      Color(0xFF000000),
      Color(0xFFFF0000),
      Color(0xFF0000FF),
    ];
    final measured = <bool, Map<Color, double>>{};
    for (final dark in <bool>[false, true]) {
      AppColors.setDark(dark);
      measured[dark] = <Color, double>{};
      for (final backdrop in extremes) {
        // 吸顶条：底衬 = scrim 叠背景（appGlassToneInk 那一套）。
        final ink = appGlassToneInkForBackdrop(backdrop);
        final backplate = appGlassToneBackplate(backdrop);
        final ratio = AppAccent.contrastRatio(backplate, ink);
        measured[dark]![backdrop] = ratio;
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '吸顶条文字（dark=$dark，背景 $backdrop）只有 '
              '${ratio.toStringAsFixed(2)}:1：低于 WCAG AA 4.5',
        );
        // 透明日期条：底衬就是背景本身（appGlassToneInkBare 那一套）。
        final bareInk = appGlassToneInkBare(backdrop);
        final bareRatio = AppAccent.contrastRatio(backdrop, bareInk);
        expect(
          bareRatio,
          greaterThanOrEqualTo(4.5),
          reason: '透明日期条文字（dark=$dark，背景 $backdrop）只有 '
              '${bareRatio.toStringAsFixed(2)}:1：低于 WCAG AA 4.5',
        );
      }
    }
    // 实测值钉住：两套墨色的最坏格（浅色/深色各一条）。
    final lightWorst = measured[false]!.values.reduce((a, b) => a < b ? a : b);
    final darkWorst = measured[true]!.values.reduce((a, b) => a < b ? a : b);
    expect(lightWorst, greaterThanOrEqualTo(4.5));
    expect(darkWorst, greaterThanOrEqualTo(4.5));
    AppColors.setDark(false);
  });
}
