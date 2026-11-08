import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { light, dark, system }

class AppThemeController {
  static const String _key = 'app_theme_mode';
  static final ValueNotifier<AppThemeMode> mode =
      ValueNotifier<AppThemeMode>(AppThemeMode.system);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      mode.value = AppThemeMode.values.firstWhere(
        (value) => value.name == saved,
        orElse: () => AppThemeMode.system,
      );
    } catch (_) {
      mode.value = AppThemeMode.system;
    }
  }

  static Future<void> setMode(AppThemeMode value) async {
    mode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.name);
    } catch (_) {
      // 设置持久化失败不影响本次生效。
    }
  }

  static String label(AppThemeMode value) {
    return switch (value) {
      AppThemeMode.light => '浅色',
      AppThemeMode.dark => '深色',
      AppThemeMode.system => '跟随系统',
    };
  }

  static bool isDark() {
    final platform =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return mode.value == AppThemeMode.dark ||
        (mode.value == AppThemeMode.system && platform == Brightness.dark);
  }
}
