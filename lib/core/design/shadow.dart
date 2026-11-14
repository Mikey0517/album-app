import 'package:flutter/material.dart';

import 'colors.dart';

class AppShadow {
  static const card = [
    BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 2)),
  ];

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
