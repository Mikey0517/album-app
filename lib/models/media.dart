class Media {
  final int id;
  final String type;
  final String? thumbUrl;
  final String url;
  final int? width;
  final int? height;
  final int? durationMs;
  final DateTime takenAt;
  final DateTime createdAt;
  final int? postId;
  final String? liveVideoUrl;
  final String? originalFormat;
  final bool thumbFailed;
  final bool favorite;
  /// 原图 EXIF 里的 GPS 坐标，没有就是 null。
  final double? latitude;
  final double? longitude;
  /// 原文件的字节数，服务端只对新上传的文件填充。
  final int? fileSize;

  const Media({
    required this.id,
    required this.type,
    required this.thumbUrl,
    required this.url,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.takenAt,
    required this.createdAt,
    required this.postId,
    this.liveVideoUrl,
    this.originalFormat,
    this.thumbFailed = false,
    this.favorite = false,
    this.latitude,
    this.longitude,
    this.fileSize,
  });

  factory Media.fromJson(Map<String, dynamic> json) {
    return Media(
      id: (json['id'] as num).toInt(),
      type: json['type'] as String? ?? 'image',
      thumbUrl: json['thumb_url'] as String?,
      url: json['url'] as String? ?? '',
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      takenAt: DateTime.tryParse(json['taken_at'] as String? ?? '') ??
          DateTime.now(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.tryParse(json['taken_at'] as String? ?? '') ??
          DateTime.now(),
      postId: (json['post_id'] as num?)?.toInt(),
      liveVideoUrl: json['live_video_url'] as String?,
      originalFormat: json['original_format'] as String?,
      thumbFailed: json['thumb_failed'] as bool? ?? false,
      favorite: json['favorite'] as bool? ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      fileSize: (json['file_size'] as num?)?.toInt(),
    );
  }

  bool get isVideo => type == 'video';
  bool get isImage => type == 'image';
  bool get isLivePhoto =>
      liveVideoUrl != null && liveVideoUrl!.trim().isNotEmpty;

  /// 没有缩略图时图片回退原图；视频只能显示占位块。
  String? get previewPath {
    if (thumbUrl != null && thumbUrl!.isNotEmpty) return thumbUrl;
    return isVideo ? null : url;
  }
}
