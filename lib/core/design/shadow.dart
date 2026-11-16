import 'package:flutter/material.dart';

import 'colors.dart';

/// 卡片 / 列表的立体感：一层近、一层远，两层都靠 [BoxShadow] 静态绘制，
/// 不参与布局（阴影画在卡片外面，不会把尺寸撑大）。
///
/// 卡片仍然是 standard 磨砂（见 [AppGlassSurface.kCardQuality]，不回到
/// premium 的 capture 路径）；层次由「阴影 + 顶部内高光 + 1px 描边」这三层
/// 静态绘制叠出来，minimal / 无档位时阴影与描边照样在，只是没有模糊。
class AppShadow {
  /// 近层：blur 10 / y 3。浅色 8%，深色 16%——深色底上黑影本来就更难看见，
  /// alpha 适度提高才立得起来。
  static BoxShadow cardNear() => BoxShadow(
        color: Colors.black.withValues(alpha: AppColors.isDark ? 0.16 : 0.08),
        blurRadius: 10,
        offset: const Offset(0, 3),
      );

  /// 远层：blur 28 / y 12。浅色 5%，深色 10%。
  static BoxShadow cardFar() => BoxShadow(
        color: Colors.black.withValues(alpha: AppColors.isDark ? 0.10 : 0.05),
        blurRadius: 28,
        offset: const Offset(0, 12),
      );

  /// 卡片的两层阴影（近 → 远）。列表里的卡片都套这一份，不各调各的。
  static List<BoxShadow> get card => [cardNear(), cardFar()];

  /// FAB 的品牌色光晕跟着主题色走，否则换成绿色主题会拖一圈蓝影。
  static List<BoxShadow> get fab => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.10),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];
  static const dialog = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 32, offset: Offset(0, 12)),
  ];
}
