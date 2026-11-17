import 'dart:convert';
import 'dart:ui' as ui;

import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/album_view_settings.dart';
import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/album/album_timeline_layout.dart';
import 'package:album_app/features/album/feed_gallery_page.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/models/paged.dart';
import 'package:album_app/widgets/app_chrome_glass_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_glass_tone.dart';
import 'package:album_app/widgets/date_header.dart';
import 'package:album_app/widgets/pinned_bar_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LightweightLiquidGlass;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

// 日期分组头（「今天 · 11月15日」那条）的**底衬契约**（这一轮改过）：
//
// - **吸顶**的那一份：与底部 footer **完全相同**的玻璃（AppChromeGlassBar：
//   premium 折射 + 55% scrim（折射可见度 45%）+ 最低档模糊 + 自动墨色文字）。
//   以前它是「主题色浅渐变 + 一层兜底模糊」，用户要求统一成 footer 的材质。
// - **非吸顶**的那一份（内容流里的普通日期头）：**完全透明**——没有渐变、
//   没有模糊、没有玻璃、没有 scrim。文字直接压在页面背景（渐变或用户挑的
//   背景图）上，用的是同一套自动墨色（appGlassToneInkBare 按背景亮度挑）。
//
// 这份文件守六件事：
// 1. 非吸顶：子树里没有 DecoratedBox / ColoredBox / BackdropFilter / 玻璃；
// 2. 非吸顶：页面背景**原样**从条带里透上来（像素等于背景色，条纹一点没被压）；
// 3. 吸顶：带的是 footer 同款玻璃（同一个组件、同一组参数），且吸顶 sliver
//    自己不垫色；
// 4. 吸顶：滚过的照片纹理被玻璃盖住（条带里残留 < 0.02）；
// 5. 文字：两版都是 footer 未激活那一套（自动墨色 + 10.5 / w500），极端背景
//    ≥ 4.5:1（浅/深各一条）；
// 6. 两版同高同位：滚动到吸顶阈值时不会跳版。

const Key _pageKey = Key('date-header-backdrop-page');

/// 条带的替身背景：完全透明的那一份应该让它原样透上来。
const Color _backdropGreen = Color(0xFF2E7D32);

/// 条带下面「照片纹理」的替身：4px 黑白竖条纹。
Widget _stripes() => SizedBox(
      height: 44,
      child: Row(
        children: [
          for (var i = 0; i < 90; i++)
            Container(
              width: 4,
              color:
                  i.isEven ? const Color(0xFF121212) : const Color(0xFFEFEFEF),
            ),
        ],
      ),
    );

/// 铺满整块的条纹：合成「背景是照片纹理」的那一块用（不会撑破页面）。
Widget _fullStripes() => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 90; i++)
          Expanded(
            child: ColoredBox(
              color:
                  i.isEven ? const Color(0xFF121212) : const Color(0xFFEFEFEF),
            ),
          ),
      ],
    );

const AlbumSection _section =
    AlbumSection(header: '今天 · 11月15日', items: <Media>[]);

class _Shot {
  _Shot(this.bytes, this.width, this.height, this.origin);

  final List<int> bytes;
  final int width;
  final int height;
  final Offset origin;

  Color at(Offset global) {
    final x = (global.dx - origin.dx).round().clamp(0, width - 1);
    final y = (global.dy - origin.dy).round().clamp(0, height - 1);
    final offset = (y * width + x) * 4;
    return Color.fromARGB(bytes[offset + 3], bytes[offset], bytes[offset + 1],
        bytes[offset + 2]);
  }

  double luminanceAt(Offset global) => at(global).computeLuminance();
}

Future<_Shot> _shoot(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_pageKey));
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final origin = tester.getTopLeft(find.byKey(_pageKey));
  final shot =
      _Shot(data.buffer.asUint8List(), image.width, image.height, origin);
  image.dispose();
  return shot;
}

/// 一条水平扫描线上相邻像素的平均亮度差：0 = 纯色，越大 = 内容纹理越清楚。
double _localContrast(_Shot shot, double y, double fromX, double toX) {
  var sum = 0.0;
  var count = 0;
  var previous = shot.luminanceAt(Offset(fromX, y));
  for (var x = fromX + 1; x < toX; x += 1) {
    final value = shot.luminanceAt(Offset(x, y));
    sum += (value - previous).abs();
    count++;
    previous = value;
  }
  return count == 0 ? 0 : sum / count;
}

int _channel(double a, double b) => ((a - b).abs() * 255).round();

/// 一条日期条：220 高的占位 + 日期头 sliver + 一屏条纹。
Widget _page({required bool pinned, bool stripes = true}) => RepaintBoundary(
      key: _pageKey,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: AppGlassBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 220)),
                timelineDateHeaderSliver(pinned: pinned, section: _section),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _stripes(),
                    childCount: stripes ? 40 : 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Media _photo(int id, DateTime takenAt) => Media(
      id: id,
      type: 'image',
      thumbUrl: null,
      url: '',
      width: 1920,
      height: 1080,
      durationMs: null,
      takenAt: takenAt,
      createdAt: takenAt,
      postId: null,
    );

/// 跨 4 个月、每组 16 张：够滚动，既有吸顶的日期头也有内容流里的。
List<Media> _crossMonths() => <Media>[
      for (var month = 9; month <= 12; month++)
        for (var i = 0; i < 16; i++)
          _photo(month * 100 + i, DateTime(2024, month, 5, 9, i)),
    ];

/// 日期头里的那条文字（两版都只有一条）。
Finder _dateText() => find.text('今天 · 11月15日');

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

  testWidgets('非吸顶：完全透明——没有渐变、没有模糊、没有玻璃', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(_page(pinned: false, stripes: false));
    await tester.pumpAndSettle();

    // 非吸顶这一份不套吸顶 sliver。
    expect(find.byType(PinnedBarSliver), findsNothing);
    expect(find.byType(AppChromeGlassBar), findsNothing,
        reason: '内容流里的日期头不该包玻璃（它下面没有内容经过）');

    final header = find.byType(DateHeader);
    expect(header, findsOneWidget);
    // 底衬一层都不许有：没有渐变色块、没有底色、没有模糊。
    for (final type in <Type>[
      DecoratedBox,
      ColoredBox,
      BackdropFilter,
      ClipRect,
    ]) {
      expect(
        find.descendant(of: header, matching: find.byType(type)),
        findsNothing,
        reason: '非吸顶日期头里还有一层 $type：它现在应该是完全透明的',
      );
    }
    // 几何不变：整块 38 高（34 文字区 + 4 与网格之间的留白）。
    expect(tester.getSize(header).height, kTimelineDateHeaderExtent);
    expect(tester.getSize(header).width, 360, reason: '条带仍然横贯整屏');
    expect(_dateText(), findsOneWidget, reason: '文字还得在');
  });

  testWidgets('吸顶：与底部 footer 同一块玻璃（同一个组件），吸顶 sliver 不垫色',
      (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(_page(pinned: true, stripes: false));
    await tester.pumpAndSettle();

    final pinnedBar =
        tester.widget<PinnedBarSliver>(find.byType(PinnedBarSliver));
    expect(pinnedBar.background, isNotNull);
    expect(pinnedBar.background!.a, 0.0,
        reason: '吸顶 sliver 垫了不透明色：玻璃顶上会多一条白杠');

    final glass = find.descendant(
      of: find.byType(PinnedBarSliver),
      matching: find.byType(AppChromeGlassBar),
    );
    expect(glass, findsOneWidget,
        reason: '吸顶日期头没有用 footer 同款玻璃（AppChromeGlassBar）');
    final surface = tester.widget<AppGlassSurface>(
      find.descendant(of: glass, matching: find.byType(AppGlassSurface)),
    );
    // 与 footer 逐项相同的那些开关（数值见 test/pinned_chrome_bar_test.dart）。
    expect(surface.preferPremium, isTrue);
    expect(surface.scrim, isTrue);
    expect(surface.useOwnLayer, isTrue);
    expect(surface.requestedQuality, AppChromeGlassBar.preferredQuality);
    // 圆角按形态取：日期条是满宽**条带**，不是胶囊。
    expect(surface.radius, kPinnedDateHeaderRadius);
    expect(tester.getSize(find.byType(DateHeader)).height,
        kTimelineDateHeaderExtent,
        reason: '换材质不许动几何');
    expect(tester.getSize(find.byType(DateHeader)).width, 360);
  });

  testWidgets('两版同高同位：滚到吸顶阈值时不会跳版', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(_page(pinned: true, stripes: false));
    await tester.pumpAndSettle();
    final pinnedRect = tester.getRect(find.byType(DateHeader));
    final pinnedStyle = tester.widget<Text>(_dateText()).style!;

    await tester.pumpWidget(_page(pinned: false, stripes: false));
    await tester.pumpAndSettle();
    final flowRect = tester.getRect(find.byType(DateHeader));
    final flowStyle = tester.widget<Text>(_dateText()).style!;

    expect(flowRect, pinnedRect, reason: '两版必须同高同位');
    // 两版文字是同一套：字号 / 字重 / 颜色逐项相同（自动墨色按同一份采样挑）。
    expect(flowStyle.fontSize, pinnedStyle.fontSize);
    expect(flowStyle.fontWeight, pinnedStyle.fontWeight);
    expect(flowStyle.color, pinnedStyle.color);
    expect(flowStyle.height, pinnedStyle.height);
  });

  testWidgets('非吸顶：页面背景原样透上来（像素 == 背景色）', (tester) async {
    _phoneViewport(tester);
    PageBackdropController.spec.value =
        const PageBackdropSpec.solid(_backdropGreen);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());
    await tester.pumpWidget(_page(pinned: false, stripes: false));
    await tester.pumpAndSettle();

    final band = tester.getRect(find.byType(DateHeader));
    final shot = await _shoot(tester);
    for (final dy in <double>[2, band.height / 2, band.height - 2]) {
      final pixel = shot.at(Offset(band.left + 3, band.top + dy));
      expect(_channel(pixel.r, _backdropGreen.r), lessThanOrEqualTo(2),
          reason: '条带在 y=$dy 处不是背景本身（实测 $pixel，期望 $_backdropGreen）：'
              '非吸顶日期头必须是完全透明的');
      expect(_channel(pixel.g, _backdropGreen.g), lessThanOrEqualTo(2));
      expect(_channel(pixel.b, _backdropGreen.b), lessThanOrEqualTo(2));
    }
  });

  testWidgets('吸顶：滚过的照片纹理被玻璃盖住（条带内残留 < 0.02）', (tester) async {
    _phoneViewport(tester);
    PageBackdropController.spec.value =
        const PageBackdropSpec.solid(_backdropGreen);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());
    await tester.pumpWidget(_page(pinned: true));
    await tester.pumpAndSettle();

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(320);
    await tester.pumpAndSettle();

    final band = tester.getRect(find.byType(DateHeader));
    final shot = await _shoot(tester);
    final inBand =
        _localContrast(shot, band.top + 3, band.left + 4, band.right - 4);
    // 对照组：条带下面 8px 处是没被遮住的同一条纹，纹理必须清清楚楚。
    final below =
        _localContrast(shot, band.bottom + 8, band.left + 4, band.right - 4);
    final ratio = below == 0 ? 0.0 : inBand / below;

    expect(below, greaterThan(0.1),
        reason: '对照组本身没有纹理，这条用例就测不出东西'
            '（below=${below.toStringAsFixed(4)}）');
    expect(inBand, lessThan(0.02),
        reason: '吸顶条里的照片纹理没被盖住（inBand=${inBand.toStringAsFixed(4)}）：'
            '玻璃/scrim 没画上去');
    expect(ratio, lessThan(0.10));
  });

  testWidgets('非吸顶：条纹一点没被压（残留 == 1.0）', (tester) async {
    _phoneViewport(tester);
    // 合成一块：条纹当背景，日期条只铺在上面（不吸顶、没有玻璃）。
    await tester.pumpWidget(
      RepaintBoundary(
        key: _pageKey,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                Positioned.fill(child: _fullStripes()),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 220),
                    child: timelineDateHeader(_section),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final band = tester.getRect(find.byType(DateHeader));
    final shot = await _shoot(tester);
    // 同一条 x 窗口（条纹是竖的，窗口相位才对得上）：条带里与条带下各取一条。
    final inBand =
        _localContrast(shot, band.top + 3, band.left + 4, band.left + 11);
    final outside =
        _localContrast(shot, band.bottom + 8, band.left + 4, band.left + 11);
    final ratio = outside == 0 ? 0.0 : inBand / outside;

    expect(outside, greaterThan(0.1),
        reason: '条带外面没有纹理，这条用例测不出东西'
            '（outside=${outside.toStringAsFixed(4)}）');
    expect(ratio, closeTo(1.0, 0.05),
        reason: '非吸顶条压掉了纹理（ratio=${ratio.toStringAsFixed(3)}）：'
            '它现在应该完全透明');
  });

  testWidgets('文字：footer 未激活那一套（自动墨色 + 10.5 / w500），极端背景 ≥4.5',
      (tester) async {
    _phoneViewport(tester);
    // 两版都要：底衬不同不影响文字契约。
    for (final pinned in <bool>[false, true]) {
      await tester.pumpWidget(_page(pinned: pinned, stripes: false));
      await tester.pump();
      final style = tester.widget<Text>(_dateText()).style!;
      expect(style.fontSize, kAppChromeLabelFontSize);
      expect(style.fontWeight, kAppChromeLabelWeight);
      expect(style.height, kAppChromeLabelHeight);
      expect(style.fontSize, 10.5, reason: '与 footer 标签同一个字号');
      expect(style.color, appGlassToneInkBare(AppBackdropSample.color.value),
          reason: 'pinned=$pinned：日期文字没有用自动墨色');
    }

    // 极端背景（纯白 / 纯黑 / 纯红 / 纯蓝）× 明暗：自动墨色必须都过 4.5:1。
    const extremes = <Color>[
      Color(0xFFFFFFFF),
      Color(0xFF000000),
      Color(0xFFFF0000),
      Color(0xFF0000FF),
    ];
    final worst = <bool, double>{};
    for (final dark in <bool>[false, true]) {
      AppColors.setDark(dark);
      var low = 99.0;
      for (final backdrop in extremes) {
        final ink = appGlassToneInkBare(backdrop);
        final ratio = AppAccent.contrastRatio(backdrop, ink);
        if (ratio < low) low = ratio;
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '透明日期条（dark=$dark，背景 $backdrop）上只有 '
              '${ratio.toStringAsFixed(2)}:1：低于 WCAG AA 4.5',
        );
      }
      worst[dark] = low;
    }
    // 实测值钉住：四种极端背景里最坏的是纯红（亮度 0.2126 ≥ 阈值 → 深墨，
    // (0.2126 + 0.05) / 0.05 = 5.25:1）。阈值不看明暗，两档同值。
    expect(worst[false]!, closeTo(5.25, 0.05));
    expect(worst[true]!, closeTo(5.25, 0.05));
    AppColors.setDark(false);
  });

  for (final page in <(String, Future<void> Function(WidgetTester))>[
    (
      '相册详情页',
      (tester) async {
        final data = _crossMonths();
        final album = Album(
          id: 7,
          title: '秋天到冬天',
          coverThumb: null,
          mediaCount: data.length,
          createdAt: DateTime(2020, 5, 1),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: AlbumDetailPage(
              album: album,
              loader: (id) async => AlbumDetail(album: album, items: data),
            ),
          ),
        );
        await tester.pumpAndSettle();
      },
    ),
    (
      '朋友圈相册',
      (tester) async {
        final items = _crossMonths();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: FeedGalleryPage(
                loader: (cursor) async => Paged<Media>(
                  items: cursor == null ? items : const <Media>[],
                  nextCursor: null,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      },
    ),
  ]) {
    testWidgets('${page.$1}：吸顶的是玻璃、内容流的是透明条', (tester) async {
      _phoneViewport(tester);
      await page.$2(tester);

      var pinnedChecked = 0;
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      for (final target in <double>[0, 200, 400, 700, 1000, 1400]) {
        position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
        await tester.pumpAndSettle();

        final headers = find.byType(DateHeader);
        expect(headers.evaluate(), isNotEmpty, reason: '分组模式必须有日期头');
        for (var i = 0; i < headers.evaluate().length; i++) {
          final header = tester.widget<DateHeader>(headers.at(i));
          final thisHeader = find.byElementPredicate(
            (element) => element == headers.evaluate().elementAt(i),
          );
          // 这条头是不是吸顶的那一条：只有它的祖先里有 PinnedBarSliver。
          final bars = find
              .ancestor(of: thisHeader, matching: find.byType(PinnedBarSliver))
              .evaluate();
          final glass = find
              .descendant(
                  of: thisHeader, matching: find.byType(AppChromeGlassBar))
              .evaluate();
          if (bars.isEmpty) {
            expect(header.pinned, isFalse);
            expect(glass, isEmpty,
                reason: '${page.$1}@$target 内容流里的日期头不该包玻璃');
            expect(
              find.descendant(
                of: thisHeader,
                matching: find.byType(BackdropFilter),
              ),
              findsNothing,
              reason: '${page.$1}@$target 内容流里的日期头里还有一层模糊',
            );
            expect(
              find.descendant(
                  of: thisHeader, matching: find.byType(DecoratedBox)),
              findsNothing,
              reason: '${page.$1}@$target 内容流里的日期头还垫着渐变/底色',
            );
            continue;
          }
          expect(header.pinned, isTrue,
              reason: '${page.$1}@$target 吸顶日期头没切到玻璃形态');
          expect(glass, hasLength(1),
              reason: '${page.$1}@$target 吸顶日期头缺 footer 同款玻璃');
          // 吸顶那一条：sliver 自己不垫色，底衬只有玻璃。
          final bar = tester.widget<PinnedBarSliver>(
            find.byElementPredicate((element) => element == bars.first),
          );
          expect(bar.background?.a ?? 1.0, 0.0,
              reason: '${page.$1} 吸顶 sliver 垫了不透明色（${bar.background}）');
          pinnedChecked++;
        }
      }
      expect(pinnedChecked, greaterThan(0),
          reason: '${page.$1} 至少要量到一条吸顶日期头');
    });
  }

  testWidgets('朋友圈动态流：吸顶日期头是 footer 同款玻璃', (tester) async {
    _phoneViewport(tester);
    addTearDown(
      installFakeApi(
        json: jsonEncode({
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
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const FeedPage()),
    );
    await tester.pumpAndSettle();

    final header = tester.widget<DateHeader>(find.byType(DateHeader).first);
    expect(header.pinned, isTrue, reason: '动态流顶部那条是吸顶的');
    expect(header.height, kFeedDateHeaderHeight, reason: '高度不变');
    expect(
      find.descendant(
        of: find.byType(DateHeader),
        matching: find.byType(AppChromeGlassBar),
      ),
      findsOneWidget,
      reason: '动态流的吸顶日期头没有用 footer 同款玻璃',
    );
  });
}
