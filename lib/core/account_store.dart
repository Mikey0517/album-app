import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import 'secure_store.dart';

/// 登录页「记住的账号」。
class SavedAccount {
  final String userId;
  final String nickname;
  final DateTime lastLoginAt;

  /// 明文密码（已解密）；没勾「记住密码」时为 null。
  final String? password;

  const SavedAccount({
    required this.userId,
    required this.nickname,
    required this.lastLoginAt,
    this.password,
  });

  bool get hasPassword => password != null && password!.isNotEmpty;

  String get label => nickname.isEmpty ? userId : nickname;

  String get initial {
    final source = label.trim();
    return source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
  }
}

/// 账号列表 + 密码的本地存储，登录页展示成 QQ 那种账号下拉。
class AccountStore {
  AccountStore._();

  static const String _key = 'login_accounts';
  static const int maxAccounts = 8;

  static Future<List<SavedAccount>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = <SavedAccount>[];
    for (final item in _rawAccounts(prefs)) {
      final userId = item['user_id'] as String?;
      if (userId == null || userId.isEmpty) continue;
      accounts.add(SavedAccount(
        userId: userId,
        nickname: item['nickname'] as String? ?? '',
        lastLoginAt: DateTime.tryParse(item['last_login'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        password: await SecureStore.decrypt(item['password'] as String?),
      ));
    }
    accounts.sort((a, b) => b.lastLoginAt.compareTo(a.lastLoginAt));
    return accounts;
  }

  /// 登录成功后调用：把账号移到最前面；[savePassword] 为 false 时顺带清掉
  /// 该账号以前保存的密码。
  static Future<void> remember(
    AppUser user,
    String password, {
    required bool savePassword,
  }) async {
    if (user.userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = _rawAccounts(prefs)
      ..removeWhere((item) => item['user_id'] == user.userId);
    final entry = <String, dynamic>{
      'user_id': user.userId,
      'nickname': user.nickname,
      'last_login': DateTime.now().toIso8601String(),
    };
    if (savePassword && password.isNotEmpty) {
      final encrypted = await SecureStore.encrypt(password);
      if (encrypted != null) entry['password'] = encrypted;
    }
    raw.insert(0, entry);
    await prefs.setString(_key, jsonEncode(raw.take(maxAccounts).toList()));
  }

  /// 只忘掉密码，账号仍留在列表里。
  static Future<void> forgetPassword(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _rawAccounts(prefs);
    for (final item in raw) {
      if (item['user_id'] == userId) item.remove('password');
    }
    await prefs.setString(_key, jsonEncode(raw));
  }

  static Future<void> remove(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _rawAccounts(prefs)
      ..removeWhere((item) => item['user_id'] == userId);
    await prefs.setString(_key, jsonEncode(raw));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static List<Map<String, dynamic>> _rawAccounts(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }
}
