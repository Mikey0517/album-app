
import 'dart:ui' as ui;

import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/features/album/album_media_filter.dart';
import 'package:album_app/features/album/album_media_filter_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:album_app/widgets/pinned_bar_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LightweightLiquidGlass;

// 相册分类筛选条的**吸顶底衬**：从 [AppColors.bgPage] 实底改成「透明 + 极轻
// 模糊」。
//
// 为什么透明：吸顶条是一条横贯整屏的窄带，垫成页面底色之后，
// [AppGlassBackdrop] 的渐变（或用户挑的背景图）到这里就被截成一条白杠。
//
// 为什么还要模糊（而不是纯透明）：条带下面是滚动的照片。实测把 4px 黑白条纹
// （照片纹理的替身）压在条带下：
// - 纯透明：条纹相邻像素平均亮度差 0.2096，一条条看得清清楚楚；
// - 加 8% 的 bgPage 蒙版：0.2087（只压掉 0.4%，等于没加）；
// - 加 blur 8：0.0060，和不透明底衬（0.0072）同一档——纹理没了，只剩色雾。
// 所以兜底选 blur，阈值取 0.02（纯透明的十分之一，约 5/255）。

const Key _pageKey = Key('segmented-backdrop-page');

/// 自定义纯色背景：条带只要真的透明，就该是这块绿，而不是 bgPage。
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

/// 一条带筛选条的相册页：220 高的占位 + 吸顶筛选条 + 一屏条纹。
Widget _page({ScrollController? controller}) => RepaintBoundary(
      key: _pageKey,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: AppGlassBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: CustomScrollView(
              controller: controller,
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 220)),
                const AlbumMediaFilterSliver(
                  counts: AlbumMediaCounts(
                    stillPhotos: 12,
                    livePhotos: 3,
                    videos: 2,
                  ),
                  selected: AlbumMediaFilter.all,
                  onChanged: _noop,
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _stripes(),
                    childCount: 30,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

void _noop(AlbumMediaFilter _) {}

void main() {
  tearDown(() {
    PageBackdropController.spec.value = const PageBackdropSpec.defaultGradient();
  });

  test('底衬的底色是「完全透明」，模糊半径取极轻那一档', () {
    const surface = AppSegmentedBarSurface(child: SizedBox.shrink());
    expect(surface.color.a, 0.0,
        reason: '吸顶底衬不许再垫 [AppColors.bgPage] 实底，渐变要透上来');
    expect(surface.blur, kAppSegmentedBarBlur);
    expect(kAppSegmentedBarBlur, inInclusiveRange(4, 12),
        reason: '极轻模糊：再大就成整块毛玻璃，再小压不住条纹');
  });

  testWidgets('分类条底衬：模糊层铺满整条，吸顶 sliver 自己不垫色', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    final pinned = tester.widget<PinnedBarSliver>(find.byType(PinnedBarSliver));
    expect(pinned.background, isNotNull);
    expect(pinned.background!.a, 0.0,
        reason: '吸顶 sliver 一旦垫了不透明色，模糊就只采到这块色，等于没透明');

    final surface = tester.widget<AppSegmentedBarSurface>(
      find.byType(AppSegmentedBarSurface),
    );
    expect(surface.color.a, 0.0);

    // 模糊层铺满整条（含上下 7 的内边距），不是只糊中间那一块。
    final blur = find.byKey(AppSegmentedBarSurface.blurKey);
    expect(blur, findsOneWidget);
    expect(tester.getSize(blur).height, kAppSegmentedBarHeight);
    expect(
      tester.getSize(blur).width,
      tester.getSize(find.byType(AppSegmentedBarSurface)).width,
      reason: '模糊层要铺满整条，左右不能各留一条没糊的边',
    );
    expect(tester.widget<BackdropFilter>(blur).filter, isNotNull);
  });

  testWidgets('透明：条带里的底色是页面背景，不是 bgPage 白杠', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PageBackdropController.spec.value = const PageBackdropSpec.solid(
      _backdropGreen,
    );
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());

    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    // 还没滚动：条带下面是页面背景本身（没有任何内容经过）。
    final band = tester.getRect(find.byType(AppSegmentedBarSurface));
    final shot = await _shoot(tester);
    // 取胶囊外的左边距（胶囊从 12 起）：这一条就是「底衬」本身。
    final pixel = shot.at(Offset(band.left + 3, band.center.dy));

    final pixelText = pixel.toString();
    final greenText = _backdropGreen.toString();
    expect(_channel(pixel.r, _backdropGreen.r), lessThanOrEqualTo(2),
        reason: '条带底衬没有让页面背景透上来（实测 $pixelText，'
            '期望接近 $greenText）');
    expect(_channel(pixel.g, _backdropGreen.g), lessThanOrEqualTo(2));
    expect(_channel(pixel.b, _backdropGreen.b), lessThanOrEqualTo(2));
    expect(_channel(pixel.r, AppColors.bgPage.r), greaterThan(20),
        reason: '条带还是 bgPage 那块白底：透明度没有生效');
  });

  testWidgets('模糊兜底：条纹压在条带下，纹理残留 < 0.02', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());

    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_page(controller: controller));
    await tester.pumpAndSettle();

    // 滚起来：条纹从吸顶条下面穿过去。
    controller.jumpTo(320);
    await tester.pumpAndSettle();

    final band = tester.getRect(find.byType(AppSegmentedBarSurface));
    final shot = await _shoot(tester);

    // 条带上沿 3px 那条（胶囊从 +7 开始）：整条都是「底衬」。
    final inBand = _localContrast(
      shot,
      band.top + 3,
      band.left + 4,
      band.right - 4,
    );
    // 对照组：条带下面 8px 处是没被遮住的同一条纹，纹理必须清清楚楚。
    final below = _localContrast(
      shot,
      band.bottom + 8,
      band.left + 4,
      band.right - 4,
    );

    final belowText = below.toStringAsFixed(4);
    final inBandText = inBand.toStringAsFixed(4);
    expect(below, greaterThan(0.1),
        reason: '对照组本身没有纹理，这条用例就测不出东西（below=$belowText）');
    expect(inBand, lessThan(0.02),
        reason: '条带里的内容纹理没有被揉开（inBand=$inBandText，'
            '纯透明约 0.21）：吸顶条会显得脏');
  });
}
