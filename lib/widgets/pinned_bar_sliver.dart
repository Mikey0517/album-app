import 'package:flutter/material.dart';

import '../core/design/colors.dart';

/// 把一条固定高度的横条做成吸顶 sliver。
///
/// 相册详情页的筛选条、日期分组头都用它：高度、吸顶行为、底衬色只有一份
/// 实现，样式由传入的 child 决定（[AppSegmentedBarSurface] / DateHeader）。
///
/// **两个调用点现在都把底衬显式传透明**（[background] = `Colors.transparent`）：
/// 吸顶条垫一层页面底色之后，[AppGlassBackdrop] 的渐变（或背景图）到这里就被
/// 截成一条白杠；而且吸顶时是「不透明页面底色」，内容流里是「背景」，两者切换
/// 的那一下会跳。底衬于是交给 child 自己画——两条横条的 child
/// （[AppSegmentedBarSurface] / DateHeader）各带一层**主题色浅渐变**，吸顶版
/// 与内容流版因此是同一块材质。这也是 [color] 的 alpha = 0 时整层不画的原因。
class PinnedBarSliver extends StatelessWidget {
  final double height;
  final Widget child;
  final Color? background;

  const PinnedBarSliver({
    super.key,
    required this.height,
    required this.child,
    this.background,
  });

  /// 吸顶条底色：默认与页面背景同色，且不透明。传 alpha = 0 的颜色（比如
  /// `Colors.transparent`）就是「这一层不画」，把底衬完全交给 child。
  Color get color => background ?? AppColors.bgPage;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedBarDelegate(height: height, color: color, child: child),
    );
  }
}

class _PinnedBarDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Color color;
  final Widget child;

  const _PinnedBarDelegate({
    required this.height,
    required this.color,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // 透明底衬：整层不画（连 ColoredBox 都不挂），下面的内容才落进 child
    // 那层模糊的采样范围里。
    if (color.a == 0) return child;
    return ColoredBox(color: color, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedBarDelegate oldDelegate) {
    // 主题色在 build 时现取，文案不变也要重建。
    return height != oldDelegate.height ||
        color != oldDelegate.color ||
        child != oldDelegate.child;
  }
}
