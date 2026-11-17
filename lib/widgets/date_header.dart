import 'package:flutter/material.dart';

import '../core/design/bar_tint.dart';
import '../core/design/colors.dart';
import '../core/design/text_styles.dart';

/// 日期分组头：固定高度 + 左右内边距 + **主题色浅渐变**底衬。
///
/// 相册详情页与朋友圈相册都用 34 高（几何见
/// `features/album/album_timeline_layout.dart`，两页同一份）；朋友圈动态流
/// 的日期头高 36，也套这一层。
///
/// **底衬为什么是渐变而不是实底**：日期头压在 [AppGlassBackdrop] 的渐变（或
/// 用户挑的背景图）上，垫一层 [AppColors.bgPage] 实底之后，那条渐变到这里就
/// 被截成一条白杠——和分类筛选条是同一处毛病。现在改成主题色的浅渐变
/// （[BarTint]：浅色 0.10 → 0.02，深色 0.14 → 0.04），背景照样从条带里透上来，
/// 条带又有一层自己的色，滚动时不至于「字浮在照片上」。
///
/// **为什么没有模糊**：上一版是「透明 + blur 8」（`DateHeaderBlur`），用户
/// 反馈「模糊透明有点奇怪」。模糊层已经删除：本组件不包 [BackdropFilter]，
/// 底衬只有这一层渐变，吸顶版与内容流版因此**完全一致**（同一个组件、同一份
/// 参数），滚到吸顶阈值时不会换材质、也不会突变。
///
/// 高度、内边距、右侧数量都不受影响：底衬只换颜色，不碰几何。
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

  /// 底衬渐变：与分类筛选条是同一份（[BarTint.gradient]），两处不会各走各的。
  LinearGradient get gradient => BarTint.gradient;

  /// 文案样式：字号/字重照旧，只把颜色换成 [AppColors.textOnGlass]。
  ///
  /// [AppText.sectionLabel] 的 #8A93A6 是按纯色卡片挑的，落在新的主题色浅渐变
  /// 底衬上只有 **2.57:1**（浅色）/ 4.90:1（深色），浅色模式读不出来。
  /// [AppColors.textOnGlass] 在同一块底衬上是 5.45:1 / 6.94:1（实测见
  /// test/date_header_backdrop_test.dart）。
  TextStyle get textStyle =>
      AppText.sectionLabel.copyWith(color: AppColors.textOnGlass);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(gradient: gradient),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(child: Text(text, style: textStyle)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
