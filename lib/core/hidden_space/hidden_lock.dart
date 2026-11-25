import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 隐藏空间的 6 位数字密码。
///
/// 只存 `salt:sha256(salt:pin)`，不存明文；校验用常量时间比较。文件本身放在
/// App 私有目录（不在系统相册里、别的 App 读不到），密码只负责挡住拿到手机
/// 的人，不做磁盘加密——6 位数字的强度也就到这里。
class HiddenLock {
  HiddenLock._();

  static const String prefsKey = 'hidden_space_pin';

  /// 必须是 6 位数字。
  static final RegExp pinPattern = RegExp(r'^\d{6}$');

  static bool isValidPin(String pin) => pinPattern.hasMatch(pin);

  static Future<bool> isConfigured() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(prefsKey);
      return stored != null && stored.contains(':');
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setPin(String pin) async {
    if (!isValidPin(pin)) return false;
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final salt = base64Encode(saltBytes);
    final hash = _hash(pin, salt);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, '$salt:$hash');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> verify(String pin) async {
    if (!isValidPin(pin)) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(prefsKey);
      if (stored == null) return false;
      final index = stored.indexOf(':');
      if (index <= 0) return false;
      final salt = stored.substring(0, index);
      final expected = stored.substring(index + 1);
      return _constantTimeEquals(_hash(pin, salt), expected);
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
    } catch (_) {
      // 清不掉也不影响本次使用。
    }
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
