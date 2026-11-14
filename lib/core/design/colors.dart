import 'package:flutter/material.dart';

import '../app_accent_controller.dart';
import 'accent.dart';

/// 全局调色板。通过 [setDark] 切换浅色/深色，主题变化时整棵界面重建。
///
/// 主色不再是写死的常量：[primary] 每次读取时都从 [AppAccentController]
/// 取当前主题色，再按明暗模式做可读性微调。调用点继续写 `AppColors.primary`，
/// 一行都不用改，换色后全局自动跟着变。
class AppColors {
  static bool _dark = false;

  static void setDark(bool value) {
    _dark = value;
  }

  static bool get isDark => _dark;

  /// 当前主题色（用户在「我的 → 主题色」选的种子色，经明暗模式微调）。
  static Color get primary => AppAccent.primary(
        AppAccentController.seed.value,
        isDark: _dark,
        pageBg: bgPage,
      );

  /// 主色的浅色底：选中底、进度条轨道、头像底等。
  static Color get primaryLight => AppAccent.surfaceTint(
        primary,
        isDark: _dark,
        surface: bgSurface,
      );

  static Color get bgPage =>
      _dark ? const Color(0xFF0E1118) : const Color(0xFFF7F8FA);
  static Color get bgSurface =>
      _dark ? const Color(0xFF171B24) : const Color(0xFFFFFFFF);
  static Color get bgElevated =>
      _dark ? const Color(0xFF1D2330) : const Color(0xFFFBFBFC);
  static Color get textPrimary =>
      _dark ? const Color(0xFFF2F4FA) : const Color(0xFF1A1D26);
  static Color get textSecondary =>
      _dark ? const Color(0xFFA8B0C0) : const Color(0xFF6B7280);
  static Color get textTertiary =>
      _dark ? const Color(0xFF7F889B) : const Color(0xFF9CA3AF);
  static Color get textInverse =>
      _dark ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF);
  static Color get divider =>
      _dark ? const Color(0xFF252C39) : const Color(0xFFF0F1F3);
  static Color get borderLight =>
      _dark ? const Color(0xFF2D3545) : const Color(0xFFE5E7EB);
  static Color get success =>
      _dark ? const Color(0xFF34D399) : const Color(0xFF10B981);
  static Color get warning =>
      _dark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);
  static Color get danger =>
      _dark ? const Color(0xFFF87171) : const Color(0xFFEF4444);
  static Color get mediaPlaceholder =>
      _dark ? const Color(0xFF232A37) : const Color(0xFFEFF1F5);
}
