import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_patcher/flutter_patcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../server_config.dart';

/// Dart 层热更新（flutter_patcher）。
///
/// 补丁只修 Dart 代码：原生改动、权限、插件、图标仍然必须走 APK 更新，
/// 所以启动顺序永远是「先查 APK，再查补丁」，且补丁绝不阻塞启动。
/// iOS 上所有方法直接返回，不触发任何网络请求。
class PatchService {
  PatchService._();

  static const String _path = '/api/patch/latest';

  static int _appliedVersion = 0;
  static int _apkVersionCode = 0;
  static bool _inited = false;

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

  /// 检查并下载补丁。返回 true 表示补丁已落盘，等下次冷启动生效。
  ///
  /// 任何异常（断网、后端 404、校验失败、原生拒绝）都只是返回 false，
  /// 绝不向上抛，避免影响启动。
  static Future<bool> checkAndApply() async {
    if (!Platform.isAndroid) return false;
    try {
      await init();
      final info = await PackageInfo.fromPlatform();
      _apkVersionCode = int.tryParse(info.buildNumber) ?? 0;
      if (_apkVersionCode <= 0) return false;

      final current = await FlutterPatcher.currentVersion;
      _appliedVersion = int.tryParse(current ?? '') ?? 0;

      final latest = await _fetchLatest(_apkVersionCode, _appliedVersion);
      if (latest == null) return false;

      final patchVersion = (latest['patch_version'] as num?)?.toInt() ?? 0;
      final downloadPath = latest['download_url'] as String? ?? '';
      final expectedSha = (latest['sha256'] as String? ?? '').toLowerCase();
      if (patchVersion <= _appliedVersion || downloadPath.isEmpty) return false;

      final bytes = await _download('${ServerConfig.current}$downloadPath');
      if (bytes == null) return false;

      // 自己先验一遍 sha256：服务端给的就是它，校验通过再交给原生。
      if (expectedSha.isNotEmpty) {
        final actual = sha256.convert(bytes).toString();
        if (actual != expectedSha) {
          debugPrint('补丁校验失败：期望 $expectedSha，实际 $actual');
          return false;
        }
      }

      final result = await FlutterPatcher.applyPatchBytes(
        bytes,
        version: '$patchVersion',
        targetVersionCode: _apkVersionCode,
      );
      if (!result.ok) {
        debugPrint('补丁应用失败: ${result.error} ${result.message}');
        return false;
      }
      _appliedVersion = patchVersion;
      return true;
    } catch (e, s) {
      debugPrint('热更新检查失败: $e $s');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> _fetchLatest(int base, int current) async {
    try {
      final dio = Dio();
      final response = await dio.get<Map<String, dynamic>>(
        '${ServerConfig.current}$_path',
        queryParameters: {
          'base_version_code': base,
          'current_patch_version': current,
        },
        options: Options(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
          validateStatus: (status) => status == 200,
        ),
      );
      final data = response.data;
      if (data == null || data['has_update'] != true) return null;
      return data;
    } catch (e) {
      debugPrint('查询补丁失败: $e');
      return null;
    }
  }

  static Future<Uint8List?> _download(String url) async {
    try {
      final dio = Dio();
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
    }
  }
}
