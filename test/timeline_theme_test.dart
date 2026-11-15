import 'package:album_app/core/app_accent_controller.dart';
import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_timeline_layout.dart';
import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 右侧时间轴不再是「纯白/纯黑」的一套：轨道是主色→透明的竖向渐变，滑块是
// 主色实色 + 轻微高光，月份气泡是主题色的深色版（白字 ≥ 4.5）。三处使用点
// （相册详情页、朋友圈相册、朋友圈动态流）都走 PhotoTimelineScrubber，所以
// 这里两边都量：单点颜色正确 + 两个入口产出同一套颜色。

const Size _viewport = Size(390, 844);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 相册详情页 / 朋友圈相册这一路（offsets 模式，轨道顶边由 layout 给）。
Widget _albumTimelineHost(ScrollController controller) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Stack(
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
    ),
  );
}

/// 朋友圈动态流这一路（progress 模式）。
Widget _feedTimelineHost(ScrollController controller) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Stack(
        children: [
          ListView.builder(
            controller: controller,
            itemCount: 40,
            itemBuilder: (context, index) => const SizedBox(height: 100),
          ),
          FeedTimelineLayer(controller: controller, label: () => '2024年8月'),
        ],
      ),
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester, Key key) {
  final widget = tester.widget<DecoratedBox>(find.byKey(key));
  return widget.decoration as BoxDecoration;
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

void main() {
  tearDown(() {
    AppColors.setDark(false);
    AppAccentController.seed.value = AppAccent.brand;
  });

  group('时间轴配色：主题色系，没有一处纯白', () {
    test('轨道是 primary → transparent 的竖向渐变，透明度落在 10%~18%', () {
      final gradient = timelineScrubberTrackGradient();
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.colors, hasLength(2));

      final top = gradient.colors.first;
      final bottom = gradient.colors.last;
      expect(timelineScrubberTrackAlpha, inInclusiveRange(0.10, 0.18));
      expect(top.a, closeTo(timelineScrubberTrackAlpha, 1e-9));
      expect(bottom.a, 0.0, reason: '底端透明：轨道自己淡出，不画一条到边的杠');

      // 「不是纯白」：三个通道都跟着主色走，不是 0xFFFFFFFF。
      expect(top, isNot(Colors.white));
      expect(top.r, closeTo(AppColors.primary.r, 1e-9));
      expect(top.g, closeTo(AppColors.primary.g, 1e-9));
      expect(top.b, closeTo(AppColors.primary.b, 1e-9));
      expect(top.a, lessThan(1.0));
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
              reason: '${preset.label}（dark=$dark）白字对比度 ${ratio.toStringAsFixed(2)}');
          expect(bubble, isNot(Colors.white));
          expect(bubble.a, 1.0, reason: '气泡背景要不透明，底下的照片不能透上来');
          expect(
            AppAccent.relativeLuminance(bubble),
            lessThan(AppAccent.relativeLuminance(primary)),
            reason: '${preset.label}：气泡是主色的深色版，不是原色也不是纯黑',
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
      testWidgets('${entry.$1}：轨道常驻、是渐变不是纯白', (tester) async {
        _phone(tester);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(entry.$2(controller));
        await tester.pumpAndSettle();

        expect(find.byType(PhotoTimelineScrubber), findsOneWidget);
        final track = find.byKey(timelineScrubberTrackKey);
        expect(track, findsOneWidget, reason: '轨道不按键就存在');

        final decoration = _decoration(tester, timelineScrubberTrackKey);
        final gradient = decoration.gradient! as LinearGradient;
        expect(gradient.colors.first.a,
            closeTo(timelineScrubberTrackAlpha, 1e-9));
        expect(gradient.colors.first,
            isNot(Colors.white), reason: '轨道不许是纯白');
        expect(decoration.color, isNull, reason: '轨道只有渐变，没有实色底');
        expect(tester.getSize(track).width, timelineScrubberTrackWidth);
      });

      testWidgets('${entry.$1}：拖拽时滑块是主色、气泡是深色版主色', (tester) async {
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

        await gesture.up();
        await tester.pumpAndSettle();
      });
    }
  });
}