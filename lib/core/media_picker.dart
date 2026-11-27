import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

const MethodChannel _pickerChannel = MethodChannel('album/media_picker');

/// 选中的一个媒体：本地副本 + 它在系统相册里的 URI（用于上传后删除原图）。
class PickedMediaFile {
  final XFile file;
  final String? uri;

  const PickedMediaFile({required this.file, this.uri});
}

/// 选图结果：除了文件本身，还带上读取失败的数量（多数是存储空间不足）。
class PickedMediaResult {
  final List<PickedMediaFile> items;
  final int failedCount;

  const PickedMediaResult({required this.items, this.failedCount = 0});

  List<XFile> get files =>
      items.map((item) => item.file).toList(growable: false);

  List<String?> get uris =>
      items.map((item) => item.uri).toList(growable: false);

  bool get isEmpty => items.isEmpty;

  static const PickedMediaResult empty = PickedMediaResult(items: []);
}

/// 系统文件选择器选中的一个任意类型文件的**来源**（还没复制）。
class HiddenSource {
  final String uri;
  final String name;
  final String mime;
  final int size;

  const HiddenSource({
    required this.uri,
    required this.name,
    required this.mime,
    required this.size,
  });
}

/// 任意类型文件（不限于图片/视频）：隐藏空间导入用。
///
/// 只返回 content URI + 名字/大小，真正的复制由 [copyHiddenFile] 一条一条做，
/// 这样导入队列才有进度、退出页面也能继续。iOS 上还没有对应实现。
Future<List<HiddenSource>> pickHiddenSources() async {
  if (!Platform.isAndroid) {
    throw UnsupportedError('当前系统暂不支持导入文件');
  }
  final raw = await _pickerChannel.invokeMapMethod<String, dynamic>(
    'pickHiddenFiles',
  );
  final items = (raw?['items'] as List<dynamic>?) ?? const [];
  return [
    for (final item in items.whereType<Map>())
      HiddenSource(
        uri: item['uri'] as String? ?? '',
        name: item['name'] as String? ?? '',
        mime: item['mime'] as String? ?? '',
        size: (item['size'] as num?)?.toInt() ?? 0,
      ),
  ].where((source) => source.uri.isNotEmpty).toList(growable: false);
}

/// 把一个来源复制进 [targetDir]（导入队列一条一条调）。
Future<({String path, int size})> copyHiddenFile({
  required String uri,
  required String targetDir,
  required String name,
}) async {
  final result = await _pickerChannel.invokeMapMethod<String, dynamic>(
    'copyHiddenFile',
    {'uri': uri, 'targetDir': targetDir, 'name': name},
  );
  final path = result?['path'] as String? ?? '';
  if (path.isEmpty) throw StateError('复制失败');
  return (path: path, size: (result?['size'] as num?)?.toInt() ?? 0);
}

/// 用 source 的展示名复制：给导入队列用的简单封装。
Future<({String path, int size})> copyHiddenSource(
  HiddenSource source, {
  required String targetDir,
}) =>
    copyHiddenFile(uri: source.uri, targetDir: targetDir, name: source.name);

/// 使用 Android 系统 Photo Picker，但不能走 image_picker 的脱敏副本：
/// 原生端申请 ACCESS_MEDIA_LOCATION 并尽量通过 setRequireOriginal 读取原图，
/// 保留小米 Motion Photo 的内嵌视频和位置信息。
Future<PickedMediaResult> pickMultipleMediaFiles({int limit = 9}) async {
  if (limit <= 0) return PickedMediaResult.empty;
  if (Platform.isAndroid) {
    try {
      final raw = await _pickerChannel.invokeMapMethod<String, dynamic>(
        'pickMultiple',
        {'limit': limit},
      );
      if (raw != null) {
        final items = (raw['items'] as List<dynamic>?) ?? const [];
        final failed = (raw['failed'] as num?)?.toInt() ?? 0;
        final picked = items
            .whereType<Map>()
            .map(
              (item) => PickedMediaFile(
                file: XFile(
                  item['path'] as String,
                  name: item['name'] as String?,
                  mimeType: (item['mime'] as String?)?.isEmpty == true
                      ? null
                      : item['mime'] as String?,
                ),
                uri: (item['uri'] as String?)?.isEmpty == true
                    ? null
                    : item['uri'] as String?,
              ),
            )
            .take(limit)
            .toList(growable: false);
        return PickedMediaResult(items: picked, failedCount: failed);
      }
    } on MissingPluginException {
      // 原生通道未注册时退回 image_picker。
    } on PlatformException catch (e) {
      // 用户取消不会抛异常；这里通常是没有权限或选择器被占用。
      throw Exception(e.message ?? '无法打开照片选择器');
    }
  }
  final files = await ImagePicker().pickMultipleMedia(limit: limit);
  return PickedMediaResult(
    items: files
        .take(limit)
        .map((file) => PickedMediaFile(file: file))
        .toList(growable: false),
  );
}
