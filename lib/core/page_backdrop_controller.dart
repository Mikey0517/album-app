import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'page_backdrop_spec.dart';

/// 首页三个 tab（朋友圈 / 相册 / 我的）共用的页面背景。
///
/// 形态是 [PageBackdropSpec] 的四种：默认品牌渐变 / 纯色 / 双色渐变 / 自定义
/// 图片。以前这里只有一个「图片路径」[ValueNotifier]，现在换成 spec——设置页
/// 的文案、弹层的勾选态、渲染层的底色都从同一个对象推出来，不会各说一套。
///
/// 为什么图片要复制进私有目录：相册 URI（content:// 或 PHPicker 临时文件）随时
/// 会被系统回收、被「清理」工具删掉，也可能在 App 重启后失效。选完就复制一份
/// 到 support/page_backdrop/，之后只认这份副本，三个页面共用同一张。
///
/// 压缩：直接交给 image_picker 的原生编码器（maxWidth/maxHeight = [maxEdge]、
/// imageQuality = [jpegQuality]），最长边压到 ≤2048、JPEG 质量 80；不把原图整张
/// 解码进 Dart 堆再重编码，选完立刻就能用。
///
/// 为什么上限是 2048 而不是 1080：这份副本是「唯一可用的原图」，渲染层按
/// 「屏幕宽 × devicePixelRatio」解码（见 appBackdropDecodeWidth）。1080 的副本在
/// 2K 屏上只能被**放大**，放大就是糊——压缩上限必须 ≥ 解码上限。
///
/// 持久化：一段 JSON（[prefsKey] = [PageBackdropSpec.encode]），图片的副本路径
/// 是其中 [PageBackdropSpec.imagePath] 一个字段。
///
/// 迁移：[legacyPrefsKey] 是旧版本只存图片路径的 key。[init] 看到新 key 没有、
/// 旧 key 有且文件还在，就把路径包成 [PageBackdropSpec.image] 写进新 key，再把
/// 旧 key 删掉；旧 key 指向的文件已经没了就两个都清掉、回退默认渐变。迁移只跑
/// 一次，之后新 key 说了算——所有写入（[_writeSpec]）都会顺手删掉旧 key。
class PageBackdropController {
  PageBackdropController._();

  /// SharedPreferences 里的键：当前背景 spec 的 JSON。
  static const String prefsKey = 'page_backdrop_spec';

  /// 旧版本（只支持自定义图片）的键：图片副本的绝对路径。
  ///
  /// 只读不写：[init] 迁移完就删掉它。
  static const String legacyPrefsKey = 'page_background_image_path';

  /// 私有目录里的文件名主干（扩展名跟着选择器给的格式，一般就是 .jpg）。
  static const String fileStem = 'page_backdrop';

  /// 私有目录名。
  static const String dirName = 'page_backdrop';

  /// 最长边上限（像素）。
  ///
  /// 同时是「存储副本」与「解码」的同一道上限（解码侧见
  /// appBackdropDecodeMaxWidth）：副本比解码上限小就会被放大、放大就是糊。
  static const int maxEdge = 2048;

  /// JPEG 质量。
  static const int jpegQuality = 80;

  /// 当前背景；三个页面 + 设置页都听它。
  static final ValueNotifier<PageBackdropSpec> spec =
      ValueNotifier<PageBackdropSpec>(const PageBackdropSpec.defaultGradient());

  /// 测试用：替换相册选择器（避免打平台通道），顺便断言压缩参数。
  @visibleForTesting
  static Future<XFile?> Function({required int maxEdge, required int jpegQuality})?
      pickPhotoOverride;

  /// 测试用：替换私有目录，避免依赖 path_provider 插件。
  @visibleForTesting
  static Future<Directory> Function()? dirOverride;

  /// 冷启动恢复：读 spec；图片副本丢了回退默认，旧 key 顺手迁移。
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      spec.value = await _readSpec(prefs);
    } catch (_) {
      spec.value = const PageBackdropSpec.defaultGradient();
    }
  }

  /// 纯色背景。
  static Future<void> setColor(Color color) =>
      _commit(PageBackdropSpec.solid(color));

  /// 双色渐变背景（左上 → 右下）。
  static Future<void> setGradient(Color start, Color end) =>
      _commit(PageBackdropSpec.gradient(start: start, end: end));

  /// 选图 → 复制进私有目录（替换旧文件）→ 存 image spec。返回 null 表示用户取消。
  static Future<String?> pickAndSave() async {
    final picked = await _pickPhoto();
    if (picked == null) return null;
    final dir = await _backdropDir();
    final target = File('${dir.path}/$fileStem${_extensionOf(picked.path)}');
    // 先落副本再删旧图：复制失败时旧背景还在，页面不会突然变成一片空底。
    await File(picked.path).copy(target.path);
    await _deleteBackdrops(dir, keep: target.path);
    await _commit(PageBackdropSpec.image(target.path));
    return target.path;
  }

  /// 恢复默认：删掉私有目录里的副本 + 清 key，三个页面回到品牌渐变。
  static Future<void> reset() async {
    try {
      await _deleteBackdrops(await _backdropDir());
    } catch (_) {
      // 目录不可用时只清 key，至少不再引用它。
    }
    await _clearPrefs();
    spec.value = const PageBackdropSpec.defaultGradient();
  }

  /// 渲染层用：路径有值且文件确实还在才返回 [File]。
  ///
  /// 同步检查一次，图被删掉时直接少一层，不会先闪一张裂图再回退。
  static File? imageFileOrNull(String? saved) {
    if (!_imageExists(saved)) return null;
    return File(saved!);
  }

  /// spec 是图片且副本还在时返回那个文件；其他三种形态一律 null。
  static File? imageFileOf(PageBackdropSpec spec) =>
      spec.isImage ? imageFileOrNull(spec.imagePath) : null;

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

  /// 写入新 spec 并广播；不是图片形态时顺手把旧副本删掉（不然 2048 的 JPEG
  /// 会一直躺在私有目录里占地方）。
  ///
  /// 删除**不 await**：换成纯色/渐变是对用户的一次点击，不该等几次文件删除才
  /// 算「生效」；删不掉也只是留着旧文件，不影响渲染。
  static Future<void> _commit(PageBackdropSpec next) async {
    await _writeSpec(next);
    spec.value = next;
    if (next.isImage) return;
    unawaited(_purgeImages());
  }

  /// 删掉私有目录里的所有副本（best-effort）。

  static Future<void> _purgeImages() async {
    try {
      await _deleteBackdrops(await _backdropDir());
    } catch (_) {
      // 目录不可用就下次再说。
    }
  }

  /// 读 spec：新 key → 迁移旧 key → 默认渐变；坏数据不留在盘上。
  static Future<PageBackdropSpec> _readSpec(SharedPreferences prefs) async {
    final raw = prefs.getString(prefsKey);
    final parsed = PageBackdropSpec.decode(raw);
    if (parsed != null) {
      if (parsed.isImage && !_imageExists(parsed.imagePath)) {
        // 副本被清理工具/用户删掉：连 spec 一起清，别每次启动都白试一次。
        await prefs.remove(prefsKey);
        await prefs.remove(legacyPrefsKey);
        return const PageBackdropSpec.defaultGradient();
      }
      // 迁移已经完成，旧 key 不再需要。
      if (prefs.containsKey(legacyPrefsKey)) {
        await prefs.remove(legacyPrefsKey);
      }
      return parsed;
    }
    if (raw != null) await prefs.remove(prefsKey);
    return _migrateLegacy(prefs);
  }

  /// 旧 key（只有图片路径）→ image spec，写完删旧 key。
  static Future<PageBackdropSpec> _migrateLegacy(
    SharedPreferences prefs,
  ) async {
    final legacy = prefs.getString(legacyPrefsKey);
    if (legacy == null || legacy.isEmpty) {
      return const PageBackdropSpec.defaultGradient();
    }
    await prefs.remove(legacyPrefsKey);
    if (!_imageExists(legacy)) {
      // 旧 key 指向的文件早就没了：迁移没有意义，回退默认渐变。
      return const PageBackdropSpec.defaultGradient();
    }
    final migrated = PageBackdropSpec.image(legacy);
    await _writeSpec(migrated);
    return migrated;
  }

  static bool _imageExists(String? path) {
    if (path == null || path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      // 路径不可读按丢失处理。
      return false;
    }
  }

  static Future<void> _writeSpec(PageBackdropSpec value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, value.encode());
      // 新 key 已经能表达一切，旧 key 留着就是第二份真相。
      if (prefs.containsKey(legacyPrefsKey)) {
        await prefs.remove(legacyPrefsKey);
      }
    } catch (_) {
      // 落盘失败不影响本次生效，下次冷启动回到默认渐变。
    }
  }

  static Future<void> _clearPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
      await prefs.remove(legacyPrefsKey);
    } catch (_) {
      // 忽略。
    }
  }
}
