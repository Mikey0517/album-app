import 'package:album_app/features/viewer/viewer_thumbnail_strip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const itemExtent = thumbnailItemSize + thumbnailItemGap; // 44

  test('打开的图片不在屏幕内时，滚到中间', () {
    final target = thumbnailScrollTarget(
      index: 15,
      currentOffset: 0,
      viewportWidth: 360,
      maxScrollExtent: 2000,
    );
    const itemStart = thumbnailStripPadding + 15 * itemExtent;
    expect(target, isNotNull);
    // 缩略图中心应落在视口中心附近。
    expect(target! + 360 / 2, closeTo(itemStart + thumbnailItemSize / 2, 0.6));
  });

  test('已经完整可见的缩略图不再滚动', () {
    final target = thumbnailScrollTarget(
      index: 2,
      currentOffset: 0,
      viewportWidth: 360,
      maxScrollExtent: 2000,
    );
    expect(target, isNull);
  });

  test('靠近末尾时收敛到最大滚动距离', () {
    final target = thumbnailScrollTarget(
      index: 49,
      currentOffset: 0,
      viewportWidth: 360,
      maxScrollExtent: 120,
    );
    expect(target, 120);
  });

  test('列表很短时不需要滚动', () {
    final target = thumbnailScrollTarget(
      index: 2,
      currentOffset: 0,
      viewportWidth: 360,
      maxScrollExtent: 0,
    );
    expect(target, isNull);
  });
}
