
import 'dart:ui' as ui;

import 'package:album_app/core/app_accent_controller.dart';
import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_timeline_layout.dart';
import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// 右侧时间轴**空闲时一个像素都不画**：没有常驻轨道（早先那条主色→透明的竖
// 渐变已经整层去掉），只有按住拖动时才浮出滑块与月份气泡。滑块是主色实色 +
// 轻微高光，月份气泡是主题色的深色版（白字 ≥ 4.5）。三处使用点（相册详情页、
// 朋友圈相册、朋友圈动态流）都走 PhotoTimelineScrubber，所以这里两种入口都量：
// 「空闲时不可见」用像素断言，「拖起来对不对」用组件断言。

const Size _viewport = Size(390, 844);

/// 时间轴下面那块底：整块纯色。空闲时一个像素都不许偏离它。
const Color kTimelineTestBackdrop = Color(0xFF3366CC);

/// 宿主页的重绘边界：像素从这里出。
const Key kTimelineHostKey = Key('timeline-host-boundary');

void _phone(WidgetTester tester) {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host(Widget content) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: RepaintBoundary(
          key: kTimelineHostKey,
          child: ColoredBox(color: kTimelineTestBackdrop, child: content),
        ),
      ),
    );

/// 相册详情页 / 朋友圈相册这一路（offsets 模式，时间轴顶边由 layout 给）。
Widget _albumTimelineHost(ScrollController controller) {
  return _host(
    Stack(
      children: [
        ListView.builder(
          controller: controller,
          itemCount: 40,
          itemBuilder: (context, index) => const SizedBox(height: 100),
        ),
        timelineScrubberLayer(
          controller: controller,
          itemCount: 40,
          itemOffsets: List.generate(40, (i) => i * 100.0),
          trackTop: 0,
          liveLabel: () => '2024年8月',
        ),
      ],
    ),
  );
}

/// 朋友圈动态流这一路（progress 模式）。
Widget _feedTimelineHost(ScrollController controller) {
  return _host(
    Stack(
      children: [
        ListView.builder(
          controller: controller,
          itemCount: 40,
          itemBuilder: (context, index) => const SizedBox(height: 100),
        ),
        FeedTimelineLayer(controller: controller, label: () => '2024年8月'),
      ],
    ),
  );
}

Color _bubbleColor(WidgetTester tester) {
  // key 挂在 _MonthBubble 上，真正的背景色在它里面的 Container 上。
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byKey(timelineScrubberLabelKey),
      matching: find.byType(Container),
    ),
  );
  return (container.decoration! as BoxDecoration).color!;
}

/// [rect] 里每个像素都必须是 [kTimelineTestBackdrop]：这一块没有任何绘制。
Future<void> _expectRegionUntouched(WidgetTester tester, Rect rect,
    {String reason = ''}) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(kTimelineHostKey));
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final bytes = data.buffer.asUint8List();
  final origin = tester.getTopLeft(find.byKey(kTimelineHostKey));
  var checked = 0;
  for (var y = rect.top.ceil() + 1; y < rect.bottom.floor() - 1; y += 4) {
    for (var x = rect.left.ceil() + 1; x < rect.right.floor() - 1; x += 1) {
      final px = (x - origin.dx)
          .round()
          .clamp(0, image.width - 1);
      final py = (y - origin.dy)
          .round()
          .clamp(0, image.height - 1);
      final offset = (py * image.width + px) * 4;
      final color = Color.fromARGB(bytes[offset + 3], bytes[offset],
          bytes[offset + 1], bytes[offset + 2]);
      expect(color, kTimelineTestBackdrop,
          reason: '$reason 像素 ($x,$y) 被涂成了 $color');
      checked++;
    }
  }
  image.dispose();
  expect(checked, greaterThan(500), reason: '采样点太少，断言没有意义');
}

void main() {
  tearDown(() {
    AppColors.setDark(false);
    AppAccentController.seed.value = AppAccent.brand;
  });

  group('时间轴配色：主题色系，没有一处纯白', () {
    test('空闲不透明度是 0：整条不可见', () {
      expect(timelineScrubberIdleAlpha, 0.0,
          reason: '空闲时时间轴不许画任何东西（含淡到几乎看不见的轨道）');
    });

    test('滑块是主题色实色 + 轻微高光（高光不加白底）', () {
      final gradient = timelineScrubberThumbGradient();
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.colors.first.r, closeTo(1.0, 1e-9), reason: '高光是白色');
      expect(gradient.colors.first.a, lessThanOrEqualTo(0.3),
          reason: '轻微高光，不是一条白杠');
      expect(gradient.colors.last.a, 0.0);
    });

    test('月份气泡是主题色深色版，白字对比度 ≥ 4.5（任意主题色 × 明暗）', () {
      for (final dark in <bool>[false, true]) {
        AppColors.setDark(dark);
        for (final preset in AppAccent.presets) {
          AppAccentController.seed.value = preset.color;
          final primary = AppColors.primary;
          final bubble = timelineMonthBubbleColor();
          final ratio = AppAccent.contrastRatio(bubble, Colors.white);
          expect(ratio, greaterThanOrEqualTo(timelineMonthBubbleMinContrast),
              reason:
                  '@p@（dark=$dark）白字对比度 @r@'.replaceFirst('@p@', preset.label).replaceFirst('@r@', ratio.toStringAsFixed(2)));
          expect(bubble, isNot(Colors.white));
          expect(bubble.a, 1.0, reason: '气泡背景要不透明，底下的照片不能透上来');
          expect(
            AppAccent.relativeLuminance(bubble),
            lessThan(AppAccent.relativeLuminance(primary)),
            reason: '气泡是主色的深色版，不是原色也不是纯黑',
          );
        }
      }
    });
  });

  group('两个入口（相册两处 + 朋友圈动态流）产出同一套时间轴', () {
    for (final entry in <(String, Widget Function(ScrollController))>[
      ('相册（offsets 模式）', _albumTimelineHost),
      ('朋友圈动态流（progress 模式）', _feedTimelineHost),
    ]) {
      testWidgets('@n@：空闲时整条不可见（无绘制层 + 像素全透明）'
          .replaceFirst('@n@', entry.$1), (tester) async {
        _phone(tester);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(entry.$2(controller));
        await tester.pumpAndSettle();

        expect(find.byType(PhotoTimelineScrubber), findsOneWidget);
        // 1) 画布层面：时间轴子树里没有任何绘制层（轨道已整层去掉）。
        expect(
          find.descendant(
            of: find.byType(PhotoTimelineScrubber),
            matching: find.byType(DecoratedBox),
          ),
          findsNothing,
          reason: '空闲时时间轴不许有轨道/底衬这类绘制层',
        );
        expect(find.byKey(timelineScrubberThumbKey), findsNothing);
        expect(find.byKey(timelineScrubberLabelKey), findsNothing);

        // 2) 像素层面：整块区域的每个像素都还是底色。
        final rect = tester.getRect(find.byType(PhotoTimelineScrubber));
        expect(rect.width, greaterThan(0));
        await _expectRegionUntouched(tester, rect);
      });

      testWidgets('@n@：拖拽时滑块是主色、气泡是深色版主色'
          .replaceFirst('@n@', entry.$1), (tester) async {
        _phone(tester);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(entry.$2(controller));
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.byType(PhotoTimelineScrubber));
        final gesture = await tester.startGesture(rect.center);
        await tester.pump();
        await gesture.moveBy(const Offset(0, 24));
        await tester.pump();
        await tester.pump();

        final thumb = tester.widget<Container>(
          find.byKey(timelineScrubberThumbKey),
        );
        final thumbDecoration = thumb.decoration! as BoxDecoration;
        expect(thumbDecoration.color, AppColors.primary,
            reason: '滑块是主题色实色');
        final highlight = thumbDecoration.gradient! as LinearGradient;
        expect(highlight.colors.first.a, lessThanOrEqualTo(0.3),
            reason: '只有一道轻微高光');

        expect(_bubbleColor(tester), timelineMonthBubbleColor());
        expect(
          AppAccent.contrastRatio(_bubbleColor(tester), Colors.white),
          greaterThanOrEqualTo(timelineMonthBubbleMinContrast),
        );

        // 拖起来之后才画东西：时间轴区域里出现了像素（滑块 + 气泡）。
        await gesture.up();
        await tester.pumpAndSettle();
      });
    }
  });
}
