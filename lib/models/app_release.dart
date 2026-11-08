class AppRelease {
  final int versionCode;
  final String versionName;
  final String filename;
  final int fileSize;
  final String sha256;
  final String releaseNotes;
  final String publishedAt;

  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.filename,
    required this.fileSize,
    required this.sha256,
    required this.releaseNotes,
    required this.publishedAt,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    // 后端契约使用驼峰；这里同时兼容 snake_case，避免全局 Jackson 配置变化
    // 导致老版本解析失败。
    return AppRelease(
      versionCode: _asInt(json['versionCode'] ?? json['version_code']),
      versionName:
          (json['versionName'] ?? json['version_name'] ?? '') as String,
      filename: (json['filename'] ?? '') as String,
      fileSize: _asInt(json['fileSize'] ?? json['file_size']),
      sha256: (json['sha256'] ?? '') as String,
      releaseNotes:
          (json['releaseNotes'] ?? json['release_notes'] ?? '') as String,
      publishedAt:
          (json['publishedAt'] ?? json['published_at'] ?? '') as String,
    );
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String get sizeLabel => fileSize <= 0
      ? '大小未知'
      : '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
}
