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

  /// 本地文件路径：隐藏空间等「不经过服务器」的媒体用它。
  ///
  /// 有值时取图/放视频一律读本地文件，[url] / [thumbUrl] 不再使用；详情页、
  /// 保存到相册、全屏浏览都能照常工作。
  final String? localPath;

  /// 本地文件是不是动态照片（XMP 探测过）。服务器媒体仍按 [liveVideoUrl] 判断。
  final bool localMotion;

  /// 本地视频的封面图（从视频里抽的第一帧，缓存在临时目录）。相册里的视频
  /// 缩略图来自服务端，本地视频靠它把格子/全屏封面补齐。
  final String? localThumbPath;

  /// 本地图片的安全预览图（HEIC/HEIF/AVIF 先用原生解码成 JPEG）。
  /// 显示永远优先用它；保存到相册仍用 [localPath] 的原文件。
  final String? localPreviewPath;

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
    this.localPath,
    this.localMotion = false,
    this.localThumbPath,
    this.localPreviewPath,
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

  /// 是不是本地文件（隐藏空间导入的那些）。
  bool get isLocal => localPath != null && localPath!.isNotEmpty;

  /// 本地图片的扩展名。
  String get localExtension {
    final path = localPath;
    if (path == null) return '';
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// HEIC/HEIF/AVIF 不能直接交给 `Image.file`（引擎解码会 abort 进程），
  /// 必须先有 [localPreviewPath] 才能显示。
  bool get localImageNeedsPreview =>
      isLocal &&
      !isVideo &&
      const {'heic', 'heif', 'hif', 'heics', 'avif'}.contains(localExtension);

  bool get isVideo => type == 'video';
  bool get isImage => type == 'image';
  bool get isLivePhoto =>
      localMotion || (liveVideoUrl != null && liveVideoUrl!.trim().isNotEmpty);

  /// 没有缩略图时图片回退原图；视频只能显示占位块。
  String? get previewPath {
    if (thumbUrl != null && thumbUrl!.isNotEmpty) return thumbUrl;
    return isVideo ? null : url;
  }
}
