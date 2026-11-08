/// 从一组媒体里挑出最多 [max] 个代表送给 AI：均匀取首、中、尾，
/// 这样选了 9 个文件时也能概括整组的氛围，而 token 只花 3 张的量。
List<T> pickAiTargets<T>(List<T> items, {int max = 3}) {
  if (items.isEmpty || max <= 0) return <T>[];
  if (items.length <= max) return List<T>.of(items);
  if (max == 1) return <T>[items.first];

  final result = <T>[];
  for (var i = 0; i < max; i++) {
    final index = ((items.length - 1) * i / (max - 1)).round();
    final candidate = items[index];
    if (result.isEmpty || !identical(result.last, candidate)) {
      result.add(candidate);
    }
  }
  return result;
}
