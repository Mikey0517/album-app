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

  /// 扩展名可能骗人（比如 .jpg 实际是 HEIC）：再读文件头认一次品牌。
  ///
  /// HEIF/AVIF 的 `ftyp` box 在第 4~12 字节：`ftypheic` / `ftypheix` /
  /// `ftyphevc` / `ftypmif1` / `ftypavif` 等。
  static Future<bool> needsPreview(String path) async {
    if (riskyExtensions.contains(extensionOf(path))) return true;
    try {
      final file = File(path);
      final length = await file.length();
      if (length < 12) return false;
      final raf = await file.open();
      try {
        final header = await raf.read(12);
        if (header.length < 12) return false;
        final brand = String.fromCharCodes(header.sublist(4, 8));
        if (brand != 'ftyp') return false;
        final type = String.fromCharCodes(header.sublist(8, 12)).toLowerCase();
        return type.startsWith('hei') ||
            type == 'mif1' ||
            type == 'avif' ||
            type == 'avis';
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// 返回可安全显示的图片路径：
  /// - 安全格式：原路径；
  /// - HEIC/HEIF/AVIF：生成过的 JPEG 缓存，没有就现场生成；失败返回 null。
  static Future<String?> resolve(String path, {int maxEdge = 2560}) async {
    if (path.isEmpty) return null;
    if (!await needsPreview(path)) return path;
    final cached = await _cachePath(path);
    if (await cached.exists()) return cached.path;
    // 绝不能走 Dart 的 instantiateImageCodec 兜底：它还是 ImageDecoder，
    // 解 HEIC 一样会 abort 进程。原生失败就返回 null（页面显示占位）。
    final encoded = await ImageEncoder.encode(
      path,
      maxEdge: maxEdge,
      quality: 90,
      allowDartFallback: false,
    );
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
