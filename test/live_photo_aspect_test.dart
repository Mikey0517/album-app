import 'package:album_app/core/video_orientation.dart';
import 'package:album_app/features/viewer/corrected_video_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

/// 竖屏拍摄、带 90° 旋转标记的动态视频：纹理尺寸是 1920x1080，
/// 真正该显示的是 9:16（video_player 会用 RotatedBox 把纹理转回来）。
const VideoPlayerValue _rotatedSource = VideoPlayerValue(
  duration: Duration(seconds: 3),
  size: Size(1920, 1080),
  isInitialized: true,
  rotationCorrection: 90,
);

/// 同一张动态照片的静态图按 4:3 铺出来的那一块（1200x900 缩到 360 宽）。
const double _photoWidth = 360;
const double _photoHeight = 270;

void main() {
  test('contain 尺寸按修正后的比例：只缩小不放大，永不溢出', () {
    const photoBox = Size(_photoWidth, _photoHeight);
    final ratio = correctedVideoAspectRatio(_rotatedSource);
    expect(ratio, closeTo(9 / 16, 0.0001),
        reason: '90° 旋转的源要用 aspectRatio 的倒数');

    final fitted = containSizeForAspectRatio(photoBox, ratio);
    expect(fitted.width / fitted.height, closeTo(ratio, 0.0001));
    expect(fitted.height, photoBox.height, reason: '高度顶满');
    expect(fitted.width, lessThan(photoBox.width),
        reason: '按 contain 摆放，不为了填满 4:3 的图片框而拉宽');

    // 容器比视频还扁：只缩小，不溢出。
    final clamped = containSizeForAspectRatio(const Size(600, 200), ratio);
    expect(clamped.width, lessThanOrEqualTo(600));
    expect(clamped.height, lessThanOrEqualTo(200));
    expect(clamped.width / clamped.height, closeTo(ratio, 0.0001));
  });

  testWidgets('旋转 90° 的视频 + 4:3 图片：视频层比例 == 修正后的比例，不拉伸',
      (tester) async {
    await tester.pumpWidget(
      // 播放区就是静态图铺出来的那块 4:3，视频层叠在它上面。
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: _photoWidth,
            height: _photoHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Color(0xFF000000)),
                // 贴纹理的本体（VideoPlayer 里就是一块 Texture）：它永远铺满
                // 父级给的盒子，所以盒子比例错了画面就被拉伸。
                CorrectedVideoLayer(
                  value: _rotatedSource,
                  child: SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final frame = find.byKey(CorrectedVideoLayer.frameKey);
    expect(frame, findsOneWidget);
    final size = tester.getSize(frame);
    final corrected = correctedVideoAspectRatio(_rotatedSource);

    // 渲染出来的比例就是修正后的比例（9:16）。
    expect(size.width / size.height, closeTo(corrected, 0.0001));
    // 不是未修正的 16:9 —— 那正是「被拉伸」的样子。
    expect(size.width / size.height,
        isNot(closeTo(_rotatedSource.aspectRatio, 0.01)));
    // 不撑满、不溢出 4:3 的播放区。
    expect(size.width, lessThanOrEqualTo(_photoWidth));
    expect(size.height, lessThanOrEqualTo(_photoHeight));
    expect(size.height, _photoHeight);
    expect(tester.takeException(), isNull, reason: '不能有 overflow 报错');
  });

  testWidgets('播放区比视频还扁（横屏）时视频层自己缩小，不溢出', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 800,
            height: 220,
            child: CorrectedVideoLayer(
              value: _rotatedSource,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(CorrectedVideoLayer.frameKey));
    expect(size.width / size.height,
        closeTo(correctedVideoAspectRatio(_rotatedSource), 0.0001));
    expect(size.width, lessThanOrEqualTo(800));
    expect(size.height, lessThanOrEqualTo(220));
    expect(size.height, 220);
    expect(tester.takeException(), isNull);
  });
}
