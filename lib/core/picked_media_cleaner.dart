import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 管理选图时复制到 App 私有目录 `picked_media/` 的副本。
///
/// 副本放在 `filesDir`（不是 cache）：系统清理缓存时不会把它删掉，
/// 排队中的上传重启后仍能继续。上传成功/取消后立刻删除，控制磁盘占用。
class PickedMediaCleaner {
  PickedMediaCleaner._();

  /// 测试时替换候选父目录。
  @visibleForTesting
  static Future<List<String>> Function()? rootsOverride;

  static Future<List<String>> _roots() async {
    if (rootsOverride != null) return rootsOverride!();
    final roots = <String>[];
    try {
      roots.add((await getApplicationDocumentsDirectory()).path);
    } catch (_) {
      // 桌面/测试环境可能没有该插件。
    }
    try {
      // Android 原生端把副本写进 filesDir/picked_media（即 support 目录），
      // 这里必须一起扫，否则副本永远删不掉，存储空间里也会两边对不上。
      roots.add((await getApplicationSupportDirectory()).path);
    } catch (_) {
      // 桌面/测试环境可能没有该插件。
    }
    try {
      // 兼容 1.2.48 之前放在缓存目录里的副本。
      roots.add((await getTemporaryDirectory()).path);
    } catch (_) {
      // 忽略。
    }
    return roots;
  }

  /// 删除某个副本；只处理落在 `picked_media/` 里的路径，不会碰用户相册原图。
  static Future<bool> deleteCopy(String path) async {
    if (path.isEmpty) return false;
    try {
      for (final root in await _roots()) {
        if (!path.startsWith('$root/picked_media/')) continue;
        final file = File(path);
        if (!await file.exists()) return false;
        await file.delete();
        return true;
      }
    } catch (_) {
      // 删除失败不影响上传结果。
    }
    return false;
  }

  /// `picked_media/` 里的全部副本（两个候选目录都扫，按路径去重）。
  static Future<List<File>> pendingCopies() async {
    final files = <File>[];
    final seen = <String>{};
    for (final root in await _roots()) {
      final dir = Directory('$root/picked_media');
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          if (!seen.add(entity.path)) continue;
          files.add(entity);
        }
      } catch (_) {
        // 目录不可读时跳过。
      }
    }
    return files;
  }

  /// 副本的条数与总字节数，用于「存储空间」统计。
  static Future<({int count, int bytes})> copyStats() async {
    var count = 0;
    var bytes = 0;
    for (final file in await pendingCopies()) {
      try {
        bytes += (await file.stat()).size;
        count += 1;
      } catch (_) {
        // 单个文件读不到就跳过。
      }
    }
    return (count: count, bytes: bytes);
  }

  /// 清掉没有被队列引用的副本（崩溃、取消后残留），返回删除数量。
  static Future<int> deleteOrphans(Iterable<String> keepPaths) async {
    final keep = keepPaths.toSet();
    var deleted = 0;
    for (final root in await _roots()) {
      final dir = Directory('$root/picked_media');
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          if (keep.contains(entity.path)) continue;
          try {
            await entity.delete();
            deleted += 1;
          } catch (_) {
            // 单个文件删不掉就跳过。
          }
        }
      } catch (_) {
        // 目录不可读时跳过。
      }
    }
    return deleted;
  }
}
