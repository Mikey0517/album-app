import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首页三个 tab（朋友圈 / 相册 / 我的）共用的自定义背景图。
///
/// 为什么复制进私有目录：相册 URI（content:// 或 PHPicker 临时文件）随时会
/// 被系统回收、被「清理」工具删掉，也可能在 App 重启后失效。选完就复制一份
/// 到 `support/page_backdrop/`，之后只认这份副本，三个页面共用同一张。
///
/// 压缩：直接交给 image_picker 的原生编码器（`maxWidth/maxHeight =
/// [maxEdge]`、`imageQuality = [jpegQuality]`），最长边压到 ≤1080、JPEG 质量
/// 80；不把原图整张解码进 Dart 堆再重编码，选完立刻就能用。
///
/// 持久化：只存副本路径（[prefsKey]）。文件丢了（用户清数据、换设备）就读
/// 不到，[init] 会顺手把 key 清掉并让三个页面回退到渐变。
class PageBackdropController {
  PageBackdropController._();

  /// SharedPreferences 里的键：背景图副本的绝对路径。
  static const String prefsKey = 'page_background_image_path';

  /// 私有目录里的文件名主干（扩展名跟着选择器给的格式，一般就是 .jpg）。
  static const String fileStem = 'page_backdrop';

  /// 私有目录名。
  static const String dirName = 'page_backdrop';

  /// 最长边上限（像素）。
  static const int maxEdge = 1080;

  /// JPEG 质量。
  static const int jpegQuality = 80;

  /// 当前背景图路径；null = 走默认渐变。三个页面都听它。
  static final ValueNotifier<String?> path = ValueNotifier<String?>(null);

  /// 测试用：替换相册选择器（避免打平台通道），顺便断言压缩参数。
  @visibleForTesting
  static Future<XFile?> Function({required int maxEdge, required int jpegQuality})?
      pickPhotoOverride;

  /// 测试用：替换私有目录，避免依赖 path_provider 插件。
  @visibleForTesting
  static Future<Directory> Function()? dirOverride;

  /// 冷启动恢复：读 key，文件还在才生效，否则清 key 回退渐变。
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      path.value = await _existingPath(prefs.getString(prefsKey));
    } catch (_) {
      path.value = null;
    }
  }

  /// 选图 → 复制进私有目录（替换旧文件）→ 存路径。返回 null 表示用户取消。
  static Future<String?> pickAndSave() async {
    final picked = await _pickPhoto();
    if (picked == null) return null;
    final dir = await _backdropDir();
    final target = File('${dir.path}/$fileStem${_extensionOf(picked.path)}');
    // 先落副本再删旧图：复制失败时旧背景还在，页面不会突然变成一片空底。
    await File(picked.path).copy(target.path);
    await _deleteBackdrops(dir, keep: target.path);
    await _writePref(target.path);
    path.value = target.path;
    return target.path;
  }

  /// 恢复默认：删掉私有目录里的副本 + 清 key，三个页面回到渐变。
  static Future<void> reset() async {
    try {
      await _deleteBackdrops(await _backdropDir());
    } catch (_) {
      // 目录不可用时只清 key，至少不再引用它。
    }
    await _clearPref();
    path.value = null;
  }

  /// 渲染层用：路径有值且文件确实还在才返回 [File]。
  ///
  /// 同步检查一次，图被删掉时直接少一层，不会先闪一张裂图再回退。
  static File? imageFileOrNull(String? saved) {
    if (saved == null || saved.isEmpty) return null;
    final file = File(saved);
    return file.existsSync() ? file : null;
  }

  static Future<XFile?> _pickPhoto() {
    final override = pickPhotoOverride;
    if (override != null) {
      return override(maxEdge: maxEdge, jpegQuality: jpegQuality);
    }
    return ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxEdge.toDouble(),
      maxHeight: maxEdge.toDouble(),
      imageQuality: jpegQuality,
      // 背景图不需要 EXIF/位置，少要一次 iOS 的完整相册元数据权限。
      requestFullMetadata: false,
    );
  }

  static Future<Directory> _backdropDir() async {
    final override = dirOverride;
    final Directory dir;
    if (override != null) {
      dir = await override();
    } else {
      final support = await getApplicationSupportDirectory();
      dir = Directory('${support.path}/$dirName');
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 删掉 [dir] 里之前存的背景图（[keep] 是刚写好的那份）。
  static Future<void> _deleteBackdrops(Directory dir, {String? keep}) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (entity.path == keep) continue;
      if (!entity.path.split('/').last.startsWith(fileStem)) continue;
      try {
        await entity.delete();
      } catch (_) {
        // 单个删不掉就留着，下次覆盖。
      }
    }
  }

  static String _extensionOf(String sourcePath) {
    final name = sourcePath.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.jpg';
    final ext = name.substring(dot).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp'}.contains(ext) ? ext : '.jpg';
  }

  static Future<String?> _existingPath(String? saved) async {
    if (saved == null || saved.isEmpty) return null;
    try {
      if (await File(saved).exists()) return saved;
    } catch (_) {
      // 路径不可读按丢失处理。
    }
    await _clearPref();
    return null;
  }

  static Future<void> _writePref(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, value);
    } catch (_) {
      // 落盘失败不影响本次生效，下次冷启动回到渐变。
    }
  }

  static Future<void> _clearPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
    } catch (_) {
      // 忽略。
    }
  }
}
