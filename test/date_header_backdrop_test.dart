import 'dart:convert';
import 'dart:ui' as ui;

import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/album_view_settings.dart';
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
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/date_header.dart';
import 'package:album_app/widgets/pinned_bar_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LightweightLiquidGlass;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

// 日期分组头（「今天 · 11月15日」那条）的**底衬**：从 [AppColors.bgPage] 实底
// 改成透明，吸顶的那一条再叠一层极轻模糊。
//
// 为什么透明：它压在 [AppGlassBackdrop] 的渐变（或背景图）上，垫一层页面底色
// 之后渐变到这里就被截成一条白杠——和分类筛选条是同一处毛病。
//
// 为什么吸顶那条还要模糊（而不是纯透明）：吸顶条下面是滚过的照片。实测把 4px
// 黑白条纹（照片纹理的替身）压在条带下，量条带内相邻像素的平均亮度差（5 条
// 扫描线取最大）：
// - 纯透明：0.2092 —— 条纹一条条看得清清楚楚，字糊在纹理里；
// - 透明 + blur 8：0.0103；
// - 透明 + blur 12：0.0102（只比 blur 8 好 1%，没有意义）；
// - 不透明底衬（对照组）：文字线以外的扫描线 0.0046~0.0096。
// 0.0103 与不透明底衬同一档，所以取 blur 8（[kDateHeaderBlur]）：最小的那一档
// 里已经干净，不往上加。阈值取 0.02（纯透明的 1/10，约 5/255）。

const Key _pageKey = Key('date-header-backdrop-page');

/// 条带只要真的透明，就该是这块绿，而不是 bgPage。
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

/// 条带里最脏的那一条扫描线：文字行上下 + 下沿 4 的留白都量。
double _bandContrast(_Shot shot, Rect band) {
  final values = <double>[
    for (final dy in <double>[2, 8, 18, 30, band.height - 2])
      _localContrast(shot, band.top + dy, band.left + 4, band.right - 4),
  ];
  return values.reduce((a, b) => a > b ? a : b);
}

int _channel(double a, double b) => ((a - b).abs() * 255).round();

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
                timelineDateHeaderSliver(
                  pinned: pinned,
                  child: timelineDateHeader(_section),
                ),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AlbumViewSettings.group.value = AlbumGroup.day;
  });
  tearDown(() {
    AlbumViewSettings.group.value = AlbumGroup.day;
    PageBackdropController.spec.value = const PageBackdropSpec.defaultGradient();
  });

  test('底衬透明，吸顶那条叠的模糊只有一档', () {
    const header = DateHeader(text: '今天 · 11月15日');
    expect(header.color.a, 0.0, reason: '日期头不许再垫 [AppColors.bgPage] 实底');
    expect(kDateHeaderBlur, inInclusiveRange(4, 12),
        reason: '极轻模糊：再大就成整块毛玻璃，再小压不住条纹（实测见文件头）');
    expect(kDateHeaderBlur, 8, reason: '实测 blur 8 已与不透明底衬同档，12 只再好 1%');
  });

  testWidgets('吸顶日期头：sliver 不垫色，模糊层是单独一层且铺满整条', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(_page(pinned: true));
    await tester.pumpAndSettle();

    final pinned = tester.widget<PinnedBarSliver>(find.byType(PinnedBarSliver));
    expect(pinned.background, isNotNull);
    expect(pinned.background!.a, 0.0,
        reason: '吸顶 sliver 垫了不透明色，模糊就只采到这块色，背景透不上来');

    final header = tester.widget<DateHeader>(find.byType(DateHeader));
    expect(header.color.a, 0.0, reason: '日期头自己的底衬也必须是透明');

    final blur = find.byKey(DateHeaderBlur.blurKey);
    expect(blur, findsOneWidget, reason: '吸顶那条要有一层模糊兜住滚过的照片');
    expect(
      tester.widget<DateHeaderBlur>(find.byType(DateHeaderBlur)).blur,
      kDateHeaderBlur,
    );
    expect(tester.widget<BackdropFilter>(blur).filter, isNotNull);
    final band = tester.getRect(find.byType(DateHeader));
    expect(tester.getSize(blur).height, kTimelineDateHeaderExtent,
        reason: '模糊层铺满整条（含下沿 4 的留白），不能只糊文字区');
    expect(tester.getSize(blur).width, band.width,
        reason: '模糊层左右也要铺满，不能各留一条没糊的边');
  });

  testWidgets('内容流日期头：同样透明，但不叠模糊（它下面没有滚动内容）', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(_page(pinned: false));
    await tester.pumpAndSettle();

    expect(find.byType(PinnedBarSliver), findsNothing);
    expect(find.byKey(DateHeaderBlur.blurKey), findsNothing,
        reason: '内容流里的日期头跟着内容走，下面没有照片，不需要模糊');
    final header = tester.widget<DateHeader>(find.byType(DateHeader));
    expect(header.color.a, 0.0);
    expect(
      tester.getSize(find.byType(DateHeader)).height,
      kTimelineDateHeaderExtent,
      reason: '底衬改透明不许动几何：34 文字区 + 4 留白',
    );
    expect(find.text('今天 · 11月15日'), findsOneWidget);
  });

  testWidgets('透明：页面背景是纯色时从条带里透出来', (tester) async {
    _phoneViewport(tester);
    PageBackdropController.spec.value =
        const PageBackdropSpec.solid(_backdropGreen);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());
    await tester.pumpWidget(_page(pinned: true, stripes: false));
    await tester.pumpAndSettle();

    final band = tester.getRect(find.byType(DateHeader));
    final shot = await _shoot(tester);
    // 取文字左边的内边距（文字从 16 起）：这一条就是「底衬」本身。
    final pixel = shot.at(Offset(band.left + 3, band.center.dy));

    final pixelText = pixel.toString();
    expect(_channel(pixel.g, _backdropGreen.g), lessThanOrEqualTo(2),
        reason: '条带底衬没有让页面背景透上来（实测 $pixelText，期望接近 '
            '$_backdropGreen）');
    expect(_channel(pixel.r, _backdropGreen.r), lessThanOrEqualTo(2));
    expect(_channel(pixel.b, _backdropGreen.b), lessThanOrEqualTo(2));
    expect(_channel(pixel.r, AppColors.bgPage.r), greaterThan(20),
        reason: '条带还是 bgPage 那块白底：透明度没有生效');
  });

  testWidgets('模糊兜底：条纹从吸顶条下滚过，条带内纹理残留 <= 0.02', (tester) async {
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
    final inBand = _bandContrast(shot, band);
    // 对照组：条带下面 8px 处是没被遮住的同一条纹，纹理必须清清楚楚。
    final below = _localContrast(shot, band.bottom + 8, band.left + 4,
        band.right - 4);

    final belowText = below.toStringAsFixed(4);
    final inBandText = inBand.toStringAsFixed(4);
    expect(below, greaterThan(0.1),
        reason: '对照组本身没有纹理，这条用例就测不出东西（below=$belowText）');
    expect(inBand, lessThan(0.02),
        reason: '条带里的照片纹理没被揉开（inBand=$inBandText，纯透明约 0.21）：'
            '吸顶条会显得脏');
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
    testWidgets('${page.$1}：吸顶日期头透明 + 一层模糊，内容流的也透明',
        (tester) async {
      _phoneViewport(tester);
      await page.$2(tester);

      // 逐个滚动位置量：照片会从这里从日期头下面穿过去。
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
          expect(header.color.a, 0.0,
              reason: '${page.$1}@$target 第 $i 条日期头的底衬不透明');
          // 这条头是不是吸顶的那一条：只有它的祖先里有 PinnedBarSliver。
          final thisHeader = find.byElementPredicate(
            (element) => element == headers.evaluate().elementAt(i),
          );
          final bars = find
              .ancestor(of: thisHeader, matching: find.byType(PinnedBarSliver))
              .evaluate();
          final blurs = find
              .ancestor(of: thisHeader, matching: find.byType(DateHeaderBlur))
              .evaluate();
          if (bars.isEmpty) {
            expect(blurs, isEmpty,
                reason: '${page.$1} 内容流里的日期头下面没有滚动内容，不该带模糊');
            continue;
          }
          // 吸顶那一条：带着模糊层，且 sliver 自己不垫色。
          expect(blurs, hasLength(1),
              reason: '${page.$1}@$target 吸顶日期头缺模糊层：'
                  '滚过的照片会从字后面透出来');
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

  testWidgets('朋友圈动态流：吸顶日期头同样透明 + 一层模糊', (tester) async {
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
    expect(header.color.a, 0.0, reason: '动态流的日期头也是透明底衬');
    expect(header.height, kFeedDateHeaderHeight, reason: '高度不变');
    final blur = find.byKey(DateHeaderBlur.blurKey);
    expect(blur, findsWidgets, reason: '吸顶日期头缺模糊层：卡片会从字后面透出来');
    expect(tester.getSize(blur.first).height, kFeedDateHeaderHeight);
  });
}
