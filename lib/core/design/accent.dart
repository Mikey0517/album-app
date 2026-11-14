import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 一个可选的主题色预设。
class AppAccentPreset {
  final String label;
  final Color color;

  const AppAccentPreset(this.label, this.color);
}

/// 主题色的纯计算层：预设表、HSV 取值、以及按明暗模式做的可读性微调。
///
/// 这里没有状态、不碰 SharedPreferences、也不 import [AppColors]，避免循环依赖。
/// 当前选中的种子色由 `AppAccentController` 持有，`AppColors.primary` 每次
/// build 时调用 [primary] 现算，所以所有调用点都不用改。
class AppAccent {
  AppAccent._();

  /// 品牌默认色：用户没选过主题色时沿用它。
  static const Color brand = Color(0xFF4A6CF7);

  /// 内置预设。顺序即选择器里的展示顺序。
  static const List<AppAccentPreset> presets = <AppAccentPreset>[
    AppAccentPreset('暖橙', Color(0xFFFF7A45)),
    AppAccentPreset('珊瑚红', Color(0xFFF5484A)),
    AppAccentPreset('琥珀', Color(0xFFF5A524)),
    AppAccentPreset('森林绿', Color(0xFF2FA84F)),
    AppAccentPreset('湖蓝', Color(0xFF2B7FFF)),
    AppAccentPreset('鸢紫', Color(0xFF7C5CFF)),
  ];

  /// 深色模式下的最小亮度。品牌色在深色下正好落在这条线上（≈ #8FA5FA），
  /// 比浅色品牌色亮一档：深色背景上主色要表达文字/图标，太暗就读不出来。
  static const double _darkMinLightness = 0.77;

  /// 深色背景上主色（当文字/图标用）的最小对比度，取 WCAG AA 正文值。
  static const double _darkMinContrast = 4.5;

  /// 浅色模式下近白自定义色的兜底下限：几乎看不见的主色压到刚好可辨。
  static const double _lightMinContrast = 1.9;

  /// 去掉 alpha 并夹到 0xFF：主题色必须不透明，半透明主色会穿透卡片底色。
  static Color clamp(Color value) =>
      Color(0xFF000000 | (value.toARGB32() & 0x00FFFFFF));

  /// 由 HSV 取值建色。滑块/持久化的原始值可能越界，先 clamp 再建色，
  /// 否则 HSVColor.fromAHSV 在 debug 下会直接断言失败。
  static Color fromHsv({
    required double hue,
    required double saturation,
    required double value,
  }) {
    final h = hue.isNaN ? 0.0 : hue.clamp(0.0, 360.0).toDouble();
    final s = saturation.isNaN ? 0.0 : saturation.clamp(0.0, 1.0).toDouble();
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    return HSVColor.fromAHSV(1.0, h, s, v).toColor();
  }

  static HSVColor hsvOf(Color color) => HSVColor.fromColor(clamp(color));

  static double relativeLuminance(Color color) {
    double channel(double c) => c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    final r = channel(color.r);
    final g = channel(color.g);
    final b = channel(color.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  static double contrastRatio(Color background, Color foreground) {
    final a = relativeLuminance(background);
    final b = relativeLuminance(foreground);
    final hi = math.max(a, b);
    final lo = math.min(a, b);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 运行时主色。
  ///
  /// 浅色模式尊重用户选的颜色（预设所见即所得）；深色模式把亮度抬到
  /// [_darkMinLightness] 起步，再按对比度继续提亮，避免深色背景上不可读。
  static Color primary(
    Color seed, {
    required bool isDark,
    required Color pageBg,
  }) {
    final base = clamp(seed);
    if (!isDark) {
      if (contrastRatio(Colors.white, base) >= _lightMinContrast) return base;
      // 只兜底“近白”这类在白底上几乎不可见的颜色。
      final hsl = HSLColor.fromColor(base);
      var lightness = hsl.lightness;
      var color = base;
      while (contrastRatio(Colors.white, color) < _lightMinContrast &&
          lightness > 0.3) {
        lightness -= 0.04;
        color = hsl.withLightness(lightness).toColor();
      }
      return color;
    }
    final hsl = HSLColor.fromColor(base);
    var lightness = math.max(hsl.lightness, _darkMinLightness);
    var color = hsl.withLightness(lightness).toColor();
    while (contrastRatio(pageBg, color) < _darkMinContrast &&
        lightness < 0.95) {
      lightness = math.min(0.95, lightness + 0.02);
      color = hsl.withLightness(lightness).toColor();
    }
    return color;
  }

  /// 主色的浅色底（选中底、进度条轨道、头像底等）：主色朝卡片底色混合。
  static Color surfaceTint(
    Color primary, {
    required bool isDark,
    required Color surface,
  }) =>
      Color.lerp(primary, surface, isDark ? 0.82 : 0.88)!;

  /// 压在任何主题色上仍然可读的前景色（色卡上的对勾用）。
  static Color onColor(Color background) =>
      relativeLuminance(background) > 0.45
          ? const Color(0xFF1A1D26)
          : Colors.white;
}
