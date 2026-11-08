import 'package:album_app/core/ai_media_targets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('3 个以内原样返回', () {
    expect(pickAiTargets([1]), [1]);
    expect(pickAiTargets([1, 2, 3]), [1, 2, 3]);
    expect(pickAiTargets(<int>[]), isEmpty);
  });

  test('9 个文件取首中尾三张代表', () {
    expect(pickAiTargets([1, 2, 3, 4, 5, 6, 7, 8, 9]), [1, 5, 9]);
  });

  test('4~8 个均匀取样，包含首尾且不重复', () {
    for (var n = 4; n <= 8; n++) {
      final picked = pickAiTargets(List<int>.generate(n, (i) => i));
      expect(picked.length, 3, reason: 'n=$n');
      expect(picked.first, 0, reason: 'n=$n');
      expect(picked.last, n - 1, reason: 'n=$n');
      expect(picked.toSet().length, picked.length, reason: 'n=$n');
    }
  });
}
