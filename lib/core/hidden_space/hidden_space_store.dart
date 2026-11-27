import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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

  /// HEIC/HEIF/AVIF 图片的安全预览图（原生解码出的 JPEG，缓存在临时目录）。
  /// 其它格式为 null，直接显示 [path]。
  final String? previewPath;

  const HiddenFile({
    required this.id,
    required this.name,
    required this.path,
    required this.mime,
    required this.size,
    required this.addedAt,
    this.previewPath,
  });

  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'avif',
    'dng',
  };
  static const Set<String> _videoExtensions = {
    'mp4',
    'mov',
    'm4v',
    '3gp',
    'mkv',
    'webm',
    'avi',
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
        if (previewPath != null) 'preview_path': previewPath,
      };

  HiddenFile copyWith({String? previewPath}) => HiddenFile(
        id: id,
        name: name,
        path: path,
        mime: mime,
        size: size,
        addedAt: addedAt,
        previewPath: previewPath ?? this.previewPath,
      );

  static HiddenFile? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'] as String?;
    final id = raw['id'] as String?;
    if (path == null || path.isEmpty || id == null || id.isEmpty) return null;
    final size = (raw['size'] as num?)?.toInt() ?? 0;
    final added =
        DateTime.tryParse(raw['added_at'] as String? ?? '') ?? DateTime.now();
    final name =
        raw['name'] as String? ?? path.split(Platform.pathSeparator).last;
    return HiddenFile(
      id: id,
      name: name,
      path: path,
      mime: raw['mime'] as String? ?? '',
      size: size,
      addedAt: added,
      previewPath: raw['preview_path'] as String?,
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

  /// 测试用：直接返回这份列表，跳过真实文件 IO（widget 测试的 FakeAsync 里
  /// 真实 IO 不会自己完成）。
  static List<HiddenFile>? overrideFiles;

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

  /// 读索引。索引丢了/缺条目就扫描目录补齐（文件名就是展示名，类型按扩展名猜）。
  ///
  /// 按路径去重：导入队列是「先落盘、再记索引」，同一个文件既可能出现在目录
  /// 扫描里，也可能已经写进索引，不能算成两条。
  static Future<List<HiddenFile>> load() async {
    final fake = overrideFiles;
    if (fake != null) return List<HiddenFile>.of(fake);
    final dir = await directory();
    final index = await indexFile();
    final byPath = <String, HiddenFile>{};
    var fromIndex = false;
    if (await index.exists()) {
      try {
        final raw = jsonDecode(await index.readAsString());
        if (raw is List) {
          fromIndex = true;
          for (final item in raw) {
            final file = HiddenFile.tryParse(item);
            if (file == null) continue;
            if (!File(file.path).existsSync()) continue;
            byPath[file.path] = file;
          }
        }
      } catch (_) {
        // 索引坏了：按目录重建。
      }
    }
    var changed = !fromIndex;
    await for (final entity in dir.list()) {
      if (entity is! File || entity.path.endsWith(indexName)) continue;
      if (byPath.containsKey(entity.path)) continue;
      byPath[entity.path] = _fromFile(entity);
      changed = true;
    }
    final files = byPath.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    if (changed) await saveIndex(files);
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

  /// 导入队列复制完一条后调用：把它记进索引。
  static Future<HiddenFile> addImported({
    required String path,
    required String name,
    required String mime,
    required int size,
    String? previewPath,
  }) async {
    final file = HiddenFile(
      id: const Uuid().v4(),
      name: name,
      path: path,
      mime: mime,
      size: size,
      addedAt: DateTime.now(),
      previewPath: previewPath,
    );
    final files = await load();
    // 目录扫描可能已经把它扫进来了（先落盘再记索引）：按路径认，别重复，
    // 但要补上来源给的展示名/MIME/大小（磁盘文件名前面带了 uuid）。
    for (var i = 0; i < files.length; i++) {
      final existing = files[i];
      if (existing.path != path) continue;
      final updated = HiddenFile(
        id: existing.id,
        name: name,
        path: existing.path,
        mime: mime.isEmpty ? existing.mime : mime,
        size: size > 0 ? size : existing.size,
        addedAt: existing.addedAt,
        previewPath: previewPath ?? existing.previewPath,
      );
      files[i] = updated;
      await saveIndex(files);
      return updated;
    }
    files.add(file);
    await saveIndex(files);
    return file;
  }

  /// 记下某张图的预览图路径（HEIC 解码出来的 JPEG）。
  static Future<void> updatePreview(String path, String previewPath) async {
    final files = await load();
    var changed = false;
    for (var i = 0; i < files.length; i++) {
      if (files[i].path != path) continue;
      files[i] = files[i].copyWith(previewPath: previewPath);
      changed = true;
      break;
    }
    if (changed) await saveIndex(files);
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
    final extension = dot < 0 || dot == name.length - 1
        ? ''
        : name.substring(dot + 1).toLowerCase();
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
