import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../media_picker.dart';

/// 隐藏空间里的一个文件。
///
/// [path] 是 App 私有目录里的副本（不是原文件），[mime] 可能为空，按扩展名
/// 再判一次是不是图片/视频——能直接打开的只有这两类。
class HiddenFile {
  final String id;
  final String name;
  final String path;
  final String mime;
  final int size;
  final DateTime addedAt;

  const HiddenFile({
    required this.id,
    required this.name,
    required this.path,
    required this.mime,
    required this.size,
    required this.addedAt,
  });

  static const Set<String> _imageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif', 'dng',
  };
  static const Set<String> _videoExtensions = {
    'mp4', 'mov', 'm4v', '3gp', 'mkv', 'webm', 'avi',
  };

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  bool get isImage =>
      mime.startsWith('image/') || _imageExtensions.contains(extension);
  bool get isVideo =>
      mime.startsWith('video/') || _videoExtensions.contains(extension);

  /// App 能直接打开的类型（图片 / 视频）；其它文件先只列出来，点开不处理。
  bool get canOpen => isImage || isVideo;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'mime': mime,
        'size': size,
        'added_at': addedAt.toIso8601String(),
      };

  static HiddenFile? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'] as String?;
    final id = raw['id'] as String?;
    if (path == null || path.isEmpty || id == null || id.isEmpty) return null;
    final size = (raw['size'] as num?)?.toInt() ?? 0;
    final added =
        DateTime.tryParse(raw['added_at'] as String? ?? '') ?? DateTime.now();
    final name = raw['name'] as String? ?? path.split(Platform.pathSeparator).last;
    return HiddenFile(
      id: id,
      name: name,
      path: path,
      mime: raw['mime'] as String? ?? '',
      size: size,
      addedAt: added,
    );
  }
}

/// 隐藏空间的本地存储：App 私有目录 `hidden/` 下的文件 + 一份 `index.json`。
///
/// 文件不经过相册服务，也不在系统相册里；删 App 或清理数据就一起没了。
class HiddenSpaceStore {
  HiddenSpaceStore._();

  static const String dirName = 'hidden';
  static const String indexName = 'index.json';

  /// 测试用：直接指定一个临时目录，跳过 path_provider。
  static Directory? overrideDirectory;

  static Future<Directory> directory() async {
    final overridden = overrideDirectory;
    final dir = overridden ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}$dirName',
        );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> indexFile() async {
    final dir = await directory();
    return File('${dir.path}${Platform.pathSeparator}$indexName');
  }

  /// 读索引。索引丢了就扫描目录重建（文件名就是展示名，类型按扩展名猜）。
  static Future<List<HiddenFile>> load() async {
    final dir = await directory();
    final index = await indexFile();
    if (await index.exists()) {
      try {
        final raw = jsonDecode(await index.readAsString());
        if (raw is List) {
          final files = raw
              .map(HiddenFile.tryParse)
              .whereType<HiddenFile>()
              .where((file) => File(file.path).existsSync())
              .toList();
          files.sort((a, b) => b.addedAt.compareTo(a.addedAt));
          return files;
        }
      } catch (_) {
        // 索引坏了：下面按目录重建。
      }
    }
    final files = <HiddenFile>[];
    await for (final entity in dir.list()) {
      if (entity is! File || entity.path.endsWith(indexName)) continue;
      files.add(_fromFile(entity));
    }
    files.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    await saveIndex(files);
    return files;
  }

  static Future<void> saveIndex(List<HiddenFile> files) async {
    try {
      final index = await indexFile();
      await index.writeAsString(
        jsonEncode([for (final file in files) file.toJson()]),
        flush: true,
      );
    } catch (_) {
      // 索引写失败不影响文件本身，下次 load 会按目录重建。
    }
  }

  /// 拉起系统文件选择器（任意类型），把选中的文件复制进隐藏目录并写索引。
  static Future<List<HiddenFile>> importPicked() async {
    final dir = await directory();
    final picked = await pickAnyFiles(targetDir: dir.path);
    if (picked.isEmpty) return const [];
    final files = await load();
    final added = <HiddenFile>[];
    for (final item in picked) {
      final file = HiddenFile(
        id: const Uuid().v4(),
        name: item.name,
        path: item.path,
        mime: item.mime,
        size: item.size,
        addedAt: DateTime.now(),
      );
      files.add(file);
      added.add(file);
    }
    await saveIndex(files);
    return added;
  }

  /// 删除一个文件（物理文件 + 索引）。
  static Future<List<HiddenFile>> delete(HiddenFile file) async {
    try {
      final target = File(file.path);
      if (await target.exists()) await target.delete();
    } catch (_) {
      // 文件已经没了就算了，索引照样移除。
    }
    final files = await load();
    files.removeWhere((item) => item.id == file.id);
    await saveIndex(files);
    return files;
  }

  static HiddenFile _fromFile(File file) {
    final name = file.uri.pathSegments.last;
    final stat = file.statSync();
    final dot = name.lastIndexOf('.');
    final extension =
        dot < 0 || dot == name.length - 1 ? '' : name.substring(dot + 1).toLowerCase();
    String mime = '';
    if (HiddenFile._imageExtensions.contains(extension)) {
      mime = extension == 'png' ? 'image/png' : 'image/$extension';
    } else if (HiddenFile._videoExtensions.contains(extension)) {
      mime = 'video/$extension';
    }
    return HiddenFile(
      id: const Uuid().v4(),
      name: name,
      path: file.path,
      mime: mime,
      size: stat.size,
      addedAt: stat.modified,
    );
  }
}
