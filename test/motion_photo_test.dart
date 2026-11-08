import 'dart:io';

import 'package:album_app/core/motion_photo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects Xiaomi/Google motion photo XMP', () async {
    final dir = await Directory.systemTemp.createTemp('motion_photo_test');
    addTearDown(() => dir.delete(recursive: true));

    final motion = File('${dir.path}/motion.jpg');
    await motion.writeAsBytes([
      ...List<int>.filled(64, 0),
      ...'GCamera:MotionPhoto="1" Item:Semantic="MotionPhoto" Item:Length="100"'
          .codeUnits,
      ...List<int>.filled(64, 0),
    ]);

    final still = File('${dir.path}/still.jpg');
    await still.writeAsBytes([
      ...List<int>.filled(64, 0),
      ...'ordinary jpeg'.codeUnits,
      ...List<int>.filled(64, 0),
    ]);

    expect(await isMotionPhotoFile(motion.path), isTrue);
    expect(await isMotionPhotoFile(still.path), isFalse);
    expect(await isMotionPhotoFile('${dir.path}/missing.jpg'), isFalse);
  });
}
