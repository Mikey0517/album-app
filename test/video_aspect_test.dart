import 'dart:ui';

import 'package:album_app/core/video_orientation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

void main() {
  test('rotation metadata swaps video aspect ratio', () {
    const normal = VideoPlayerValue(
      duration: Duration(seconds: 1),
      size: Size(1920, 1080),
      isInitialized: true,
    );
    const rotated = VideoPlayerValue(
      duration: Duration(seconds: 1),
      size: Size(1920, 1080),
      isInitialized: true,
      rotationCorrection: 90,
    );
    expect(correctedVideoAspectRatio(normal), closeTo(16 / 9, 0.001));
    expect(correctedVideoAspectRatio(rotated), closeTo(9 / 16, 0.001));
  });
}
