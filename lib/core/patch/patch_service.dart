import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_patcher/flutter_patcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../server_config.dart';

/// 服务端 `/api/patch/latest` 返回的一条补丁：只需知道「有、多大、怎么下」。
class PatchInfo {
  final int patchVersion;
  final String downloadPath;
  final int fileSize;
  final String sha256;
  final String notes;

  const PatchInfo({
    required this.patchVersion,
    required this.downloadPath,
    this.fileSize = 0,
    this.sha256 = '',
    this.notes = '',
  });

  factory PatchInfo.fromJson(Map<String, dynamic> json) {
    return PatchInfo(
      patchVersion: (json['patch_version'] as num?)?.toInt() ?? 0,
      downloadPath: json['download_url'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      sha256: (json['sha256'] as String? ?? '').toLowerCase(),
      notes: json['release_notes'] as String? ?? '',
    );
  }

  bool get isValid => patchVersion > 0 && downloadPath.isNotEmpty;
}

/// Dart 层热更新（flutter_patcher）。
///
/// 补丁只修 Dart 代码：原生改动、权限、插件、图标仍然必须走 APK 更新。所以
/// 更新检测的顺序是「先看有没有补丁，有就只走补丁；没有才看 APK」——查询和
/// 下载分开（[fetchAvailable] 只发一次请求，[apply] 才下载），启动时只要等
/// 查询这一步，下载在后台跑，不阻塞用户进 App。
///
/// iOS 上所有方法直接返回，不触发任何网络请求。
class PatchService {
  PatchService._();

  static const String _path = '/api/patch/latest';

  static int _appliedVersion = 0;
  static int _apkVersionCode = 0;
  static bool _inited = false;

  /// 同一时间只跑一份下载：启动检查与「我的 → 检查更新」可能撞在一起。
  static Future<bool>? _applying;

  /// 当前已安装的补丁版本，0 表示没有补丁。
  static int get appliedVersion => _appliedVersion;

  /// 当前基线 APK 的 versionCode。
  static int get apkVersionCode => _apkVersionCode;

  /// 冷启动时在 runApp 之前调一次，配置崩溃回滚与首帧校验。
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    if (_inited) return;
    _inited = true;
    try {
      await FlutterPatcher.init();
    } catch (e, s) {
      debugPrint('热更新初始化失败: $e $s');
    }
  }

  /// 查一次「有没有比现在更新的补丁」，不下载。
  ///
  /// 任何异常（断网、后端 404、参数非法、原生不可用）都返回 null，绝不向上抛。
  static Future<PatchInfo?> fetchAvailable() async {
    if (!Platform.isAndroid) return null;
    try {
      await init();
      final info = await PackageInfo.fromPlatform();
      _apkVersionCode = int.tryParse(info.buildNumber) ?? 0;
      if (_apkVersionCode <= 0) return null;

      final current = await FlutterPatcher.currentVersion;
      _appliedVersion = int.tryParse(current ?? '') ?? 0;

      final latest = await _fetchLatest(_apkVersionCode, _appliedVersion);
      if (latest == null) return null;
      final patch = PatchInfo.fromJson(latest);
      if (!patch.isValid || patch.patchVersion <= _appliedVersion) return null;
      return patch;
    } catch (e, s) {
      debugPrint('热更新检查失败: $e $s');
      return null;
    }
  }

  /// 下载并安装 [info]，返回 true 表示补丁已落盘、等下次冷启动生效。
  ///
  /// 失败只返回 false（断网、校验不过、原生拒绝），不向上抛；同一时间重复
  /// 调用会复用同一次下载。
  static Future<bool> apply(PatchInfo info) {
    final existing = _applying;
    if (existing != null) return existing;
    final future = _apply(info);
    _applying = future;
    future.whenComplete(() {
      if (identical(_applying, future)) _applying = null;
    });
    return future;
  }

  static Future<bool> _apply(PatchInfo info) async {
    try {
      if (!info.isValid) return false;
      if (_apkVersionCode <= 0) {
        final package = await PackageInfo.fromPlatform();
        _apkVersionCode = int.tryParse(package.buildNumber) ?? 0;
      }
      if (_apkVersionCode <= 0) return false;

      final bytes =
          await _download('${ServerConfig.current}${info.downloadPath}');
      if (bytes == null) return false;

      // 自己先验一遍 sha256：服务端给的就是它，校验通过再交给原生。
      if (info.sha256.isNotEmpty) {
        final actual = sha256.convert(bytes).toString();
        if (actual != info.sha256) {
          debugPrint('补丁校验失败：期望 ${info.sha256}，实际 $actual');
          return false;
        }
      }

      final result = await FlutterPatcher.applyPatchBytes(
        bytes,
        version: '${info.patchVersion}',
        targetVersionCode: _apkVersionCode,
      );
      if (!result.ok) {
        debugPrint('补丁应用失败: ${result.error} ${result.message}');
        return false;
      }
      _appliedVersion = info.patchVersion;
      return true;
    } catch (e, s) {
      debugPrint('热更新应用失败: $e $s');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> _fetchLatest(int base, int current) async {
    final dio = Dio();
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '${ServerConfig.current}$_path',
        queryParameters: {
          'base_version_code': base,
          'current_patch_version': current,
        },
        options: Options(
          // 和 APK 检查同一档超时：启动时这两个请求并行等，谁慢也不该多拖
          // 几秒首屏。
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (status) => status == 200,
        ),
      );
      final data = response.data;
      if (data == null || data['has_update'] != true) return null;
      return data;
    } catch (e) {
      debugPrint('查询补丁失败: $e');
      return null;
    } finally {
      // 查询是一次性的，连接池留着只会占端口。
      dio.close(force: true);
    }
  }

  static Future<Uint8List?> _download(String url) async {
    Dio? dio;
    try {
      dio = Dio();
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 120),
          validateStatus: (status) => status == 200,
        ),
      );
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } catch (e) {
      debugPrint('下载补丁失败: $e');
      return null;
    } finally {
      dio?.close(force: true);
    }
  }
}
