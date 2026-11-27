import 'package:album_app/core/local_image_preview.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/widgets/album_thumb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HEIC/HEIF/AVIF 需要先转 JPEG，其它格式直接显示', () {
    expect(LocalImagePreview.isSafeForFlutter('/a/IMG_1.HEIC'), isFalse);
    expect(LocalImagePreview.isSafeForFlutter('/a/IMG_1.heif'), isFalse);
    expect(LocalImagePreview.isSafeForFlutter('/a/IMG_1.avif'), isFalse);
    expect(LocalImagePreview.isSafeForFlutter('/a/IMG_1.jpg'), isTrue);
    expect(LocalImagePreview.isSafeForFlutter('/a/IMG_1.png'), isTrue);
    expect(LocalImagePreview.isSafeForFlutter('/a/noext'), isTrue);
  });

  test('Media 能判断本地图是不是必须先有预览', () {
    Media media(String path) => Media(
          id: 1,
          type: 'image',
          thumbUrl: null,
          url: '',
          width: null,
          height: null,
          durationMs: null,
          takenAt: DateTime(2026),
          createdAt: DateTime(2026),
          postId: null,
          originalFormat: 'heic',
          fileSize: 1,
          localPath: path,
        );
    // 现在所有本地图片都先走 JPEG 预览（大图直接解会 OOM abort）。
    expect(media('/x/a.heic').localImageNeedsPreview, isTrue);
    expect(media('/x/a.jpg').localImageNeedsPreview, isTrue);
  });

  testWidgets('HEIC 没预览时格子显示占位，不会去解码原文件', (tester) async {
    final media = Media(
      id: 1,
      type: 'image',
      thumbUrl: null,
      url: '',
      width: null,
      height: null,
      durationMs: null,
      takenAt: DateTime(2026),
      createdAt: DateTime(2026),
      postId: null,
      originalFormat: 'heic',
      fileSize: 1,
      localPath: '/tmp/not-exists.heic',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(
          width: 100,
          height: 100,
          child: AlbumThumb(media: media),
        ))),
      ),
    );
    expect(find.byType(Image), findsNothing);
  });
}
