import 'package:album_app/core/video_orientation.dart';
import 'package:album_app/features/viewer/corrected_video_layer.dart';
import 'package:album_app/features/viewer/live_photo_view.dart';
import 'package:album_app/models/media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

/// 竖着拍的手机短片：编码尺寸 1920x1080，容器里带 90° 旋转标记。
///
/// video_player 上报的 [VideoPlayerValue.size] 已经是**旋转后的显示尺寸**
/// （video_player_android 2.8.4 起用 media3 `VideoSize`，它自己已经算过旋转），
/// 90/270 度的旋转由 [VideoPlayer] 内部的 `RotatedBox` 完成。
/// 所以真正该显示的比例就是 1080/1920 = 9:16，不能再取倒数。
const VideoPlayerValue _rotatedSource = VideoPlayerValue(
  duration: Duration(seconds: 3),
  size: Size(1080, 1920),
  isInitialized: true,
  rotationCorrection: 90,
);

/// 动态照片的静态图是 4:3 时，铺出来的那块矩形（1200x900 缩到 360 宽）。
const double _photoWidth = 360;
const double _photoHeight = 270;

Media _livePhotoMedia() => Media(
      id: 1,
      type: 'image',
      thumbUrl: null,
      url: 'https://example.com/still.jpg',
      // 竖拍的 3:4 静态图（服务端 probe 出来的显示尺寸）。
      width: 3024,
      height: 4032,
      durationMs: null,
      takenAt: DateTime(2026, 1, 1),
      createdAt: DateTime(2026, 1, 1),
      postId: null,
      liveVideoUrl: 'https://example.com/live.mp4',
    );

/// 替身控制器：只改状态、不碰平台通道，让测试能看到「正在播放」这一帧。
class _FakeVideoController extends VideoPlayerController {
  _FakeVideoController(this._initial)
      : super.networkUrl(Uri.parse('https://example.com/live.mp4'));

  final VideoPlayerValue _initial;

  @override
  Future<void> initialize() async {
    value = _initial;
  }

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }
}

void main() {
  test('显示比例用 VideoPlayerValue 的显示尺寸，不再对 90° 取倒数', () {
    expect(videoDisplayAspectRatio(_rotatedSource), closeTo(9 / 16, 0.0001),
        reason: 'size 已经是 1080x1920，取倒数会得到 16:9（盒子被转置）');
    const landscape = VideoPlayerValue(
      duration: Duration(seconds: 3),
      size: Size(1920, 1080),
      isInitialized: true,
    );
    expect(videoDisplayAspectRatio(landscape), closeTo(16 / 9, 0.0001));
    // 尺寸还没上报时兜底成正方形，不返回 0/NaN。
    const unknown = VideoPlayerValue(duration: Duration(seconds: 3));
    expect(videoDisplayAspectRatio(unknown), 1);
  });

  test('contain 尺寸按显示比例：只缩小不放大，永不溢出', () {
    const photoBox = Size(_photoWidth, _photoHeight);
    final ratio = videoDisplayAspectRatio(_rotatedSource);
    expect(ratio, closeTo(9 / 16, 0.0001));

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

  testWidgets('视频层只在静态图那块矩形里 contain，两侧留黑边', (tester) async {
    // iPad 竖屏那种又高又大的播放区：静态图 3:4、短片 9:16。
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Color(0xFF000000)),
            CorrectedVideoLayer(
              value: _rotatedSource,
              frameAspectRatio: 3 / 4,
              child: SizedBox.expand(),
            ),
          ],
        ),
      ),
    );

    final frame = find.byKey(CorrectedVideoLayer.frameKey);
    expect(frame, findsOneWidget);
    final rect = tester.getRect(frame);
    final displayRatio = videoDisplayAspectRatio(_rotatedSource);

    // 比例就是显示比例（9:16），不是转置后的 16:9。
    expect(rect.width / rect.height, closeTo(displayRatio, 0.0001));
    expect(rect.width / rect.height, isNot(closeTo(1 / displayRatio, 0.01)));

    // 静态图 3:4 铺出来 = 1024x1365.33，视频层比它窄，左右各一条黑边。
    final photo = containSizeForAspectRatio(const Size(1024, 1366), 3 / 4);
    expect(rect.height, closeTo(photo.height, 0.01));
    expect(rect.width, lessThan(photo.width));
    final leftBar = rect.left - (1024 - photo.width) / 2;
    final rightBar = (1024 + photo.width) / 2 - rect.right;
    expect(leftBar, greaterThan(1));
    expect(rightBar, closeTo(leftBar, 0.01), reason: '水平居中，两侧黑边等宽');
    expect(tester.takeException(), isNull, reason: '不能有 overflow 报错');
  });

  testWidgets('静态图宽高是旋转前的存储尺寸时，视频框不会被转置', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 360,
            height: 800,
            child: CorrectedVideoLayer(
              value: _rotatedSource,
              // 横着存、靠 EXIF 转回来的静态图：4032x3024。
              frameAspectRatio: 4032 / 3024,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byKey(CorrectedVideoLayer.frameKey));
    // 框仍然是竖的：按 3:4 的静态图算，短片 9:16 在它里面 contain。
    expect(rect.width, lessThan(360), reason: '不能因为宽高颠倒就占满屏宽');
    expect(rect.width / rect.height,
        closeTo(videoDisplayAspectRatio(_rotatedSource), 0.0001));
    expect(rect.height, closeTo(480, 0.01));
    expect(tester.takeException(), isNull);
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
        closeTo(videoDisplayAspectRatio(_rotatedSource), 0.0001));
    expect(size.width, lessThanOrEqualTo(800));
    expect(size.height, lessThanOrEqualTo(220));
    expect(size.height, 220);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真机链路：pump 整个 LivePhotoView，播放中视频层不撑满、两侧留黑边',
      (tester) async {
    // 20:9 手机：1080x2400 物理像素 / 3 = 360x800 逻辑像素。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: LivePhotoView(
            media: _livePhotoMedia(),
            // 不自动播放：测试用点击进入播放，绕开 connectivity 平台通道。
            active: false,
            heroTag: 'live_photo_1',
            onPlayingChanged: (_) {},
            controllerFactory: (_) => _FakeVideoController(_rotatedSource),
          ),
        ),
      ),
    );
    await tester.pump();

    // 还没播放：只有静态图，没有视频层。
    expect(find.byKey(CorrectedVideoLayer.frameKey), findsNothing);

    await tester.tap(find.byType(LivePhotoView));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final frame = find.byKey(CorrectedVideoLayer.frameKey);
    expect(frame, findsOneWidget, reason: '播放中应该叠上视频层');
    final screen = tester.getSize(find.byType(LivePhotoView));
    expect(screen, const Size(360, 800));
    final rect = tester.getRect(frame);
    final displayRatio = videoDisplayAspectRatio(_rotatedSource);

    // 1) 播放中的视频层比例 == 显示比例（9:16），不是转置的 16:9。
    expect(rect.width / rect.height, closeTo(displayRatio, 0.0001));
    expect(rect.width / rect.height, isNot(closeTo(1 / displayRatio, 0.01)));

    // 2) 静态图 3:4 在 360x800 上铺出来是 360x480；视频层在它里面 contain。
    final photo = containSizeForAspectRatio(screen, 3024 / 4032);
    expect(photo.width, closeTo(360, 0.01));
    expect(photo.height, closeTo(480, 0.01));
    expect(rect.width, closeTo(270, 0.01), reason: '480 * 9 / 16');
    expect(rect.height, closeTo(photo.height, 0.01), reason: '高度顶满静态图');

    // 3) 没有撑满播放区：比静态图还窄，左右各留一条黑边且等宽。
    expect(rect.width, lessThan(screen.width));
    expect(rect.width, lessThan(photo.width), reason: '不能比静态图还大');
    final leftBar = rect.left;
    final rightBar = screen.width - rect.right;
    expect(leftBar, greaterThan(1), reason: '左侧留黑边');
    expect(rightBar, greaterThan(1), reason: '右侧留黑边');
    expect(rightBar, closeTo(leftBar, 0.01), reason: '水平居中');
    // 竖直方向也没有越出静态图那块矩形。
    final photoTop = (screen.height - photo.height) / 2;
    final photoBottom = photoTop + photo.height;
    expect(rect.top, greaterThanOrEqualTo(photoTop - 0.01));
    expect(rect.bottom, lessThanOrEqualTo(photoBottom + 0.01));
    expect(tester.takeException(), isNull, reason: '不能有 overflow 报错');

    // 收尾：让 LivePhotoView 走 dispose，别把手定时器留给下一条测试。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
