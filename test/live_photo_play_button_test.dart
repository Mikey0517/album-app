import 'package:album_app/features/viewer/live_photo_view.dart';
import 'package:album_app/models/media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Media _live({bool withVideo = true}) => Media(
      id: 1,
      type: 'image',
      thumbUrl: null,
      url: 'https://example.test/1.jpg',
      width: 1920,
      height: 1080,
      durationMs: null,
      takenAt: DateTime(2024, 8, 1),
      createdAt: DateTime(2024, 8, 1),
      postId: null,
      liveVideoUrl: withVideo ? 'https://example.test/1.mp4' : null,
    );

const Size _phone = Size(390, 844);
const double _safeBottom = 48;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpView(
    WidgetTester tester, {
    required Media media,
    bool uiVisible = true,
    double bottomClearance = 0,
  }) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      MaterialApp(
        home: LivePhotoView(
          media: media,
          active: false,
          heroTag: 'h',
          uiVisible: uiVisible,
          bottomClearance: bottomClearance,
          onPlayingChanged: (_) {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('动态照片右下角有圆形播放按钮，贴右 16、让开底部安全区', (tester) async {
    await pumpView(tester, media: _live());

    final button = find.byKey(livePhotoPlayButtonKey);
    expect(button, findsOneWidget);
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.play_arrow_rounded),
      ),
      findsOneWidget,
      reason: '圆圈里是一个播放箭头',
    );

    final rect = tester.getRect(button);
    expect(rect.size, const Size(48, 48));
    expect(rect.right, _phone.width - livePhotoPlayButtonInset);
    expect(
      rect.bottom,
      _phone.height - livePhotoPlayButtonInset - _safeBottom,
      reason: '底部安全区 48 要让开，不能压在导航条上',
    );
  });

  testWidgets('底部有缩略图条时按钮浮到它上面', (tester) async {
    await pumpView(tester, media: _live(), bottomClearance: 56);
    final rect = tester.getRect(find.byKey(livePhotoPlayButtonKey));
    expect(
      rect.bottom,
      _phone.height - livePhotoPlayButtonInset - 56 - _safeBottom,
    );
  });

  testWidgets('控制层隐藏时按钮跟着淡出，也不再吃点击', (tester) async {
    await pumpView(tester, media: _live(), uiVisible: false);

    // 最近的祖先才是我们这一层（图片渐显也是一层 AnimatedOpacity）。
    final fade = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byKey(livePhotoPlayButtonKey),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(fade.opacity, 0);
    final ignore = tester.widget<IgnorePointer>(
      find
          .ancestor(
            of: find.byKey(livePhotoPlayButtonKey),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(ignore.ignoring, isTrue);
  });

  testWidgets('没有内嵌动态视频的普通照片没有这个按钮', (tester) async {
    await pumpView(tester, media: _live(withVideo: false));
    expect(find.byKey(livePhotoPlayButtonKey), findsNothing);
  });

  testWidgets('点按钮走的还是同一条播放路径（不会抛异常）', (tester) async {
    await pumpView(tester, media: _live());
    await tester.tap(find.byKey(livePhotoPlayButtonKey));
    await tester.pump();
    // 测试环境没有 video_player 平台实现：初始化失败要被吞掉，按钮留着可重试。
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(livePhotoPlayButtonKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
