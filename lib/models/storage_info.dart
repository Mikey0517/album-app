class StorageInfo {
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;
  final double usedRatio;

  const StorageInfo({
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
    required this.usedRatio,
  });

  factory StorageInfo.fromJson(Map<String, dynamic> json) {
    final total = (json['total_bytes'] as num?)?.toInt() ?? 0;
    final free = (json['free_bytes'] as num?)?.toInt() ?? 0;
    final used = (json['used_bytes'] as num?)?.toInt() ?? (total - free);
    final ratio = (json['used_ratio'] as num?)?.toDouble() ??
        (total > 0 ? used / total : 0.0);
    return StorageInfo(
      totalBytes: total,
      freeBytes: free,
      usedBytes: used,
      usedRatio: ratio.clamp(0.0, 1.0),
    );
  }
}
