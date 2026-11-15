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

  testWidgets('下拉刷新全过程：卡片每一帧都不许落到需要 capture 的 premium 路径',
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

    final frames = <String, List<List<String>>>{
      '刷新前': [_cardPaths(tester)],
    };

    // 用 RefreshIndicator 真正会调用的那个回调走一遍下拉刷新。
    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final future = refresh.onRefresh();
    await tester.pump();
    expect(AppGlassRefreshHold.isActive, isTrue, reason: '刷新段一开始就暂停玻璃');

    // 刷新保持期间逐帧记录。回包有 320ms 假延时，所以这里能真正看到「刷新中」
    // 的中间帧，而不是把回包后那一帧当成刷新中。
    final holdFrames = <List<String>>[];
    await tester.pump(const Duration(milliseconds: 16));
    final holdLuminance = await _cardPaddingBandLuminance(tester);
    for (var i = 0; i < 60; i++) {
      if (!AppGlassRefreshHold.isActive) break;
      holdFrames.add(_cardPaths(tester));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await future;
    await tester.pumpAndSettle();

    // 刷新结束、数据替换完成后连续几帧：黑卡就发生在这一段（暂停玻璃已经
    // 释放，卡片回到 premium 重新 capture）。
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
    frames['刷新保持'] = holdFrames;
    frames['刷新后'] = afterFrames;
    frames['滚动中'] = scrollFrames;

    final premiumFrames = <String, List<String>>{};
    frames.forEach((phase, phaseFrames) {
      for (final paths in phaseFrames) {
        if (paths.any((p) => p == GlassQuality.premium.name)) {
          premiumFrames.putIfAbsent(phase, () => paths);
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

    // 暂停玻璃作为第二层保险仍然要在。
    expect(
      holdFrames.any((paths) => paths.contains('opaque')),
      isTrue,
      reason: '刷新期间保留「暂停玻璃 → 同色不透明表面」',
    );
    // 刷新结束后必须回到玻璃（standard），不能一直钉在不透明面上。
    expect(
      afterFrames.any((paths) => paths.contains(GlassQuality.standard.name)),
      isTrue,
      reason: '刷新结束立刻回到 standard 玻璃，只是不再抓 capture',
    );
    // 不画玻璃的那几帧是同色不透明底，不是黑块。
    expect(holdLuminance, greaterThan(0.5),
        reason: '刷新保持期间卡片留白带亮度 $holdLuminance');
    expect(afterLuminance, greaterThan(0.5),
        reason: '刷新后卡片留白带亮度 $afterLuminance');
    expect(tester.takeException(), isNull);
  });
}