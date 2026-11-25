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

// **三处吸顶悬浮条 = 底部 footer 的同一块玻璃，只差折射那一档**：朋友圈吸顶
// 日期条、相册吸顶分类条、相册吸顶日期条都走 [AppChromeGlassBar]，参数只在那里
// 写一次。
//
// 这份文件守四件事：
// 1. 三处与 footer 共用的那几项**逐项相等**（scrim / scrimAlpha / blur /
//    saturation / tint / 档位 / 自建层 / 光照），折射三数**逐项不同**：
//    吸顶条 44 / 1.75 / 0.32，footer 36 / 1.55 / 0.22；
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
  bool get showBorder => surface.showBorder;
  bool get showHighlight => surface.showHighlight;
  Color? get backplate => surface.backplate;
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
  double get lightIntensity => settings.lightIntensity;
  double get edgeAbsorption => settings.edgeAbsorption;
  double get rimShade => settings.rimShade;
  double get tintAlpha => settings.glassColor.a;
}

_Chrome _chromeOf(WidgetTester tester, Finder bar, String name) {
  final surface = tester.widget<AppGlassSurface>(
    find.descendant(of: bar, matching: find.byType(AppGlassSurface)),
  );
  return _Chrome(name, surface);
}

/// 条带里某一层装饰出现了几次（0 = 没画）。
int _layerCount(WidgetTester tester, Finder bar, Key key) =>
    find.descendant(of: bar, matching: find.byKey(key)).evaluate().length;

/// footer 的事：胶囊 + 1px 描边 + 顶部内高光，没有固定底衬。
void _expectFooterDecoration(WidgetTester tester, Finder bar) {
  expect(_layerCount(tester, bar, AppGlassSurface.strokeKey), 1,
      reason: 'footer 的 1px 描边没了');
  expect(_layerCount(tester, bar, AppGlassSurface.highlightKey), 1,
      reason: 'footer 的顶部内高光没了');
  expect(_layerCount(tester, bar, AppGlassSurface.backplateKey), 0,
      reason: 'footer 多了一层底衬：它背后是页面底图，不需要压色');
  // footer 仍是浮在底部的胶囊：左右各留 sideInset，离底只剩 bottomGap。
  final rect = tester.getRect(bar);
  expect(rect.left, AppBottomTabBar.sideInset);
  expect(tester.view.physicalSize.width - rect.right, AppBottomTabBar.sideInset);
  expect(tester.view.physicalSize.height - rect.bottom,
      AppBottomTabBar.bottomGap);
}

/// 三处吸顶条的事：**没有**描边、**没有**内高光、只有一层固定底衬，
/// 而且几何上贴住页面左右边缘（不留侧边空隙）。
void _expectPinnedDecoration(WidgetTester tester, Finder bar, String name) {
  expect(_layerCount(tester, bar, AppGlassSurface.strokeKey), 0,
      reason: '$name还有 1px 描边：直边条上下各一条线，会把玻璃和页面切开');
  expect(_layerCount(tester, bar, AppGlassSurface.highlightKey), 0,
      reason: '$name还有顶部内高光：直边条上不该再压一道白色横杠');
  expect(_layerCount(tester, bar, AppGlassSurface.backplateKey), 1,
      reason: '$name少了固定底衬：背后内容一动，条带就会变色');
  // 底衬 = 页面底色 + 固定不透明度，铺满整条（连圆角外也不留缝）。
  final backplate = tester.widget<DecoratedBox>(
    find.descendant(of: bar, matching: find.byKey(AppGlassSurface.backplateKey)),
  ).decoration as BoxDecoration;
  expect(backplate.color!.a, closeTo(kAppChromePinnedBackplateAlpha, 1e-9));
  expect(backplate.color, AppColors.bgPage.withValues(alpha: kAppChromePinnedBackplateAlpha));
  expect(tester.getRect(find.descendant(
    of: bar,
    matching: find.byKey(AppGlassSurface.backplateKey),
  )), tester.getRect(bar), reason: '$name的底衬没有铺满外框');
  // 贴边：吸顶条与屏幕左右边缘对齐，没有侧边空隙。
  final rect = tester.getRect(bar);
  expect(rect.left, 0, reason: '$name左边留了空隙');
  expect(rect.width, tester.view.physicalSize.width,
      reason: '$name没有横贯整屏（右侧留了空隙）');
}

Finder _footerBar() => find.descendant(
      of: find.byType(AppBottomTabBar),
      matching: find.byType(AppChromeGlassBar),
    );

/// 相册吸顶区那一整块玻璃：**一块**同时装分类行与日期行（不是两条各自
/// 带玻璃的吸顶条，那会在两行之间留一条接缝）。
Finder _albumChromeBar() => find.descendant(
      of: find.byType(AlbumPinnedChromeSliver),
      matching: find.byType(AppChromeGlassBar),
    );

/// 相册吸顶区里那一行日期（玻璃在它的**祖先**里）。
Finder _albumDateRow() => find.descendant(
      of: find.byType(AlbumPinnedChromeSliver),
      matching: find.byType(DateHeader),
    );

/// 朋友圈吸顶日期条那一块玻璃（单行，日期头自己带玻璃；内容流里的日期头是
/// 透明条，没有玻璃）。
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

  testWidgets('三处吸顶条与 footer：共用项逐项相等，折射三数吸顶条更高一档',
      (tester) async {
    _phone(tester);

    await tester.pumpWidget(_footerPage());
    await tester.pump(const Duration(milliseconds: 50));
    final footer = _chromeOf(tester, _footerBar(), 'footer');
    // footer 的形状与装饰：胶囊 + 描边 + 内高光（三处吸顶条不许有这两层）。
    _expectFooterDecoration(tester, _footerBar());

    await tester.pumpWidget(_albumPage());
    await tester.pumpAndSettle();
    await _scrollAlbum(tester);
    // 相册吸顶区：**一块**玻璃同时装两行，所以这里只量到一块（分类行与日期
    // 行共用同一份材质，不可能各写一套）。
    expect(_albumChromeBar(), findsOneWidget,
        reason: '相册吸顶区不是一块玻璃：分类行与日期行各自带玻璃就是两条');
    expect(_albumDateRow(), findsOneWidget, reason: '两块里只剩一块日期行了');
    final albumChrome = _chromeOf(tester, _albumChromeBar(), '相册吸顶区');
    final albumRect = tester.getRect(_albumChromeBar());
    _expectPinnedDecoration(tester, _albumChromeBar(), '相册吸顶区');

    addTearDown(installFakeApi(json: _feedJson()));
    await tester.pumpWidget(_feedPage());
    await tester.pumpAndSettle();
    final feedDate = _chromeOf(tester, _pinnedDateBar(), '朋友圈吸顶日期条');
    final feedRect = tester.getRect(_pinnedDateBar());
    _expectPinnedDecoration(tester, _pinnedDateBar(), '朋友圈吸顶日期条');

    // 四处 chrome：footer + 相册吸顶区（分类行 + 日期行同一块）+ 朋友圈日期条。
    final sites = <_Chrome>[albumChrome, feedDate];

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

    // 2. 共用那一半：模糊 / 饱和度 / 光照 / 边缘吸收三处 = footer，一项一项比
    //    （不是「大致同一档」）。吸顶条只在折射三数上分家。
    for (final site in sites) {
      expect(site.blur, footer.blur,
          reason: '${site.name} 的模糊半径与 footer 不一致');
      expect(site.saturation, footer.saturation,
          reason: '${site.name} 的饱和度与 footer 不一致');
      expect(site.lightIntensity, footer.lightIntensity,
          reason: '${site.name} 的光照强度与 footer 不一致');
      expect(site.edgeAbsorption, closeTo(footer.edgeAbsorption, 1e-9),
          reason: '${site.name} 的边缘吸收与 footer 不一致（暗边会被放大）');
      expect(site.tintAlpha, closeTo(footer.tintAlpha, 1e-9),
          reason: '${site.name} 的 tint 与 footer 不一致');
      // 吸顶条**不要**那圈高光边：直边条横贯整屏，底部会留下一条像 1px 边框
      // 的亮线（footer 是胶囊，那圈边是它圆角上的高光，保留）。
      expect(site.rimShade, 0.0,
          reason: '${site.name} 还画着 rimShade（底部那条亮线）');
    }
    expect(footer.rimShade, greaterThan(0), reason: 'footer 的 rim 高光要保留');
    expect(footer.blur, appGlassChromeBlur);
    expect(footer.blur, 2, reason: '模糊保持 2：折射才不会被糊掉');
    expect(footer.saturation, appGlassChromeSaturation);
    expect(footer.saturation, 1.3);

    // 3. 折射那一档：footer = 旧的一组（36 / 1.55 / 0.22，不许跟着吸顶条变），
    //    三处吸顶条 = 新的一组（44 / 1.75 / 0.32），而且是**真的更高一档**。
    expect(footer.thickness, appGlassChromeThickness);
    expect(footer.thickness, 36, reason: 'footer 的斜面保持 36');
    expect(footer.chroma, appGlassChromeChromaticAberration);
    expect(footer.chroma, 0.22, reason: 'footer 的色散保持 0.22');
    expect(footer.refractiveIndex, appGlassChromeRefractiveIndex);
    expect(footer.refractiveIndex, 1.55, reason: 'footer 的折射率保持 1.55');
    for (final site in sites) {
      expect(site.thickness, appGlassPinnedThickness,
          reason: '${site.name} 的斜面厚度不是吸顶条那一档');
      expect(site.thickness, 44, reason: '${site.name} 的斜面是 44（footer 36）');
      expect(site.refractiveIndex, appGlassPinnedRefractiveIndex,
          reason: '${site.name} 的折射率不是吸顶条那一档');
      expect(site.refractiveIndex, 1.75,
          reason: '${site.name} 的折射率是 1.75（footer 1.55）');
      expect(site.chroma, appGlassPinnedChromaticAberration,
          reason: '${site.name} 的色散不是吸顶条那一档');
      expect(site.chroma, 0.32, reason: '${site.name} 的色散是 0.32（footer 0.22）');
      // 「更高一档」不是三个不相干的数：逐项都比 footer 高。
      expect(site.thickness, greaterThan(footer.thickness),
          reason: '${site.name} 的斜面没有比 footer 更深');
      expect(site.refractiveIndex, greaterThan(footer.refractiveIndex),
          reason: '${site.name} 的折射率没有比 footer 更高');
      expect(site.chroma, greaterThan(footer.chroma),
          reason: '${site.name} 的色散没有比 footer 更强');
      // 而且不是「顺手把 footer 一起改了」：两边的参数确实不是同一份。
      expect(site.settings, isNot(equals(footer.settings)),
          reason: '${site.name} 与 footer 用的是同一份参数：这一档没生效');
    }
    // scrim 0.55 = 折射可见度 45%。
    expect(footer.scrimAlpha, closeTo(0.55, 1e-9));
    expect(footer.scrimAlpha, closeTo(appGlassChromeScrimAlpha(), 1e-9));
    expect(appGlassChromeRefractionVisibility(), closeTo(0.45, 1e-9));

    // 4. 圆角按各自形态取：footer 是胶囊（28），三处吸顶条一律 **0**。
    expect(footer.radius, AppBottomTabBar.radius);
    expect(footer.radius, AppBottomTabBar.barHeight / 2, reason: 'footer 是胶囊');
    expect(footer.radius, 28, reason: 'footer 的胶囊圆角保持 28');
    expect(kAppChromePinnedRadius, 0, reason: '吸顶条是直边条，圆角只有 0 这一档');
    expect(kPinnedDateHeaderRadius, kAppChromePinnedRadius);
    for (final site in sites) {
      expect(site.radius, 0, reason: '${site.name} 还有圆角：吸顶时两端会露出照片');
      expect(site.radius, kAppChromePinnedRadius);
    }

    // 5. 描边 / 内高光 / 底衬：三处吸顶条只留玻璃本体 + 固定底衬；
    //    footer 仍是「描边 + 高光、无底衬」。
    for (final site in sites) {
      expect(site.showBorder, isFalse, reason: '${site.name} 还画着 1px 描边');
      expect(site.showHighlight, isFalse,
          reason: '${site.name} 还画着顶部内高光');
      expect(site.backplate, isNotNull, reason: '${site.name} 少了固定底衬');
      expect(site.backplate!.a, closeTo(kAppChromePinnedBackplateAlpha, 1e-9));
      expect(site.backplate,
          AppColors.bgPage.withValues(alpha: kAppChromePinnedBackplateAlpha),
          reason: '${site.name} 的底衬不是「页面底色 + 固定不透明度」');
    }
    expect(footer.showBorder, isTrue, reason: 'footer 的描边不许跟着吸顶条一起掉');
    expect(footer.showHighlight, isTrue, reason: 'footer 的内高光要保持');
    expect(footer.backplate, isNull, reason: 'footer 不加底衬');

    // 6. 直边 + 更深的斜面，不许把最矮的那条压出「上下暗边」。
    //
    //    包内的斜面宽度按物理像素计、再按 dpr/3 折算，所以**逻辑斜面宽 =
    //    thickness / 3**（与 dpr 无关）：36 → 12 lp，44 → 14.7 lp。直边条的
    //    斜面只落在上下两条长边上，两条斜面把中间的平台面夹在中间——平台面
    //    一旦被吃光，上下两条暗边就接成一条，整条带子发灰。
    double bevel(double thickness) => thickness / 3;
    // 最矮的一块是朋友圈吸顶日期条（相册那块是 46 + 34 = 80），实测而不是写死。
    expect(feedRect.height, 36, reason: '朋友圈吸顶日期条高 36，是最矮的一块');
    expect(albumRect.height, 80, reason: '相册吸顶区 = 分类行 46 + 日期行 34');
    for (final site in <({String name, Rect rect})>[
      (name: '朋友圈吸顶日期条', rect: feedRect),
      (name: '相册吸顶区', rect: albumRect),
    ]) {
      final flat = site.rect.height - bevel(appGlassPinnedThickness) * 2;
      expect(flat, greaterThan(0),
          reason: '${site.name} 上下两条斜面已经叠到一起：整条都在斜面上，'
              '这就是「上下暗边」');
      expect(flat, greaterThan(4),
          reason: '${site.name} 中间只剩 ${flat.toStringAsFixed(1)} lp 平台面：'
              '44 的斜面把它压成两条暗边夹一条缝');
    }
    // 比 footer 那一档只宽 ~2.7 lp：暗边本身是细线（见 appGlassPinnedThickness
    // 的推算），不是两条带；两档的量级一样，观感不会分家。
    expect(
      bevel(appGlassPinnedThickness) - bevel(appGlassChromeThickness),
      lessThan(3),
      reason: '吸顶条的斜面比 footer 宽了不止 3 lp：直边会被两条更粗的暗边夹住',
    );
    expect(bevel(appGlassPinnedThickness), lessThan(16),
        reason: '斜面宽过 16 lp 就该降 thickness 或挪 lightIntensity 了');
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

    // 相册吸顶日期条（玻璃里那一行）：日期文字 + 那一组的张数。
    await _scrollAlbum(tester);
    final dateTexts = tester
        .widgetList<Text>(find.descendant(
          of: _albumDateRow(),
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
