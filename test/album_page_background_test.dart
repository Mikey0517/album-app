import 'dart:convert';
import 'dart:io';

import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/album/album_tab_page.dart';
import 'package:album_app/features/album/feed_gallery_page.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/widgets/app_category_menu.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

// 「朋友圈相册」和「家庭/私人相册」的背景必须是同一份。
//
// 两种入口：从「相册」tab 里看朋友圈相册（[FeedGalleryPage]，挂在
// [AlbumTabPage] 的 [AppGlassBackdrop] 下），和从列表 push 进入一个相册
// （[AlbumDetailPage]）。后者原来只有 Scaffold 的 bgPage 实底，前者是渐变，
// 于是同一个相册从两个入口看过去底色不一样。
//
// 这里不按 key 逐层点名（背景层的实现以后可能加形态），而是把「背景自己画的
// 那几层」按结构抽出来——[AppGlassBackdrop] 里、且不在 Scaffold 下面的
// [DecoratedBox]——再把两处的层类型、底色、渐变 colors/stops、遮罩色逐项比。
// 任何一处多画一层、少画一层、改一个 alpha 都会让两边对不上。

const Key _pageKey = Key('album-page-background-boundary');

/// 1x1 的 PNG：只是让 Image.file 真的能解码，像素内容无所谓。
final List<int> _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

/// 背景自己画的那几层：[AppGlassBackdrop] 的子树里、**不在 Scaffold 下面**
/// 的 [DecoratedBox]（Scaffold 下面的属于页面内容，不是页面背景）。
List<BoxDecoration> _backdropLayers(WidgetTester tester) {
  final layers = <BoxDecoration>[];
  final boxes = find
      .descendant(
        of: find.byType(AppGlassBackdrop),
        matching: find.byType(DecoratedBox),
      )
      .evaluate()
      .toList();
  for (final element in boxes) {
    if (element.findAncestorWidgetOfExactType<Scaffold>() != null) continue;
    final decoration = (element.widget as DecoratedBox).decoration;
    if (decoration is BoxDecoration) layers.add(decoration);
  }
  return layers;
}

/// 一层的「画法」：颜色 + 渐变的端点/色标/停靠点。两边逐字符比就行。
String _describe(BoxDecoration decoration) {
  final buffer = StringBuffer();
  if (decoration.color != null) {
    buffer.write('color=${decoration.color!.toARGB32()} ');
  }
  final gradient = decoration.gradient;
  if (gradient is LinearGradient) {
    buffer.write('linear ${gradient.begin}->${gradient.end} '
        'colors=${[for (final c in gradient.colors) c.toARGB32()]} '
        'stops=${gradient.stops}');
  } else if (gradient is RadialGradient) {
    buffer.write('radial center=${gradient.center} radius=${gradient.radius} '
        'colors=${[for (final c in gradient.colors) c.toARGB32()]} '
        'stops=${gradient.stops}');
  }
  return buffer.toString().trim();
}

List<String> _signature(WidgetTester tester) =>
    _backdropLayers(tester).map(_describe).toList();

Future<void> _pumpSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 相册 tab（三个分类共用同一个背景）。
Future<void> _pumpTabPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: const RepaintBoundary(key: _pageKey, child: AlbumTabPage()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 从列表 push 进来的相册详情页。
Future<void> _pumpDetailPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: RepaintBoundary(
        key: _pageKey,
        child: AlbumDetailPage(
          album: Album(
            id: 1,
            title: '家庭相册',
            coverThumb: null,
            mediaCount: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 切到某个分类（0 朋友圈相册 / 1 家庭相册 / 2 私人相册）。
Future<void> _selectTab(WidgetTester tester, int index) async {
  final menu = tester.widget<AppCategoryMenu>(find.byType(AppCategoryMenu));
  menu.onChanged(index);
  await tester.pump();
  expect(
    tester.widget<AppCategoryMenu>(find.byType(AppCategoryMenu)).selectedIndex,
    index,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 背景图副本要真文件（AppGlassBackdrop 用 existsSync 判定）：文件 IO 必须在
  // setUp 里做——testWidgets 的假时钟里 await 真实 IO 会一直等下去。
  late Directory tempDir;
  late File backdropFile;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppColors.setDark(false);
    PageBackdropController.spec.value =
        const PageBackdropSpec.defaultGradient();
    addTearDown(installFakeApi());
    tempDir = await Directory.systemTemp.createTemp('album_bg_test');
    backdropFile = File('${tempDir.path}/backdrop.png');
    await backdropFile.writeAsBytes(_tinyPng);
  });

  tearDown(() {
    AppColors.setDark(false);
    PageBackdropController.spec.value =
        const PageBackdropSpec.defaultGradient();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('朋友圈相册（tab 进入）与相册详情（push 进入）用同一份页面背景',
      (tester) async {
    await _pumpSize(tester);

    await _pumpTabPage(tester);
    expect(
      find.byType(AppGlassBackdrop),
      findsOneWidget,
      reason: '三个分类（含朋友圈相册）共用 AlbumTabPage 的同一个背景',
    );
    await _selectTab(tester, 0);
    expect(find.byType(FeedGalleryPage), findsOneWidget);
    final feedGalleryTab = _signature(tester);
    await _selectTab(tester, 1);
    final familyTab = _signature(tester);

    await _pumpDetailPage(tester);
    expect(
      find.byType(AppGlassBackdrop),
      findsOneWidget,
      reason: 'push 进入的相册详情页必须挂在同一份背景实现下（原来只有 '
          'Scaffold 的 bgPage 实底）',
    );
    final albumDetail = _signature(tester);

    // 层数、层类型、底色、渐变 colors/stops、遮罩色：一处不同就失败。
    expect(albumDetail, feedGalleryTab,
        reason: '相册详情页和「朋友圈相册」tab 的背景层对不上：'
            'push=$albumDetail tab=$feedGalleryTab');
    expect(albumDetail, familyTab,
        reason: '相册详情页和「家庭相册」tab 的背景层对不上：'
            'push=$albumDetail tab=$familyTab');

    // 底色就是全 App 唯一那个页面底色，不是某一页自己的颜色。
    final layers = _backdropLayers(tester);
    expect(layers, isNotEmpty);
    expect(layers.first.color, AppColors.bgPage,
        reason: '页面底色必须是 AppColors.bgPage（AppGlassBackdrop.baseKey）');

    // Scaffold 自己不上色，否则背景被它整片盖掉、两页又各是各的底。
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.transparent);
    await _pumpTabPage(tester);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.transparent);
  });

  testWidgets('自定义背景图：两页的图 + 可读性遮罩（alpha）完全一致', (tester) async {
    await _pumpSize(tester);
    PageBackdropController.spec.value =
        PageBackdropSpec.image(backdropFile.path);

    await _pumpTabPage(tester);
    await _selectTab(tester, 0);
    final tabLayers = _backdropLayers(tester);
    // 图那一层（BoxDecoration 里没有）之外，必须有一层遮罩。
    final tabMasks =
        tabLayers.where((d) => d.color == appBackdropMaskColor()).toList();

    await _pumpDetailPage(tester);
    final detailLayers = _backdropLayers(tester);
    final detailMasks =
        detailLayers.where((d) => d.color == appBackdropMaskColor()).toList();

    expect(tabMasks, hasLength(1),
        reason: '自定义背景图下，tab 页的遮罩层数与颜色应当来自 '
            'AppGlassBackdrop 一处（appBackdropMaskColor）');
    expect(detailMasks, hasLength(1));
    expect(detailMasks.single.color!.a, tabMasks.single.color!.a,
        reason: '两页的遮罩 alpha 必须一样');
    expect(
      _signature(tester),
      _signatureOf(tabLayers),
      reason: '图 + 遮罩这一组层两页必须逐项相等',
    );
  });

  testWidgets('朋友圈相册子树自己不画任何整屏底色', (tester) async {
    await _pumpSize(tester);
    await _pumpTabPage(tester);
    await _selectTab(tester, 0);

    final gallery = find.byType(FeedGalleryPage);
    expect(gallery, findsOneWidget);
    expect(
      find.descendant(of: gallery, matching: find.byType(AppGlassBackdrop)),
      findsNothing,
      reason: '朋友圈相册不许自带一份 AppGlassBackdrop（那就是第二套底色）',
    );
    expect(
      find.descendant(of: gallery, matching: find.byType(Scaffold)),
      findsNothing,
      reason: '朋友圈相册是 tab 的子页，自己开 Scaffold 就会盖掉共享背景',
    );

    // 任何一层铺满视口的底色/装饰都不许出现在它自己的子树里。
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    final painted = find
        .descendant(
          of: gallery,
          matching: find.byWidgetPredicate(
              (w) => w is DecoratedBox || w is ColoredBox),
        )
        .evaluate();
    for (final element in painted) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize) continue;
      expect(
        box.size.width >= view.width - 1 && box.size.height >= view.height - 1,
        isFalse,
        reason: '朋友圈相册子树里有一层铺满视口的底色：'
            '${(element.widget as dynamic).runtimeType} ${box.size}',
      );
    }
  });
}

/// [BoxDecoration] 列表的签名，用于不重新 pump 的比较。
List<String> _signatureOf(List<BoxDecoration> layers) =>
    layers.map(_describe).toList();
