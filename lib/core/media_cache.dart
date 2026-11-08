import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// App 内所有网络图片共用的磁盘缓存。
///
/// 缓存目录：`<临时目录>/album_image_cache`（flutter_cache_manager 管理）。
/// 除了条数上限，还按字节预算在启动时裁剪，避免在存储紧张的手机上越滚越大。
class MediaCache {
  MediaCache._();

  static const String cacheKey = 'album_image_cache';

  /// 超过这个大小就在启动时按时间从旧到新裁剪。
  static const int maxBytes = 320 * 1024 * 1024;

  /// 裁剪到这个大小为止（留出滞后区间，避免每次启动都反复删）。
  static const int keepBytes = 240 * 1024 * 1024;

  static final CacheManager manager = CacheManager(
    Config(
      cacheKey,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 800,
    ),
  );

  /// 1.2.49 之前用的默认缓存目录，清理时一并删掉。
  static const String legacyCacheKey = 'libCachedImageData';
}
