import 'dart:convert';
import 'dart:ui' as ui;

import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/album_view_settings.dart';
import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/bar_tint.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/text_styles.dart';
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
import 'package:album_app/widgets/pinned_band_blur.dart';
import 'package:album_app/widgets/pinned_bar_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LightweightLiquidGlass;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

// 日期分组头（「今天 · 11月15日」那条）的**底衬**：从「透明 + blur 8」换成
// 主题色浅渐变。
//
// 上一版是透明底衬，吸顶那条再叠一层 DateHeaderBlur（blur 8）；用户反馈
// 「模糊透明有点奇怪」，模糊层这一版整层删除。现在底衬只有一层渐变：
// 主题色纵向从上沿 100% 走到 0% 的强度，浅色 0.10 → 0.02、深色 0.14 → 0.04
// （参数只有一份，见 BarTint，分类筛选条用的也是它）。
//
// 这份文件守五件事：
// 1. 底衬就是 LinearGradient、颜色取自 AppColors.primary、最大 alpha ≤ 0.16
//    （再高就不是「浅」渐变，会成色块）；
// 2. 没有 BackdropFilter / 模糊层：日期头子树里一层都不许有；
// 3. 页面背景（渐变或背景图）仍从条带里透上来——底衬不是实底；
// 4. 文字在新底衬上对比度 ≥ 4.5（浅/深各一条）；
// 5. 吸顶版与内容流版是**同一块**材质：同一个组件、同一份参数，切换时不突变。

const Key _pageKey = Key('date-header-backdrop-page');

/// 条带只要不是实底，页面背景就该从它里面透出来：这块绿是「背景图」的替身。
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
    AppColors.setDark(false);
  });
  tearDown(() {
    AlbumViewSettings.group.value = AlbumGroup.day;
    PageBackdropController.spec.value = const PageBackdropSpec.defaultGradient();
    AppColors.setDark(false);
  });

  test('底衬是主题色浅渐变：颜色取自 primary，最大 alpha ≤ 0.16', () {
    const header = DateHeader(text: '今天 · 11月15日');
    for (final dark in <bool>[false, true]) {
      AppColors.setDark(dark);
      final gradient = header.gradient;
      final primary = AppColors.primary;
      expect(gradient.begin, Alignment.topCenter, reason: '纵向渐变（dark=$dark）');
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.colors, hasLength(2));
      for (final color in gradient.colors) {
        expect(color.r, closeTo(primary.r, 1e-9),
            reason: '渐变颜色必须来自主题色（dark=$dark）');
        expect(color.g, closeTo(primary.g, 1e-9));
        expect(color.b, closeTo(primary.b, 1e-9));
      }
      expect(gradient.colors.first.a, closeTo(dark ? 0.14 : 0.10, 1e-9));
      expect(gradient.colors.last.a, closeTo(dark ? 0.04 : 0.02, 1e-9),
          reason: '下沿要几乎看不见：底衬是「浅」渐变，不是色块');
      for (final color in gradient.colors) {
        expect(color.a, lessThanOrEqualTo(BarTint.maxAlpha),
            reason: '渐变最大 alpha 超过 ${BarTint.maxAlpha}（dark=$dark）');
        expect(BarTint.maxAlpha, 0.16);
      }
    }
  });

  testWidgets('吸顶与内容流：同一个组件、同一份渐变，没有模糊层', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(_page(pinned: true, stripes: false));
    await tester.pumpAndSettle();

    final pinnedBar =
        tester.widget<PinnedBarSliver>(find.byType(PinnedBarSliver));
    expect(pinnedBar.background, isNotNull);
    expect(pinnedBar.background!.a, 0.0,
        reason: '吸顶 sliver 垫了不透明色：条带顶上会多一条白杠，而且吸顶版与'
            '内容流版就不是同一块底衬了');

    final header = tester.widget<DateHeader>(find.byType(DateHeader));
    expect(header.gradient, BarTint.gradient);
    // 底衬本身只有渐变这一层：模糊挂在这条带子的**外面**，是吸顶专用兜底，
    // 不参与「渐变 + 文字」这套底衬。
    expect(
      find.descendant(
        of: find.byType(DateHeader),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
      reason: '日期头自己的底衬里还有一层模糊：底衬只该是那层渐变',
    );
    expect(
      find.descendant(
        of: find.byType(DateHeader),
        matching: find.byType(ClipRect),
      ),
      findsNothing,
    );
    // 吸顶这一条多套一层很轻的模糊：渐变只压掉一成纹理，压不住滚过的照片。
    final blur = find.byType(PinnedBandBlur);
    expect(blur, findsOneWidget,
        reason: '吸顶日期头没有兜底模糊：浅渐变压不住从下面滚过的照片纹理');
    expect(tester.widget<PinnedBandBlur>(blur).blur, kPinnedBandBlur);
    expect(kPinnedBandBlur, inInclusiveRange(6, 8),
        reason: '兜底模糊取 6~8 那一档：再大就成一块毛玻璃');
    // 吸顶版与内容流版同高：底衬换色不许动几何。
    expect(tester.getSize(find.byType(DateHeader)).height,
        kTimelineDateHeaderExtent);
    expect(find.text('今天 · 11月15日'), findsOneWidget);

    // 同一块材质：内容流版的渐变与吸顶版逐字段相等。
    await tester.pumpWidget(_page(pinned: false, stripes: false));
    await tester.pumpAndSettle();
    expect(find.byType(PinnedBandBlur), findsNothing,
        reason: '内容流里的日期头下面没有内容经过，不该带兜底模糊');
    final flowHeader = tester.widget<DateHeader>(find.byType(DateHeader));
    expect(flowHeader.gradient.begin, header.gradient.begin);
    expect(flowHeader.gradient.end, header.gradient.end);
    expect(flowHeader.gradient.colors, header.gradient.colors,
        reason: '吸顶版与内容流版的渐变不一样：滚到吸顶阈值时会出现肉眼可见的突变');
  });

  testWidgets('吸顶与内容流的条带像素一致（切换那一下不突变）', (tester) async {
    _phoneViewport(tester);
    PageBackdropController.spec.value =
        const PageBackdropSpec.solid(_backdropGreen);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());

    await tester.pumpWidget(_page(pinned: true, stripes: false));
    await tester.pumpAndSettle();
    final pinnedBand = tester.getRect(find.byType(DateHeader));
    final pinnedShot = await _shoot(tester);

    await tester.pumpWidget(_page(pinned: false, stripes: false));
    await tester.pumpAndSettle();
    final flowBand = tester.getRect(find.byType(DateHeader));
    final flowShot = await _shoot(tester);

    expect(flowBand, pinnedBand, reason: '两种日期头必须同高同位');
    for (final dy in <double>[2, pinnedBand.height / 2, pinnedBand.height - 2]) {
      for (final dx in <double>[3, pinnedBand.width - 8]) {
        final offset = Offset(pinnedBand.left + dx, pinnedBand.top + dy);
        final a = pinnedShot.at(offset);
        final b = flowShot.at(offset);
        final delta = <int>[
          _channel(a.r, b.r),
          _channel(a.g, b.g),
          _channel(a.b, b.b),
        ];
        expect(delta.every((d) => d <= 1), isTrue,
            reason: '吸顶版与内容流版在 $offset 的像素不同（$a vs $b）：'
                '滚到吸顶阈值时会看见底衬跳一下');
      }
    }
  });

  testWidgets('文字对比度 ≥ 4.5：浅色 / 深色各一条', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(_page(pinned: true, stripes: false));
    await tester.pumpAndSettle();

    // 最坏的一档：渐变最强的上沿（alpha 最大、底衬被染得最深）。
    final worst = <bool, double>{};
    for (final dark in <bool>[false, true]) {
      AppColors.setDark(dark);
      final backplate = BarTint.backplateAt(0);
      final ratio = AppAccent.contrastRatio(backplate, AppColors.textOnGlass);
      worst[dark] = ratio;
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '日期条文字在新底衬上只有 ${ratio.toStringAsFixed(2)}:1'
            '（dark=$dark，底衬 $backplate）：低于 WCAG AA 4.5',
      );
      // 旧的 #8A93A6 在浅色这一层上是不够的——这条钉住「为什么换色」。
      // 深色模式的深底衬上它本来就有 4.90:1，够用；换色是为了浅色那一档，
      // 也让两条横条的文字色统一。
      final legacy = AppAccent.contrastRatio(backplate, const Color(0xFF8A93A6));
      if (!dark) {
        expect(legacy, lessThan(4.5),
            reason: 'sectionLabel 的原色在新底衬上居然过了 4.5：'
                '${legacy.toStringAsFixed(2)}:1，换色的理由要重写');
        expect(legacy, closeTo(2.57, 0.05));
      } else {
        expect(legacy, greaterThanOrEqualTo(4.5),
            reason: '深色下旧色的实测值是 4.90:1（够用，不是换色的原因）');
        expect(legacy, closeTo(4.90, 0.05));
      }
    }
    // 实测值（浅 / 深）钉住：底衬或文字色被谁改掉都会在这里露出来。
    expect(worst[false]!, closeTo(5.45, 0.15));
    expect(worst[true]!, closeTo(6.94, 0.15));

    // 组件真的用了这个色：不是只算了一遍数学。
    AppColors.setDark(false);
    final text = tester.widget<Text>(find.text('今天 · 11月15日'));
    expect(text.style!.color, AppColors.textOnGlass);
    expect(AppText.sectionLabel.color, const Color(0xFF8A93A6),
        reason: 'sectionLabel 是别人还在用的 token，不能就地改掉');
  });

  testWidgets('页面背景从渐变里透上来：不是实底，也不是纯透明', (tester) async {
    _phoneViewport(tester);
    PageBackdropController.spec.value =
        const PageBackdropSpec.solid(_backdropGreen);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());
    await tester.pumpWidget(_page(pinned: true, stripes: false));
    await tester.pumpAndSettle();

    final band = tester.getRect(find.byType(DateHeader));
    final shot = await _shoot(tester);
    final sample = Offset(band.left + 3, band.center.dy);
    final pixel = shot.at(sample);
    // 渐变在这一行（条带正中）的强度 = 两端中点，叠在绿底上的合成色。
    final t = (sample.dy - band.top) / band.height;
    final expected = BarTint.backplateAt(t, over: _backdropGreen);
    final pixelText = pixel.toString();
    expect(_channel(pixel.r, expected.r), lessThanOrEqualTo(3),
        reason: '条带里不是「渐变叠背景」（实测 $pixelText，期望 $expected）');
    expect(_channel(pixel.g, expected.g), lessThanOrEqualTo(3));
    expect(_channel(pixel.b, expected.b), lessThanOrEqualTo(3));
    expect(_channel(pixel.b, _backdropGreen.b), greaterThan(6),
        reason: '条带里看不到主题色：底衬没画（实测 $pixelText）');
    expect(_channel(pixel.r, AppColors.bgPage.r), greaterThan(20),
        reason: '条带又回到 bgPage 那块白底：实底会把页面背景截成一条白杠');
  });

  testWidgets('吸顶：滚过的条纹被兜底模糊揉开（残留 < 0.02）', (tester) async {
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

    final belowText = below.toStringAsFixed(4);
    final inBandText = inBand.toStringAsFixed(4);
    final ratioText = ratio.toStringAsFixed(3);
    expect(below, greaterThan(0.1),
        reason: '对照组本身没有纹理，这条用例就测不出东西（below=$belowText）');
    expect(find.byType(PinnedBandBlur), findsOneWidget);
    // 吸顶条的验收口径：模糊把纹理揉开，条带里只剩一层柔和色雾（< 0.02，
    // 纯渐变叠条纹时是 ≈0.19）。
    expect(inBand, lessThan(0.02),
        reason: '吸顶条里的照片纹理没被揉开（inBand=$inBandText / below=$belowText '
            '= $ratioText）：滚过的照片会一条条从字后面透出来');
    expect(ratio, lessThan(0.10),
        reason: '条带里的纹理残留太高（ratio=$ratioText）：兜底模糊没起作用');
  });

  testWidgets('非吸顶：纯渐变，纹理只被染淡（残留 ≈ 0.9，允许 ≤ 0.9）', (tester) async {
    _phoneViewport(tester);
    // 合成一块：条纹当背景，日期条只铺在上面（不吸顶、没有兜底模糊）。
    // 内容流里的日期头跟着内容一起滚，下面不会有东西经过，所以这里只要求
    // 「渐变把纹理染淡一点」——不要求压住它。
    await tester.pumpWidget(
      RepaintBoundary(
        key: _pageKey,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                const Positioned.fill(child: SizedBox.shrink()),
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
    // 同一条 x 窗口（条纹是竖的，窗口相位才对得上），条带里与条带下各取一条：
    // 文字从 16 起，4~14 这一段落在左右内边距里，只有底衬。
    // 取条带**最上沿**那一行（渐变最浓，alpha 0.10）：这是残留最低的一档。
    final inBand =
        _localContrast(shot, band.top + 3, band.left + 4, band.left + 14);
    final outside = _localContrast(
        shot, band.bottom + 8, band.left + 4, band.left + 14);
    final ratio = outside == 0 ? 0.0 : inBand / outside;
    final ratioText = ratio.toStringAsFixed(3);
    expect(outside, greaterThan(0.1),
        reason: '条带外面没有纹理，这条用例测不出东西（outside='
            '${outside.toStringAsFixed(4)}）');
    expect(ratio, lessThanOrEqualTo(0.95),
        reason: '非吸顶条的纹理残留 ratio=$ratioText 偏高：说明底衬被加了东西');
    expect(ratio, greaterThan(0.85),
        reason: '非吸顶条的纹理被压掉太多（ratio=$ratioText）：纯渐变只该染淡一成');
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
    testWidgets('${page.$1}：吸顶与内容流的日期头都是同一套渐变、都没有模糊',
        (tester) async {
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
          expect(header.gradient.colors, BarTint.gradient.colors,
              reason: '${page.$1}@$target 第 $i 条日期头的底衬不是主题色浅渐变');
          expect(header.gradient.colors.first.a,
              lessThanOrEqualTo(BarTint.maxAlpha));
          final thisHeader = find.byElementPredicate(
            (element) => element == headers.evaluate().elementAt(i),
          );
          // 子树里没有模糊层。
          expect(
            find.descendant(
              of: thisHeader,
              matching: find.byType(BackdropFilter),
            ),
            findsNothing,
            reason: '${page.$1}@$target 第 $i 条日期头里还有一层模糊',
          );
          // 这条头是不是吸顶的那一条：只有它的祖先里有 PinnedBarSliver。
          final bars = find
              .ancestor(of: thisHeader, matching: find.byType(PinnedBarSliver))
              .evaluate();
          final blurs = find
              .ancestor(of: thisHeader, matching: find.byType(PinnedBandBlur))
              .evaluate();
          if (bars.isEmpty) {
            expect(blurs, isEmpty,
                reason: '${page.$1} 内容流里的日期头不该带兜底模糊');
            continue;
          }
          expect(blurs, hasLength(1),
              reason: '${page.$1}@$target 吸顶日期头缺兜底模糊：'
                  '滚过的照片会从字后面透出来');
          // 吸顶那一条：sliver 自己不垫色，底衬只有 child 那一层渐变。
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

  testWidgets('朋友圈动态流：吸顶日期头同样是渐变、没有模糊', (tester) async {
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
    expect(header.gradient.colors, BarTint.gradient.colors,
        reason: '动态流的日期头用的是另一份底衬');
    expect(
      find.ancestor(
        of: find.byType(DateHeader).first,
        matching: find.byType(PinnedBandBlur),
      ),
      findsOneWidget,
      reason: '动态流的吸顶日期头缺兜底模糊：卡片会从字后面一条条透出来',
    );
    expect(header.height, kFeedDateHeaderHeight, reason: '高度不变');
    expect(
      find.descendant(
        of: find.byType(DateHeader),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
      reason: '动态流的吸顶日期头还挂着一层模糊：卡片会从字后面糊着透出来',
    );
  });
}
