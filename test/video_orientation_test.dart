import 'package:album_app/core/video_orientation.dart';
import 'package:album_app/models/media.dart';
import 'package:flutter_test/flutter_test.dart';

Media _video({int? width, int? height}) {
  return Media(
    id: 1,
    type: 'video',
    thumbUrl: null,
    url: '/files/a.mp4',
    width: width,
    height: height,
    durationMs: 3000,
    takenAt: DateTime(2026, 1, 1),
    createdAt: DateTime(2026, 1, 1),
    postId: null,
  );
}

void main() {
  test('横屏视频按横屏打开', () {
    expect(isLandscapeVideo(_video(width: 1920, height: 1080)), isTrue);
  });

  test('竖屏视频按竖屏打开', () {
    expect(isLandscapeVideo(_video(width: 1080, height: 1920)), isFalse);
  });

  test('没有宽高信息时按横屏处理', () {
    expect(isLandscapeVideo(_video()), isTrue);
  });
}
