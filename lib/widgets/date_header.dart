import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/design/text_styles.dart';

/// 吸顶日期头底衬的模糊半径（sigma）。取值见 [DateHeaderBlur]。
const double kDateHeaderBlur = 8;

/// 日期分组头：固定高度 + 左右内边距 + **透明底衬**。
///
/// 相册详情页与朋友圈相册都用 34 高（几何见
/// `features/album/album_timeline_layout.dart`，两页同一份）；朋友圈动态流
/// 的日期头高 36，也套这一层。
///
/// **为什么底色是透明的**：日期头压在 [AppGlassBackdrop] 的渐变（或用户挑的
/// 背景图）上，垫一层 [AppColors.bgPage] 实底之后，那条渐变到这里就被截成一
/// 条白杠——和上一轮的分类筛选条是同一处毛病。透明之后渐变原样穿过，高度、
/// 文字、右侧数量都不变（底衬只改颜色，不碰内边距）。
///
/// 吸顶的那一条还要再兜一层模糊（滚过的照片会从字后面透出来），那一层由
/// [DateHeaderBlur] 单独挂在这之上：本组件自己不模糊，内容流里的日期头下面
/// 本来也没有滚动内容。
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

  /// 底衬颜色：只有这一处定义，alpha = 0（完全透明）。
  ///
  /// 吸顶 sliver（[PinnedBarSliver]）读到 alpha = 0 就整层不画，模糊层因此能
  /// 采到这条带子下面真正的滚动内容，而不是一块底色。
  Color get color => Colors.transparent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      color: color,
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

/// 吸顶日期头的「透明 + 极轻模糊」底衬：一条 38 高的模糊层，铺满整条。
///
/// 只套在**吸顶**的日期头上（[timelineDateHeaderSliver] 的 pinned 分支、动态流
/// 的吸顶日期头）：透明之后滚过的照片会从字后面透出来，纯透明时那是一条条看得
/// 清清楚楚的纹理，字反而糊在照片里。实测（4px 黑白条纹替身压在条带下、量条带
/// 内相邻像素的平均亮度差，见 test/date_header_backdrop_test.dart）：
/// - 纯透明：0.2092 —— 条纹一条条看得清清楚楚，字糊在纹理里；
/// - blur 8：0.0103；
/// - blur 12：0.0102 —— 只比 blur 8 好 1%，没必要再加。
/// 不透明底衬（对照组）是 0.0046~0.0096（文字线以外）。0.0103 已经和它同一档，
/// 所以取 [kDateHeaderBlur] = 8：纹理被揉开只剩一层柔和色雾，背景渐变照样穿过
/// （模糊对渐变几乎没有影响）。
///
/// 它是**单独一层**，不倚赖 [PinnedBarSliver] 的底衬：那一层 alpha = 0 时整层
/// 不画，模糊只能挂在这之上（挂在下面的话糊的是那条不存在的底色）。
class DateHeaderBlur extends StatelessWidget {
  final Widget child;

  /// 模糊半径（sigma）；<= 0 表示不模糊（纯透明，返回 child 本身）。
  final double blur;

  const DateHeaderBlur({
    super.key,
    required this.child,
    this.blur = kDateHeaderBlur,
  });

  /// 模糊层的 key：测试用它断言「吸顶日期头带一层轻模糊」。
  static const Key blurKey = ValueKey<String>('date-header-blur');

  @override
  Widget build(BuildContext context) {
    if (blur <= 0) return child;
    // 铺满整条（含下方 4 的留白）：只糊文字区的话，条带上沿会留一条锋利的内容，
    // 比整条不糊更脏。
    return ClipRect(
      child: BackdropFilter(
        key: blurKey,
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: child,
      ),
    );
  }
}
