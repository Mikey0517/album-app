import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/text_styles.dart';

/// 日期分组头。朋友圈使用固定 36 高并吸顶；相册使用宽松上下留白。
class DateHeader extends StatelessWidget {
  final String text;
  final double? height;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  const DateHeader({
    super.key,
    required this.text,
    this.height = 36,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      color: AppColors.bgPage,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(child: Text(text, style: AppText.sectionLabel)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
