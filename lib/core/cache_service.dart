import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'media_cache.dart';

/// 统计涉及的 App 私有目录。
class CacheDirs {
  /// 临时目录（系统缓存目录）：图片缓存、动图临时文件、分享/下载/更新包。
  final String tempDir;

  /// 文档目录：`picked_media/` 待上传副本等。
  final String docsDir;

  /// 另一个私有目录；Android 上是应用数据里的 `files`，iOS 上不同。
  final String? supportDir;

  const CacheDirs({
    required this.tempDir,
    required this.docsDir,
    this.supportDir,
  });

  /// 待上传副本目录（不是缓存，清理时绝对不能删）。
  String get uploadsDir => '$docsDir/picked_media';
}

/// 一次统计的结果，单位字节。
///
/// 原来的「其他」大杂烩拆成五个子项：[updateBytes]、[shareBytes]、
/// [appDataBytes]、[programBytes]、[residueBytes]，每项在「存储空间」页单独占一行。
class CacheUsage {
  /// 图片磁盘缓存（含旧版默认缓存目录）。
  final int imageBytes;

  /// 临时文件：动图提取等临时产物（更新包、分享/导出单独统计）。
  final int tempBytes;

  /// 待上传副本（`picked_media/`），不是缓存，不计入可清理。
  final int pendingUploadBytes;

  /// 待上传副本的条数。
  final int pendingUploadCount;

  /// 更新包：下载到 `<临时目录>/album_updates/` 的 APK。
  final int updateBytes;

  /// 分享/导出临时文件：`album_share_*` 目录与 `familyalbum_*` 中间文件。
  final int shareBytes;

  /// 应用数据：`databases`、`shared_prefs`、`files`，不可清理。
  final int appDataBytes;

  /// 程序本体估算（安装包 / .app）。
  final int programBytes;

  /// 其它残留：以上都对不上的私有目录剩余部分。
  final int residueBytes;

  const CacheUsage({
    required this.imageBytes,
    required this.tempBytes,
    required this.pendingUploadBytes,
    required this.pendingUploadCount,
    required this.updateBytes,
    required this.shareBytes,
    required this.appDataBytes,
    required this.programBytes,
    required this.residueBytes,
  });

  static const CacheUsage empty = CacheUsage(
    imageBytes: 0,
    tempBytes: 0,
    pendingUploadBytes: 0,
    pendingUploadCount: 0,
    updateBytes: 0,
    shareBytes: 0,
    appDataBytes: 0,
    programBytes: 0,
    residueBytes: 0,
  );

  /// 「其他」小计：五个子项之和。
  int get otherBytes =>
      updateBytes + shareBytes + appDataBytes + programBytes + residueBytes;

  /// 可清理的分项：图片缓存、临时文件、更新包、分享/导出临时文件、其它残留。
  int get clearableBytes =>
      imageBytes + tempBytes + updateBytes + shareBytes + residueBytes;

  /// App 在本机的总占用：所有分项之和。
  int get appBytes =>
      imageBytes + tempBytes + pendingUploadBytes + otherBytes;

  bool get isEmpty => clearableBytes == 0;
}

class CacheClearResult {
  final int freedBytes;

  const CacheClearResult(this.freedBytes);
}

/// 存储统计与清理。
///
/// 设计要点：
/// - 只自动清理「可再生」的数据：图片缓存、临时文件、更新包、分享/导出临时文件；
/// - 待上传副本（`picked_media`）属于用户数据，永不在这里删除；
/// - 应用数据（`databases`/`shared_prefs`/`files`）与程序本体只统计、不删；
/// - 正在下载更新包时跳过 `album_updates`，避免把安装包删掉；
/// - 「其它残留」保守清理：只删空目录与已知可再生的临时命名，拿不准的一律留着；
/// - 启动时按预算裁剪图片缓存、清理过期临时文件。
class CacheService {
  CacheService._();

  @visibleForTesting
  static Future<CacheDirs> Function()? dirsOverride;

  /// 程序本体估算，测试可替换。
  @visibleForTesting
  static int Function()? programBytesOverride;

  /// 读不到安装包时的估值：Flutter 引擎 + Dart 代码 + 资源大致几十 MB。
  static const int fallbackProgramBytes = 60 * 1024 * 1024;

  /// 更新包正在下载时置为 true，清理缓存会跳过 `album_updates`。
  static bool updating = false;

  /// 临时文件保留时长，超过后启动时清理。
  static const Duration tempMaxAge = Duration(days: 7);

  /// 启动裁剪用的上限，测试可改小。
  @visibleForTesting
  static int maxImageBytes = MediaCache.maxBytes;

  @visibleForTesting
  static int keepImageBytes = MediaCache.keepBytes;

  /// 待上传副本目录名（临时目录里可能还留着 1.2.48 之前的旧副本）。
  static const String pendingDirName = 'picked_media';

  /// 更新包目录名：`update_service.dart` 把 APK 下到这里。
  static const String updateDirName = 'album_updates';

  /// 分享/导出临时目录前缀（`media_share_service.dart`）。
  static const String shareDirPrefix = 'album_share_';

  /// 保存到相册时下载的中间文件前缀（`media_download_service.dart`）。
  static const String downloadFilePrefix = 'familyalbum_';

  /// 动图提取的临时目录（`motion_photo.dart`）。
  static const String motionDirName = 'motion_photos';

  /// Android 文档目录名（`<应用数据>/app_flutter`）。
  static const String docsDirName = 'app_flutter';

  /// 应用数据目录名，位于文档目录的同级，不可清理。
  static const List<String> appDataDirNames = [
    'databases',
    'shared_prefs',
    'files',
  ];

  static Future<CacheDirs> _dirs() async {
    if (dirsOverride != null) return dirsOverride!();
    final temp = await getTemporaryDirectory();
    final docs = await getApplicationDocumentsDirectory();
    String? support;
    try {
      support = (await getApplicationSupportDirectory()).path;
    } catch (_) {
      // 桌面/测试环境可能没有该插件。
    }
    return CacheDirs(
      tempDir: temp.path,
      docsDir: docs.path,
      supportDir: support,
    );
  }

  static Future<CacheUsage> measure() async {
    try {
      final dirs = await _dirs();
      final imageBytes = await _dirSize([
        '${dirs.tempDir}/${MediaCache.cacheKey}',
        '${dirs.tempDir}/${MediaCache.legacyCacheKey}',
      ]);
      final pendingDirs = _unique([
        dirs.uploadsDir,
        '${dirs.tempDir}/$pendingDirName',
      ]);
      var pendingBytes = 0;
      var pendingCount = 0;
      for (final path in pendingDirs) {
        final stats = await _dirStats(path);
        pendingBytes += stats.bytes;
        pendingCount += stats.count;
      }
      var tempBytes = 0;
      var updateBytes = 0;
      var shareBytes = 0;
      for (final entity in await _topLevel(dirs.tempDir)) {
        final name = _basename(entity.path);
        if (name == MediaCache.cacheKey ||
            name == MediaCache.legacyCacheKey ||
            name == pendingDirName) {
          continue;
        }
        final bytes = await _sizeOf(entity);
        if (name == updateDirName) {
          updateBytes += bytes;
        } else if (_isShareTemp(name)) {
          shareBytes += bytes;
        } else {
          tempBytes += bytes;
        }
      }
      final appDataBytes = await _appDataBytes(dirs);
      final programBytes = await _programBytes();
      final privateBytes = await _privateBytes(dirs);
      final known = imageBytes + pendingBytes + updateBytes + shareBytes + tempBytes;
      final residue = privateBytes - known;
      return CacheUsage(
        imageBytes: imageBytes,
        tempBytes: tempBytes,
        pendingUploadBytes: pendingBytes,
        pendingUploadCount: pendingCount,
        updateBytes: updateBytes,
        shareBytes: shareBytes,
        appDataBytes: appDataBytes,
        programBytes: programBytes,
        residueBytes: residue > 0 ? residue : 0,
      );
    } catch (_) {
      return CacheUsage.empty;
    }
  }

  /// 清理所有标记为可清理的分项，返回释放的字节数。
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
        if (name == pendingDirName) continue;
        if (name == updateDirName && updating) continue;
        await _deleteEntity(entity);
      }
      await clearResidue(await _residuePaths(dirs));
    } catch (_) {
      // 清理失败时返回已经释放的部分。
    }
    final after = await measure();
    final freed = before.clearableBytes - after.clearableBytes;
    return CacheClearResult(freed > 0 ? freed : 0);
  }

  /// 删除 [paths] 里确认可再生的「其它残留」，返回删除的字节数。
  ///
  /// 只认两种：已知可再生的临时命名（分享/导出中间文件、动图临时目录）与空目录。
  /// 未知文件、非空且名字不认识的目录一律保留；已知分项（图片缓存、待上传副本、
  /// 更新包）也不走这里，各自有自己的清理路径。
  static Future<int> clearResidue(Iterable<String> paths) async {
    var freed = 0;
    for (final path in paths) {
      final name = _basename(path);
      if (_isKnownEntry(name)) continue;
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          final dir = Directory(path);
          // 不认识的目录只删空的：里面有东西说明还可能是数据，宁可留着。
          if (!_isRegenerableResidue(name) && await _hasEntries(dir)) continue;
          final bytes = await _sizeOf(dir);
          await dir.delete(recursive: true);
          freed += bytes;
        } else if (type == FileSystemEntityType.file) {
          if (!_isRegenerableResidue(name)) continue;
          final bytes = await _sizeOf(File(path));
          await File(path).delete();
          freed += bytes;
        }
      } catch (_) {
        // 删不掉就留着，不影响其余残留的清理。
      }
    }
    return freed;
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
          name == pendingDirName ||
          (name == updateDirName && updating)) {
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

  /// 程序本体估算：Android 读安装包，iOS 读 .app bundle，读不到时用估值。
  static Future<int> _programBytes() async {
    final override = programBytesOverride;
    if (override != null) return override();
    final mobile = Platform.isAndroid || Platform.isIOS;
    try {
      if (Platform.isAndroid) {
        final bytes = await _installedPackageBytes();
        if (bytes > 0) return bytes;
      } else if (Platform.isIOS) {
        final bytes = await _bundleBytes();
        if (bytes > 0) return bytes;
      }
    } catch (_) {
      // 读不到就退回估值。
    }
    return mobile ? fallbackProgramBytes : 0;
  }

  /// 系统会把安装包映射进进程，从 /proc/self/maps 找出路径再算体积。
  static Future<int> _installedPackageBytes() async {
    final maps = File('/proc/self/maps');
    if (!await maps.exists()) return 0;
    final paths = <String>{};
    for (final line in await maps.readAsLines()) {
      final index = line.indexOf('/data/');
      if (index < 0) continue;
      final path = line.substring(index).trim();
      if (!path.endsWith('.apk')) continue;
      paths.add(path);
    }
    var total = 0;
    for (final path in paths) {
      total += await _sizeOf(File(path));
    }
    return total;
  }

  /// iOS：可执行文件所在的 .app 目录就是程序本体。
  static Future<int> _bundleBytes() async {
    final executable = Platform.resolvedExecutable;
    if (executable.isEmpty) return 0;
    return _sizeOf(File(executable).parent);
  }

  /// 应用数据：Android 上 `app_flutter` 同级的 databases / shared_prefs / files。
  static Future<int> _appDataBytes(CacheDirs dirs) async {
    var total = 0;
    for (final path in _appDataDirs(dirs)) {
      total += await _sizeOf(Directory(path));
    }
    return total;
  }

  static List<String> _appDataDirs(CacheDirs dirs) {
    final docsDir = _normalize(dirs.docsDir);
    if (_basename(docsDir) != docsDirName) return const [];
    final parent = _parentOf(docsDir);
    if (parent == null) return const [];
    return [for (final name in appDataDirNames) '$parent/$name'];
  }

  /// 私有目录总量：临时目录 + 文档目录 + 支持目录（去掉重复、被包含与属于应用数据的）。
  static Future<int> _privateBytes(CacheDirs dirs) async {
    var total = 0;
    for (final root in _privateRoots(dirs)) {
      total += await _sizeOf(Directory(root));
    }
    return total;
  }

  static List<String> _privateRoots(CacheDirs dirs) {
    final roots = _unique([
      dirs.tempDir,
      dirs.docsDir,
      if (dirs.supportDir != null) dirs.supportDir!,
    ]);
    final separator = Platform.pathSeparator;
    final appDataDirs = _appDataDirs(dirs);
    return roots
        .where((path) => !appDataDirs.any(
              (data) => path == data || path.startsWith('$data$separator'),
            ))
        .where((path) => !roots.any(
              (other) => other != path && path.startsWith('$other$separator'),
            ))
        .toList(growable: false);
  }

  /// 「其它残留」的候选：私有目录（临时目录之外）里不属于任何已知分项的顶层条目。
  ///
  /// 临时目录里非已知分项的内容统一算「临时文件」，不在这里重复统计。
  static Future<List<String>> _residuePaths(CacheDirs dirs) async {
    final paths = <String>[];
    for (final root in _privateRoots(dirs)) {
      if (root == dirs.tempDir) continue;
      for (final entity in await _topLevel(root)) {
        final name = _basename(entity.path);
        if (_isKnownEntry(name)) continue;
        paths.add(entity.path);
      }
    }
    return paths;
  }

  /// 已知分项的名字：各自有独立的统计与清理路径。
  static bool _isKnownEntry(String name) =>
      name == MediaCache.cacheKey ||
      name == MediaCache.legacyCacheKey ||
      name == pendingDirName ||
      name == updateDirName;

  /// 分享/导出临时命名：`album_share_*` 目录与 `familyalbum_*` 中间文件。
  static bool _isShareTemp(String name) =>
      name.startsWith(shareDirPrefix) || name.startsWith(downloadFilePrefix);

  /// 残留里删了也能再生的命名。
  static bool _isRegenerableResidue(String name) =>
      _isShareTemp(name) || name == motionDirName;

  /// 去掉结尾的分隔符并去重，避免同一个目录被统计两次。
  static List<String> _unique(List<String> paths) {
    final result = <String>[];
    for (final raw in paths) {
      if (raw.isEmpty) continue;
      final path = _normalize(raw);
      if (!result.contains(path)) result.add(path);
    }
    return result;
  }

  static String _normalize(String path) {
    var end = path.length;
    while (end > 1 && path[end - 1] == Platform.pathSeparator) {
      end -= 1;
    }
    return path.substring(0, end);
  }

  static String? _parentOf(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    if (index <= 0) return null;
    return path.substring(0, index);
  }

  static Future<bool> _hasEntries(Directory dir) async {
    try {
      await for (final _ in dir.list(followLinks: false)) {
        return true;
      }
    } catch (_) {
      // 读不到就当作非空，宁可留着。
      return true;
    }
    return false;
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

  /// 目录里的文件数与总字节数。
  static Future<({int bytes, int count})> _dirStats(String path) async {
    var bytes = 0;
    var count = 0;
    final dir = Directory(path);
    if (!await dir.exists()) return (bytes: 0, count: 0);
    try {
      await for (final item in dir.list(recursive: true, followLinks: false)) {
        if (item is! File) continue;
        try {
          bytes += (await item.stat()).size;
          count += 1;
        } catch (_) {
          // 单个文件失败跳过。
        }
      }
    } catch (_) {
      // 目录不可读时当作空。
    }
    return (bytes: bytes, count: count);
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
