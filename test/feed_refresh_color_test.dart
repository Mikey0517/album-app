
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassQuality, LightweightLiquidGlass, LiquidGlassSettings;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

// 「朋友圈下拉刷新时卡片变色」的复现与回归用例。
//
// 机制：标准档磨砂的合成是「模糊后的 backdrop × (1 − tintAlpha) + tint」。
// 卡片 tint 只有 37% 时背后内容占 63%，下拉刷新那几帧列表被拉伸/位移
// （BouncingScrollPhysics 下卡片整体下移 50~60 逻辑像素），玻璃采到的背景
// 换了一段，卡片亮度就跟着跳。
//
// 复现条件（三条都必要，缺一条就测不出东西）：
// 1. BouncingScrollPhysics（iOS 档）：Android 档的 ClampingScrollPhysics 下拉
//    时内容不动，卡片一帧都不会变——这不是「没问题」，是根本没位移；
// 2. 高对比背景：默认品牌渐变太淡，卡片移动 60px 也只差 1/255，量不出漂移
//    的振幅；深蓝 → 暖橙的双色渐变相当于一张对比度高的自定义背景图；
// 3. 采样跟着卡片走（每次重新取卡片矩形），量的是「这张卡片的颜色」，
//    不是屏幕上某个固定点。
//
// 阈值 3/255：实测 84% tint 下最坏 2/255（37% 时是 8/255），留 1 个计数给
// 抗锯齿/抖动的噪声；3/255 ≈ 1.2%，在大面积平色上低于约 2% 的恰可察觉差。

const Key _pageKey = Key('feed-refresh-color-page');

/// 卡片颜色允许的最大单通道差（0~255）。
const int kRefreshCardColorTolerance = 3;

/// 下拉至少要真的把卡片挪动这么多逻辑像素，复现才算成立。
const double kRefreshCardDisplacementFloor = 40;

/// 高对比背景：深蓝 → 暖橙（相当于一张对比度高的自定义背景图）。
const PageBackdropSpec _highContrastBackdrop = PageBackdropSpec.gradient(
  start: Color(0xFF20335A),
  end: Color(0xFFF2C48A),
);

String _feedJson() {
  final items = <Map<String, Object?>>[];
  for (var i = 0; i < 6; i++) {
    items.add({
      'id': i + 1,
      'author_id': 1,
      'author_nickname': '妈妈',
      'content': 'post-$i',
      'posted_at': '2026-01-0${i}T10:00:00Z',
      'medias': <dynamic>[],
    });
  }
  return jsonEncode({'items': items, 'next_cursor': null});
}

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

/// 一帧的采样：卡片留白区（外框内缩 8px）+ 内容区（正文右侧的卡片底）。
class _Frame {
  _Frame(this.phase, this.cardTop, this.pad, this.content);

  final String phase;
  final double cardTop;
  final Color pad;
  final Color content;
}

Future<_Frame> _frame(WidgetTester tester, String phase) async {
  final surface = find
      .descendant(
        of: find.byType(PostCard).first,
        matching: find.byType(AppGlassSurface),
      )
      .first;
  final card = tester.getRect(surface);
  // 内容区取正文右侧：在内容带里，但落在卡片底上（不是字上）。
  final text = tester.getRect(find.text('post-0'));
  final shot = await _shoot(tester);
  return _Frame(
    phase,
    card.top,
    shot.at(Offset(card.left + 8, card.top + 8)),
    shot.at(Offset(text.right + 8, text.center.dy)),
  );
}

int _channel(double a, double b) => ((a - b).abs() * 255).round();

void _expectStable(List<_Frame> frames, Color Function(_Frame) pick) {
  final base = frames.first;
  final reference = pick(base);
  for (final frame in frames.skip(1)) {
    final color = pick(frame);
    final delta = <int>[
      _channel(color.r, reference.r),
      _channel(color.g, reference.g),
      _channel(color.b, reference.b),
    ];
    expect(
      delta.every((d) => d <= kRefreshCardColorTolerance),
      isTrue,
      reason: '刷新阶段与「刷新前」的卡片颜色差超过 '
          'kRefreshCardColorTolerance（$kRefreshCardColorTolerance）/255：'
          '基准 $reference → 本阶段 $color，通道差 $delta',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppGlassRefreshHold.reset();
    AppColors.setDark(false);
    PageBackdropController.spec.value = _highContrastBackdrop;
    CurrentUser.notifier.value = const AppUser(
      id: 99,
      userId: 'mikey',
      nickname: 'Mikey',
    );
  });

  tearDown(() {
    AppGlassRefreshHold.reset();
    PageBackdropController.spec.value = const PageBackdropSpec.defaultGradient();
    CurrentUser.notifier.value = null;
    AppColors.setDark(false);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('下拉刷新四个阶段：卡片留白区与内容区的颜色差 ≤ 3/255', (tester) async {
    // iOS 档才有「内容被拉伸/位移」这一段（Android 档下拉时内容不动，
    // 位移为 0 的用例测不出漂移）。
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(installFakeApi(
      json: _feedJson(),
      delay: const Duration(milliseconds: 320),
    ));

    // 玻璃的轻量 shader（FragmentProgram）是懒加载的：没预热时第一帧只画
    // backdrop、不叠 tint，卡片会「看起来是原图」——那不是产品行为，是测试
    // 环境少了 main() 里那句 LiquidGlassWidgets.initialize()。这里显式预热，
    // 让四帧都走同一条（上色的）渲染路径，颜色差才代表真实观感。
    await tester.runAsync(() => LightweightLiquidGlass.preWarm());

    await tester.pumpWidget(AppGlassScope(
      quality: GlassQuality.premium,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const RepaintBoundary(key: _pageKey, child: FeedPage()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PostCard), findsWidgets);

    final frames = <_Frame>[await _frame(tester, '刷新前')];

    // 按住列表往下拖：RefreshIndicator 收到 overscroll，内容跟着下移。
    final list = find.byType(CustomScrollView);
    final gesture = await tester.startGesture(tester.getCenter(list));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    frames.add(await _frame(tester, '下拉中'));

    // 松手：刷新开始，指示器回弹，卡片往回走一段。
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    frames.add(await _frame(tester, '释放瞬间'));

    // 回包（320ms）+ 动画走完，数据替换完成。
    await tester.pump(const Duration(milliseconds: 200));
    frames.add(await _frame(tester, '刷新中'));

    await tester.pumpAndSettle();
    frames.add(await _frame(tester, '刷新完成'));

    // 复现前提：这一段确实把卡片挪动了，否则「颜色不变」是假的。
    final displacements =
        frames.map((f) => (f.cardTop - frames.first.cardTop).abs()).toList();
    expect(
      displacements.reduce((a, b) => a > b ? a : b),
      greaterThan(kRefreshCardDisplacementFloor),
      reason: '下拉没有真的移动卡片，这条用例没复现出「采样内容在变」',
    );

    _expectStable(frames, (f) => f.pad);
    _expectStable(frames, (f) => f.content);

    debugDefaultTargetPlatformOverride = null;
    PageBackdropController.spec.value = const PageBackdropSpec.defaultGradient();
    expect(tester.takeException(), isNull);
  });

  testWidgets('模糊半径不影响成品颜色（20 与 8 的卡片像素差 ≤ 2/255）', (tester) async {
    // tint 84% 之后 backdrop 只剩 16% 的权重，模糊再大也只作用在这 16% 上。
    // 这条把「降 blur 只是省成本，不改观感」钉住。
    final settings20 = _cardFrost(blur: 20);
    final settings8 = _cardFrost(blur: 8);
    tester.view.physicalSize = const Size(360, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() => LightweightLiquidGlass.preWarm());
    await tester.pumpWidget(RepaintBoundary(
      key: _pageKey,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(child: _stripes()),
              Positioned(
                left: 16,
                top: 20,
                width: 320,
                height: 120,
                child: AppGlassSurface(
                  depth: true,
                  settings: settings20,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: 16,
                top: 180,
                width: 320,
                height: 120,
                child: AppGlassSurface(
                  depth: true,
                  settings: settings8,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final cards = find.byType(AppGlassSurface);
    final shot = await _shoot(tester);
    final a = shot.at(tester.getRect(cards.at(0)).center);
    final b = shot.at(tester.getRect(cards.at(1)).center);
    final delta = <int>[
      _channel(a.r, b.r),
      _channel(a.g, b.g),
      _channel(a.b, b.b),
    ];
    expect(delta.every((d) => d <= 2), isTrue,
        reason: 'blur 20 与 blur 8 的卡片颜色差太大（$a vs $b，通道差 $delta）：'
            '降模糊改掉了观感，不能算「只是省成本」');
    expect(tester.takeException(), isNull);
  });
}

/// 卡片那套参数，只把模糊半径换掉。
LiquidGlassSettings _cardFrost({required double blur}) => LiquidGlassSettings(
      thickness: 12,
      blur: blur,
      glassColor: appCardFrostTintColor,
      lightAngle: 2.356,
      lightIntensity: 0.65,
      ambientStrength: 0.0,
      refractiveIndex: 1.0,
      saturation: 1.15,
      chromaticAberration: 0.0,
    );

/// 照片纹理的替身：4px 黑白竖条纹。
Widget _stripes() => Row(
      children: [
        for (var i = 0; i < 90; i++)
          Expanded(
            child: Container(
              color: i.isEven
                  ? const Color(0xFF121212)
                  : const Color(0xFFEFEFEF),
            ),
          ),
      ],
    );