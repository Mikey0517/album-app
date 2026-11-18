import 'package:album_app/features/viewer/video_view.dart';
import 'package:album_app/models/media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

const Duration _duration = Duration(seconds: 3);
const Size _size = Size(1920, 1080);
const Duration _middle = Duration(milliseconds: 900);

Media _videoMedia() => Media(
      id: 1,
      type: 'video',
      thumbUrl: null,
      url: 'https://example.com/v.mp4',
      width: 1920,
      height: 1080,
      durationMs: 3000,
      takenAt: DateTime(2026, 1, 1),
      createdAt: DateTime(2026, 1, 1),
      postId: null,
    );

/// 播放中的值。[buffering] 用来摆出「真的在等数据」这一帧。
VideoPlayerValue _playing({bool buffering = false}) => VideoPlayerValue(
      duration: _duration,
      size: _size,
      isInitialized: true,
      position: _middle,
      isPlaying: true,
      isBuffering: buffering,
    );

/// 播完那一帧：video_player 收到 completed 事件时会 pause + seek 到 duration，
/// 平台随之报一次 bufferingStart —— 真机上就是「转圈闪一下」的来源。
const VideoPlayerValue _completed = VideoPlayerValue(
  duration: _duration,
  size: _size,
  isInitialized: true,
  position: _duration,
  isCompleted: true,
  isBuffering: true,
);

/// 替身控制器：只改状态、不碰平台通道。
class _FakeVideoController extends VideoPlayerController {
  _FakeVideoController(this._initial)
      : super.networkUrl(Uri.parse('https://example.com/v.mp4'));

  final VideoPlayerValue _initial;

  @override
  Future<void> initialize() async {
    value = _initial;
  }

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true, isCompleted: false);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  /// 真机 seek 会发一次 bufferingStart；这里照做，看控件会不会误报。
  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(
      position: position,
      isCompleted: position >= value.duration,
      isBuffering: true,
    );
  }

  /// 让测试直接推进到某个状态（播完、缓冲开始/结束）。
  void emit(VideoPlayerValue next) => value = next;
}

Widget _viewer({
  required VideoPlayerController Function(Uri) factory,
  bool active = true,
}) =>
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: VideoView(
          media: _videoMedia(),
          active: active,
          uiVisible: true,
          heroTag: 'media_1',
          onToggleUi: () {},
          onUserInteraction: () {},
          onPlayingChanged: (_) {},
          controllerFactory: factory,
        ),
      ),
    );

/// 收尾：让 VideoView 走 dispose，别把 250ms 的手定时器留给下一条用例。
Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  test('缓冲指示器的判据：播完、重播 seek 窗口内都不该转圈', () {
    expect(
      shouldShowVideoBuffering(_playing(buffering: true),
          error: false, ended: false, suppressed: false),
      isTrue,
      reason: '真的在等数据时要转',
    );
    expect(
      shouldShowVideoBuffering(_playing(),
          error: false, ended: false, suppressed: false),
      isFalse,
      reason: '没在缓冲就不转',
    );
    expect(
      shouldShowVideoBuffering(_completed,
          error: false, ended: false, suppressed: false),
      isFalse,
      reason: 'isCompleted 时平台那次 seek 的 buffering 不是等待',
    );
    expect(
      shouldShowVideoBuffering(_completed,
          error: false, ended: true, suppressed: false),
      isFalse,
      reason: '停在最后一帧时任何 buffering 都不算等待',
    );
    expect(
      shouldShowVideoBuffering(_playing(buffering: true),
          error: false, ended: false, suppressed: true),
      isFalse,
      reason: '重播 seek 的 400ms 窗口内屏蔽',
    );
    expect(
      shouldShowVideoBuffering(_playing(buffering: true),
          error: true, ended: false, suppressed: false),
      isFalse,
      reason: '出错时走错误态，不叠转圈',
    );
  });

  testWidgets('播完停在最后一帧：不出现 CircularProgressIndicator', (tester) async {
    late _FakeVideoController controller;
    await tester.pumpWidget(
      _viewer(factory: (_) => controller = _FakeVideoController(_playing())),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '初始化完成后不该有转圈');

    controller.emit(_completed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'isCompleted = true 时不得显示 buffering 指示器');
    expect(find.byIcon(Icons.replay_rounded), findsOneWidget,
        reason: '停在静止帧，只有重播按钮');
    await _tearDown(tester);
  });

  testWidgets('结束 → 重播的过渡期间不出现 loading', (tester) async {
    late _FakeVideoController controller;
    await tester.pumpWidget(
      _viewer(factory: (_) => controller = _FakeVideoController(_playing())),
    );
    await tester.pump();
    controller.emit(_completed);
    await tester.pump();
    expect(find.byIcon(Icons.replay_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.replay_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.value.position, Duration.zero, reason: '重播先 seek 回 0');
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'seek 引起的 buffering 不是等待，窗口内不转圈');

    // 窗口（400ms）过去后仍在缓冲：那才是真的在等数据。
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: '屏蔽只是短窗口，持续缓冲要如实显示');
    await _tearDown(tester);
  });

  testWidgets('控制条的播放键从末尾拉起播放：同样不闪 loading', (tester) async {
    late _FakeVideoController controller;
    await tester.pumpWidget(
      _viewer(factory: (_) => controller = _FakeVideoController(_playing())),
    );
    await tester.pump();
    controller.emit(_completed);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '控制条 seek 回 0 的这次 buffering 也要屏蔽');
    await _tearDown(tester);
  });

  testWidgets('真实播放中的缓冲仍然显示 loading', (tester) async {
    late _FakeVideoController controller;
    await tester.pumpWidget(
      _viewer(factory: (_) => controller = _FakeVideoController(_playing())),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    controller.emit(_playing(buffering: true));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: '没播完、真的在缓冲：功能不能被修没了');

    controller.emit(_playing());
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '缓冲结束就收');
    await _tearDown(tester);
  });
}
