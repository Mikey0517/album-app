import 'package:album_app/features/viewer/viewer_bottom_controls.dart';
import 'package:album_app/features/viewer/viewer_thumbnail_strip.dart';
import 'package:album_app/models/media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手机横屏与竖屏两种屏幕。
const Size _portraitSize = Size(390, 844);
const Size _landscapeSize = Size(844, 390);

Media _photo(int id) => Media(
      id: id,
      type: 'image',
      thumbUrl: null,
      url: '',
      width: 1920,
      height: 1080,
      durationMs: null,
      takenAt: DateTime(2024, 8, 1),
      createdAt: DateTime(2024, 8, 1),
      postId: null,
    );

Widget _controls() => ViewerVideoControlsLayout(
      position: const Duration(minutes: 1, seconds: 32),
      duration: const Duration(minutes: 3, seconds: 15),
      isPlaying: true,
      onPlayPause: () {},
      onSeek: (_) {},
      onSeekStart: () {},
      onToggleRotation: () {},
    );

Future<void> _useSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 只摆控制条：量进度条宽度与整条高度。
Future<void> _pumpControls(WidgetTester tester, Size size) async {
  await _useSize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Align(alignment: Alignment.bottomCenter, child: _controls()),
      ),
    ),
  );
  await tester.pump();
}

/// 控制条 + 缩略图条按浏览页的方式叠放：缩略图条靠 [viewerThumbnailStripBottom] 定位。
Future<void> _pumpViewerBottom(WidgetTester tester, Size size) async {
  await _useSize(tester, size);
  final landscape = size.width > size.height;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: viewerThumbnailStripBottom(
                landscape: landscape,
                bottomInset: 0,
              ),
              child: ViewerThumbnailStrip(
                items: [for (var i = 0; i < 8; i++) _photo(i + 1)],
                currentIndex: 0,
                onSelected: (_) {},
              ),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _controls()),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('横屏控制条：进度条比竖屏宽、按钮横向排列、不溢出', (tester) async {
    await _pumpControls(tester, _portraitSize);
    expect(tester.takeException(), isNull);
    final portraitBar = tester.getSize(find.byType(ViewerVideoControlsLayout));
    final portraitSlider = tester.getRect(find.byType(Slider));
    expect(portraitBar.height, viewerControlsExtent(landscape: false));

    await _pumpControls(tester, _landscapeSize);
    expect(tester.takeException(), isNull, reason: '844x390 横屏不许溢出');
    final landscapeBar = tester.getSize(find.byType(ViewerVideoControlsLayout));
    final landscapeSlider = tester.getRect(find.byType(Slider));
    expect(
      landscapeBar.height,
      viewerControlsExtent(landscape: true),
      reason: '横屏是另一套版式：行高与上下留白都换过',
    );
    expect(
      landscapeSlider.width,
      greaterThan(portraitSlider.width),
      reason: '横屏进度条横向铺满可用宽度',
    );
    expect(
      landscapeSlider.width,
      greaterThan(_landscapeSize.width * 0.6),
      reason: '横屏进度条不能被两侧按钮挤成窄条',
    );
    // 按钮仍在同一行里左右排开，没有被挤到第二行。
    final row = tester.getRect(find.byKey(viewerControlsRowKey));
    expect(row.height, viewerControlsHeightLandscape);
    expect(
      row.top,
      closeTo(
        _landscapeSize.height -
            viewerControlsHeightLandscape -
            viewerControlsPaddingLandscape,
        0.01,
      ),
    );
    expect(tester.getRect(find.byType(Slider)).center.dy, closeTo(row.center.dy, 4));
  });

  testWidgets('缩略图条贴着进度条：横屏间距 8、竖屏 10，都不压到进度条', (tester) async {
    for (final size in [_landscapeSize, _portraitSize]) {
      await _pumpViewerBottom(tester, size);
      expect(tester.takeException(), isNull);
      final strip = tester.getRect(find.byType(ViewerThumbnailStrip));
      final row = tester.getRect(find.byKey(viewerControlsRowKey));
      // 缩略图条自己有 8 的内边距，真正贴进度条的是图片下沿。
      final thumbBottom = strip.bottom - thumbnailStripVerticalPadding;
      final gap = row.top - thumbBottom;
      expect(gap, lessThanOrEqualTo(12), reason: '$size 间距要收紧到 12 以内');
      expect(gap, greaterThanOrEqualTo(8), reason: '$size 别贴得看不出是两块');
      expect(gap, greaterThan(0), reason: '$size 缩略图不许压住进度条');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  test('缩略图条位置由控制条几何算出，安全区变了间距也不变', () {
    for (final landscape in [true, false]) {
      for (final inset in [0.0, 21.0, 34.0]) {
        final bottom = viewerThumbnailStripBottom(
          landscape: landscape,
          bottomInset: inset,
        );
        final gap = bottom +
            thumbnailStripVerticalPadding -
            viewerControlsRowTop(landscape: landscape, bottomInset: inset);
        expect(gap, lessThanOrEqualTo(12));
        expect(gap, greaterThanOrEqualTo(8));
      }
    }
    // 横屏贴得更紧，竖向预算是全屏高度的零头。
    expect(
      viewerThumbnailGapLandscape,
      lessThan(viewerThumbnailGapPortrait),
    );
  });
}
