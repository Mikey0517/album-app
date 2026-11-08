import 'package:flutter/material.dart';

/// 全局调色板。通过 [setDark] 切换浅色/深色，主题变化时整棵界面重建。
class AppColors {
  static bool _dark = false;

  static void setDark(bool value) {
    _dark = value;
  }

  static bool get isDark => _dark;

  static Color get primary =>
      _dark ? const Color(0xFF8AA2FF) : const Color(0xFF4A6CF7);
  static Color get primaryLight =>
      _dark ? const Color(0xFF252D4A) : const Color(0xFFE8EDFE);
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
