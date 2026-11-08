import 'dart:convert';

import 'package:flutter/services.dart';

/// 本地保存密码用的加密层。
///
/// Android 端走 `album/secure_store` 通道，用 AndroidKeyStore 里不可导出的
/// AES/GCM 密钥加密；通道不可用（桌面、测试、API < 23）时退回 base64 混淆，
/// 保证「记住密码」在旧设备上仍然可用。
class SecureStore {
  SecureStore._();

  static const MethodChannel _channel = MethodChannel('album/secure_store');
  static const String _keystorePrefix = 'k1:';
  static const String _fallbackPrefix = 'b64:';

  static Future<String?> encrypt(String value) async {
    if (value.isEmpty) return null;
    try {
      final encrypted = await _channel.invokeMethod<String>(
        'encrypt',
        {'value': value},
      );
      if (encrypted != null && encrypted.isNotEmpty) {
        return '$_keystorePrefix$encrypted';
      }
    } catch (_) {
      // 插件不可用或 Keystore 异常：退回混淆存储。
    }
    return '$_fallbackPrefix${base64Encode(utf8.encode(value))}';
  }

  static Future<String?> decrypt(String? stored) async {
    if (stored == null || stored.isEmpty) return null;
    if (stored.startsWith(_keystorePrefix)) {
      try {
        return await _channel.invokeMethod<String>(
          'decrypt',
          {'value': stored.substring(_keystorePrefix.length)},
        );
      } catch (_) {
        // 密钥失效（重装/恢复出厂）时只能让用户重新输入。
        return null;
      }
    }
    if (stored.startsWith(_fallbackPrefix)) {
      try {
        return utf8.decode(
          base64Decode(stored.substring(_fallbackPrefix.length)),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
