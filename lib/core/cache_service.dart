import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'media_cache.dart';

/// 缓存涉及的两个目录。
class CacheDirs {
  /// 临时目录：图片缓存、动图临时文件、分享/下载/更新包。
  final String tempDir;

  /// 待上传副本（不是缓存，清理时绝对不能删）。
  final String uploadsDir;

  const CacheDirs({required this.tempDir, required this.uploadsDir});
}

/// 一次统计的结果，单位字节。
class CacheUsage {
  /// 图片磁盘缓存（含旧版默认缓存目录）。
  final int imageBytes;

  /// 临时文件：动图提取、分享、下载、更新包等。
  final int tempBytes;

  /// 待上传副本，不计入可清理。
  final int pendingUploadBytes;

  const CacheUsage({
    required this.imageBytes,
    required this.tempBytes,
    required this.pendingUploadBytes,
  });

  static const CacheUsage empty = CacheUsage(
    imageBytes: 0,
    tempBytes: 0,
    pendingUploadBytes: 0,
  );

  int get clearableBytes => imageBytes + tempBytes;

  bool get isEmpty => clearableBytes == 0;
}

class CacheClearResult {
  final int freedBytes;

  const CacheClearResult(this.freedBytes);
}

/// 缓存统计与清理。
///
/// 设计要点：
/// - 只清理「可再生」的数据：图片缓存、临时文件；
/// - 待上传副本（`picked_media`）属于用户数据，永不在这里删除；
/// - 正在下载更新包时跳过 `album_updates`，避免把安装包删掉；
/// - 启动时按预算裁剪图片缓存、清理过期临时文件。
class CacheService {
  CacheService._();

  @visibleForTesting
  static Future<CacheDirs> Function()? dirsOverride;

  /// 更新包正在下载时置为 true，清理缓存会跳过 `album_updates`。
  static bool updating = false;

  /// 临时文件保留时长，超过后启动时清理。
  static const Duration tempMaxAge = Duration(days: 7);

  /// 启动裁剪用的上限，测试可改小。
  @visibleForTesting
  static int maxImageBytes = MediaCache.maxBytes;

  @visibleForTesting
  static int keepImageBytes = MediaCache.keepBytes;

  static Future<CacheDirs> _dirs() async {
    if (dirsOverride != null) return dirsOverride!();
    final temp = await getTemporaryDirectory();
    final docs = await getApplicationDocumentsDirectory();
    return CacheDirs(
      tempDir: temp.path,
      uploadsDir: '${docs.path}/picked_media',
    );
  }

  static Future<CacheUsage> measure() async {
    try {
      final dirs = await _dirs();
      final imageBytes = await _dirSize([
        '${dirs.tempDir}/${MediaCache.cacheKey}',
        '${dirs.tempDir}/${MediaCache.legacyCacheKey}',
      ]);
      var tempBytes = 0;
      for (final entity in await _topLevel(dirs.tempDir)) {
        final name = _basename(entity.path);
        if (name == MediaCache.cacheKey || name == MediaCache.legacyCacheKey) {
          continue;
        }
        tempBytes += await _sizeOf(entity);
      }
      final uploadBytes = await _dirSize([dirs.uploadsDir]);
      return CacheUsage(
        imageBytes: imageBytes,
        tempBytes: tempBytes,
        pendingUploadBytes: uploadBytes,
      );
    } catch (_) {
      return CacheUsage.empty;
    }
  }

  /// 清理图片缓存与临时文件，返回释放的字节数。
  static Future<CacheClearResult> clear() async {
    final before = await measure();
    try {
      final dirs = await _dirs();
      await _deleteDir('${dirs.tempDir}/${MediaCache.cacheKey}');
      await _deleteDir('${dirs.tempDir}/${MediaCache.legacyCacheKey}');
      // 让缓存管理器把索引库一起重置（失败不影响已经删掉的文件）。
      // 测试环境注入目录时跳过：插件不可用会产生未处理的异步异常。
      if (dirsOverride == null) {
        try {
          await MediaCache.manager.emptyCache();
        } catch (_) {
          // 忽略。
        }
      }
      for (final entity in await _topLevel(dirs.tempDir)) {
        final name = _basename(entity.path);
        if (name == MediaCache.cacheKey || name == MediaCache.legacyCacheKey) {
          continue;
        }
        if (name == 'picked_media') continue;
        if (name == 'album_updates' && updating) continue;
        await _deleteEntity(entity);
      }
    } catch (_) {
      // 清理失败时返回已经释放的部分。
    }
    final after = await measure();
    final freed = before.clearableBytes - after.clearableBytes;
    return CacheClearResult(freed > 0 ? freed : 0);
  }

  /// 启动时调用：裁剪超预算的图片缓存，清掉过期临时文件。
  static Future<void> trimIfNeeded() async {
    try {
      final dirs = await _dirs();
      await _pruneOldTemp(dirs);
      final imageDir = Directory('${dirs.tempDir}/${MediaCache.cacheKey}');
      final bytes = await _sizeOf(imageDir);
      if (bytes > maxImageBytes) {
        await _trimToLimit(imageDir, keepImageBytes);
      }
      await _deleteDir('${dirs.tempDir}/${MediaCache.legacyCacheKey}');
    } catch (_) {
      // 裁剪失败不影响使用。
    }
  }

  static Future<void> _pruneOldTemp(CacheDirs dirs) async {
    final cutoff = DateTime.now().subtract(tempMaxAge);
    for (final entity in await _topLevel(dirs.tempDir)) {
      final name = _basename(entity.path);
      if (name == MediaCache.cacheKey ||
          name == MediaCache.legacyCacheKey ||
          name == 'picked_media' ||
          (name == 'album_updates' && updating)) {
        continue;
      }
      if (await _isOld(entity, cutoff)) {
        await _deleteEntity(entity);
      }
    }
  }

  /// 文件看修改时间；目录看里面最新的文件，避免把还在用的分享/下载目录删掉。
  static Future<bool> _isOld(FileSystemEntity entity, DateTime cutoff) async {
    try {
      if (entity is File) {
        return (await entity.stat()).modified.isBefore(cutoff);
      }
      if (entity is Directory) {
        var hasFile = false;
        var newest = DateTime.fromMillisecondsSinceEpoch(0);
        await for (final item
            in entity.list(recursive: true, followLinks: false)) {
          if (item is! File) continue;
          hasFile = true;
          final modified = (await item.stat()).modified;
          if (modified.isAfter(newest)) newest = modified;
        }
        if (!hasFile) return (await entity.stat()).modified.isBefore(cutoff);
        return newest.isBefore(cutoff);
      }
    } catch (_) {
      // 读不到就当作不旧，宁可留着。
    }
    return false;
  }

  static Future<void> _trimToLimit(Directory dir, int keepBytes) async {
    final files = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    final entries = <({File file, DateTime modified, int size})>[];
    for (final entity in files) {
      try {
        final stat = await entity.stat();
        entries.add((file: entity, modified: stat.modified, size: stat.size));
      } catch (_) {
        // 忽略无法 stat 的文件。
      }
    }
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.size);
    for (final entry in entries) {
      if (total <= keepBytes) break;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (_) {
        // 删除失败就继续尝试下一个。
      }
    }
  }

  static Future<List<FileSystemEntity>> _topLevel(String dir) async {
    final directory = Directory(dir);
    if (!await directory.exists()) return const [];
    final result = <FileSystemEntity>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        result.add(entity);
      }
    } catch (_) {
      // 目录不可读时当作空。
    }
    return result;
  }

  static Future<int> _dirSize(List<String> paths) async {
    var total = 0;
    for (final path in paths) {
      total += await _sizeOf(Directory(path));
    }
    return total;
  }

  static Future<int> _sizeOf(FileSystemEntity entity) async {
    try {
      if (entity is File) return (await entity.stat()).size;
      if (entity is Directory) {
        var total = 0;
        await for (final item
            in entity.list(recursive: true, followLinks: false)) {
          if (item is File) {
            try {
              total += (await item.stat()).size;
            } catch (_) {
              // 单个文件失败跳过。
            }
          }
        }
        return total;
      }
      if (entity is Link) return 0;
    } catch (_) {
      // 不存在或不可读。
    }
    return 0;
  }

  static Future<void> _deleteDir(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // 忽略删除失败。
    }
  }

  static Future<void> _deleteEntity(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: true);
    } catch (_) {
      // 忽略删除失败。
    }
  }

  static String _basename(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? path : path.substring(index + 1);
  }
}
