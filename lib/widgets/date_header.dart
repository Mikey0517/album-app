import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/text_styles.dart';

/// 日期分组头：固定高度 + 左右内边距 + 不透明底色。
///
/// 相册详情页与朋友圈相册都用 34 高（几何见
/// `features/album/album_timeline_layout.dart`，两页同一份）；朋友圈动态流
/// 的日期头高 36，也套这一层。
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