import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'image_encoder.dart';

/// 本地图片的安全预览图。
///
/// Flutter 解码 HEIF/HEIC/AVIF 时走 Android `ImageDecoder`，某些图（小米相机
/// 的 HEIC、带 gain map 的 HEIF）会让引擎抛 JNI 异常并直接 **abort 进程**
/// （flutter/flutter#196793），Dart 层拦不住。所以这些格式不进 `Image.file`，
/// 先用原生 `BitmapFactory` 解码、转成 JPEG 缓存再显示——JPEG/PNG/WebP/GIF
/// 仍按原文件走，不做转换。
class LocalImagePreview {
  LocalImagePreview._();

  /// 需要先转 JPEG 才能安全显示的扩展名。
  static const Set<String> riskyExtensions = {
    'heic', 'heif', 'hif', 'heics', 'avif',
  };

  static String extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// 这个文件能不能直接交给 `Image.file`（不经过 Android ImageDecoder）。
  static bool isSafeForFlutter(String path) =>
      !riskyExtensions.contains(extensionOf(path));

  /// 返回可安全显示的图片路径：
  /// - 安全格式：原路径；
  /// - HEIC/HEIF/AVIF：生成过的 JPEG 缓存，没有就现场生成；失败返回 null。
  static Future<String?> resolve(String path, {int maxEdge = 2560}) async {
    if (path.isEmpty) return null;
    if (isSafeForFlutter(path)) return path;
    final cached = await _cachePath(path);
    if (await cached.exists()) return cached.path;
    final encoded = await ImageEncoder.encode(path, maxEdge: maxEdge, quality: 90);
    if (encoded == null || encoded.bytes.isEmpty) return null;
    await cached.parent.create(recursive: true);
    await cached.writeAsBytes(encoded.bytes, flush: true);
    return cached.path;
  }

  static Future<File> _cachePath(String path) async {
    final cache = await getTemporaryDirectory();
    final digest = sha1.convert(
      '${path}_${File(path).lengthSync()}_${File(path).lastModifiedSync()}'
          .codeUnits,
    );
    return File(
      '${cache.path}${Platform.pathSeparator}hidden_previews'
      '${Platform.pathSeparator}$digest.jpg',
    );
  }
}
