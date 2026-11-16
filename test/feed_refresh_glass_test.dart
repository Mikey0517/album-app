import 'dart:convert';
import 'dart:ui' as ui;

import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

// 「朋友圈下拉刷新时出现黑色卡片」的复现用例。
//
// 现象：真机（Impeller）下拉刷新那几秒，列表里的卡片会整块发黑。
//
// 根因：卡片原来要 premium 档。premium 在包里的实现是
//   GlassContainer -> AdaptiveGlass -> LiquidGlass.withOwnLayer -> LiquidGlassLayer
// 的「全管线」路径：几何遮罩靠 Picture.toImageSync/render（1x1 兜底就在
// render_liquid_glass_geometry.dart 里），背景由 BackdropGroup/RepaintBoundary
// 的 capture 提供。列表某一次重建/滚动换掉了玻璃层，新层在「遮罩/背景 capture
// 还没就绪」的那一帧照样会画一遍：采到空纹理，叠上 tint 就是一块近黑。刷新
// 回调内暂停玻璃挡不住它——黑卡发生在刷新回调结束、数据替换之后的那几帧。
//
// 为什么不用 golden 像素采样直接测「黑」：flutter_tester 的
// ImageFilter.isShaderFilterSupported 是 false（见本文件第一条测试），premium
// 的 GPU 路径根本不会光栅化，修复前后拍出来是同一张图——golden 会是假绿。
// 能测的是「每一帧请求了哪条渲染路径」：premium = 需要 capture 的那条。
// 所以复现用例逐帧记录每张卡片表面的实际档位，并额外对卡片留白带做像素采样，
// 确认「不画玻璃」的那几帧是同色不透明底、不是黑色。

const Key _pageKey = Key('feed-page-boundary');

String _feedJson() {
  final items = <Map<String, Object?>>[];
  for (var i = 0; i < 4; i++) {
    items.add({
      'id': i + 1,
      'author_id': 1,
      'author_nickname': '妈妈',
      'content': '第 $i 条动态',
      'posted_at': '2026-01-0${i + 1}T10:00:00Z',
      'medias': <dynamic>[],
    });
  }
  return jsonEncode({'items': items, 'next_cursor': null});
}

/// 这一帧每张卡片表面走的是哪条路径：
/// - [GlassQuality.premium]：需要 capture 的路径（真机上就是黑卡的来源）；
/// - [GlassQuality.standard]：纯 BackdropFilter/轻量 shader，不抓 capture；
/// - opaque：这一帧不画玻璃（刷新保持 / 平台不支持）。
List<String> _cardPaths(WidgetTester tester) {
  final cards = find.byType(PostCard);
  final paths = <String>[];
  for (var i = 0; i < cards.evaluate().length; i++) {
    final glass = find.descendant(
      of: cards.at(i),
      matching: find.byType(GlassContainer),
    );
    final found = glass.evaluate().toList();
    if (found.isEmpty) {
      paths.add('opaque');
      continue;
    }
    paths.addAll(
      found.map((e) => (e.widget as GlassContainer).quality?.name ?? 'inherit'),
    );
  }
  return paths;
}

/// 第一张卡片的玻璃 [Element]：刷新往返里必须是**同一个**实例。
///
/// Element 换了 = 那一层玻璃被换掉/重建，真机上就是材质断一下；同实例说明
/// 刷新只是重绘，没有换材质。
Element? _firstCardGlassElement(WidgetTester tester) {
  final found = find
      .descendant(
        of: find.byType(PostCard).first,
        matching: find.byType(GlassContainer),
      )
      .evaluate()
      .toList();
  return found.isEmpty ? null : found.first;
}

/// 卡片留白带（玻璃外框上沿 8px 处，避开内缩 16 的正文）的平均亮度。
///
/// 白卡 ≈ 1.0；黑卡 ≈ 0.0。只取留白带是因为正文里本来就有深色文字，混进去
/// 会把「有没有黑块」这件事淹掉。
Future<double> _cardPaddingBandLuminance(WidgetTester tester) async {
  final surface = find.byType(AppGlassSurface).first;
  final rect = tester.getRect(surface);
  final origin = tester.getTopLeft(find.byKey(_pageKey));
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_pageKey));
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final dpr = image.width / boundary.size.width;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final bytes = data.buffer.asUint8List();
  final y =
      ((rect.top + 8 - origin.dy) * dpr).round().clamp(0, image.height - 1);
  var sum = 0.0;
  var count = 0;
  for (var x = rect.left + 8; x < rect.right - 8; x += 4) {
    final px = ((x - origin.dx) * dpr).round().clamp(0, image.width - 1);
    final offset = (y * image.width + px) * 4;
    final color = Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
    sum += color.computeLuminance();
    count++;
  }
  return count == 0 ? 0 : sum / count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppGlassRefreshHold.reset();
    AppColors.setDark(false);
    CurrentUser.notifier.value = const AppUser(
      id: 99,
      userId: 'mikey',
      nickname: 'Mikey',
    );
  });

  tearDown(() {
    AppGlassRefreshHold.reset();
    CurrentUser.notifier.value = null;
    AppColors.setDark(false);
  });

  testWidgets('复现前提：flutter_tester 里 premium 的 GPU 路径不参与光栅化', (tester) async {
    // 这条不是被测行为，是把「为什么只能用渲染路径而不是 golden 像素采样来
    // 复现」钉成证据：premium 的 toImageSync/BackdropGroup 在这台测试环境里
    // 压根不会跑，修复前后像素一致。
    expect(
      ui.ImageFilter.isShaderFilterSupported,
      isFalse,
      reason: '若这条变成 true，就该把下面的用例升级成真正的 golden 像素复现',
    );
  });

  testWidgets('下拉刷新全过程：玻璃材质连续（没有 opaque 中间态），黑卡仍不复现',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(installFakeApi(
      json: _feedJson(),
      delay: const Duration(milliseconds: 320),
    ));

    // 上限钉成 premium：模拟真机（Impeller）拿得到 premium 的那一档。修复要
    // 做到的是「就算上限允许，卡片自己也不要」，所以这条注入必须有。
    await tester.pumpWidget(AppGlassScope(
      quality: GlassQuality.premium,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const RepaintBoundary(key: _pageKey, child: FeedPage()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PostCard), findsWidgets);

    // 刷新前的基准：卡片档位、玻璃元素实例、刷新区重绘边界的实例、留白带亮度。
    final beforePaths = _cardPaths(tester);
    final glassBefore = _firstCardGlassElement(tester);
    final layerBefore =
        tester.element(find.byKey(FeedRefreshGlassLayer.repaintKey));
    final luminanceBefore = await _cardPaddingBandLuminance(tester);
    expect(beforePaths, isNotEmpty);
    expect(
      beforePaths.every((p) => p == GlassQuality.standard.name),
      isTrue,
      reason: '刷新前卡片就是 standard 玻璃：$beforePaths',
    );
    expect(glassBefore, isNotNull);

    // 用 RefreshIndicator 真正会调用的那个回调走一遍下拉刷新。
    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final future = refresh.onRefresh();
    await tester.pump();
    // 老实现（刷新期间换成同色不透明表面）在这一行就把 hold 打开了——那一进
    // 一出正是「下拉刷新闪一下」的来源，现在 feed 页不许再动材质。
    expect(AppGlassRefreshHold.isActive, isFalse,
        reason: '刷新期间不换材质：不再把玻璃暂停成不透明表面');

    final frames = <String, List<List<String>>>{
      '刷新前': [beforePaths],
    };

    // 刷新往返逐帧记录。回包有 320ms 假延时，20 帧 × 16ms 刚好把「刷新中」
    // 和「回包后数据替换」两段都盖住（老实现的闪烁就发生在后半段）。
    //
    // 每帧除了记档位，还采一次卡片留白带的亮度：材质换没换，亮度是最直接的
    // 证据——换成不透明 bgSurface（浅色纯白）那几帧会明显亮出去。
    final refreshFrames = <List<String>>[];
    final refreshLuminance = <double>[];
    for (var i = 0; i < 20; i++) {
      refreshLuminance.add(await _cardPaddingBandLuminance(tester));
      refreshFrames.add(_cardPaths(tester));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await future;
    await tester.pumpAndSettle();

    // 数据替换完成后连续几帧：黑卡原本就发生在这一段。
    final afterFrames = <List<String>>[];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      afterFrames.add(_cardPaths(tester));
    }
    final afterLuminance = await _cardPaddingBandLuminance(tester);

    // 再滚一屏：列表重建/滚动期间的 capture 时机问题同样要覆盖。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
    final scrollFrames = <List<String>>[];
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      scrollFrames.add(_cardPaths(tester));
    }
    frames['刷新往返'] = refreshFrames;
    frames['刷新后'] = afterFrames;
    frames['滚动中'] = scrollFrames;

    final premiumFrames = <String, List<String>>{};
    final opaqueFrames = <String, List<String>>{};
    frames.forEach((phase, phaseFrames) {
      for (final paths in phaseFrames) {
        if (paths.any((p) => p == GlassQuality.premium.name)) {
          premiumFrames.putIfAbsent(phase, () => paths);
        }
        if (paths.any((p) => p == 'opaque')) {
          opaqueFrames.putIfAbsent(phase, () => paths);
        }
      }
    });

    expect(
      premiumFrames,
      isEmpty,
      reason: '这些帧（阶段 → 卡片档位）里卡片又走 premium 了：'
          '$premiumFrames；'
          'premium = 需要 toImageSync/capture 的全管线路径，列表重建的那一帧'
          'capture 还没就绪就会画出一块近黑——真机上的黑卡就是这几帧。'
          '卡片必须固定在 standard（纯 BackdropFilter）。',
    );

    // 材质连续：刷新前/往返/刷新后/滚动中，每一帧每张卡片都是同一层玻璃，
    // 没有任何一帧退回「不透明表面」——那一次切换就是闪烁本身。
    expect(
      opaqueFrames,
      isEmpty,
      reason: '这些帧里卡片变成了不透明表面（材质切换 = 闪烁）：$opaqueFrames',
    );

    // 不是「换了但很快换回来」：玻璃元素与刷新区重绘边界刷新前后必须是同一个
    // 实例，说明刷新往返里材质层根本没被换掉/重建。
    expect(
      _firstCardGlassElement(tester),
      same(glassBefore),
      reason: '刷新后卡片的玻璃 Element 换了实例：材质层被重建，画面就会闪',
    );
    expect(
      tester.element(find.byKey(FeedRefreshGlassLayer.repaintKey)),
      same(layerBefore),
      reason: '刷新区重绘边界刷新后换了实例：整棵刷新区被重建了',
    );

    // 亮度连续：刷新中的每一帧都只能落在「刷新前」和「刷新后」两个稳态之间。
    // 老实现（换成不透明 bgSurface）会在中途亮出去/暗下去一截——那一截就是
    // 用户看到的那下闪。稳态本身在刷新后可以有一点位移（数据替换后卡片内容
    // 变了），但**不许有超出稳态的瞬时跳变**。
    final steadyLow = luminanceBefore < afterLuminance
        ? luminanceBefore
        : afterLuminance;
    final steadyHigh = luminanceBefore < afterLuminance
        ? afterLuminance
        : luminanceBefore;
    for (final value in refreshLuminance) {
      expect(
        value,
        inInclusiveRange(steadyLow - 0.02, steadyHigh + 0.02),
        reason: '刷新往返里有一帧的留白带亮度 $value 超出了稳态区间 '
            '[${steadyLow.toStringAsFixed(4)}, ${steadyHigh.toStringAsFixed(4)}]：'
            '这就是材质切换那一帧（刷新前 $luminanceBefore、刷新后 $afterLuminance）。',
      );
      expect(value, greaterThan(0.5), reason: '刷新期间不许出现发黑的卡片');
    }
    expect(afterLuminance, greaterThan(0.5),
        reason: '刷新后卡片留白带亮度 $afterLuminance');
    expect(tester.takeException(), isNull);
  });
}