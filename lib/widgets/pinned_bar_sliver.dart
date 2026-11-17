import 'package:flutter/material.dart';

import '../core/design/colors.dart';

/// 把一条固定高度的横条做成吸顶 sliver。
///
/// 相册详情页的筛选条、日期分组头都用它：高度、吸顶行为、底衬色只有一份
/// 实现，样式由传入的 child 决定（[AppSegmentedBarSurface] / DateHeader）。
///
/// 底衬默认是页面底色：日期分组头这种「压住照片的小标签」需要一块实底，否则
/// 滚动的内容会在字下面穿过去。**筛选条不传底衬**（[background] 传透明）——
/// 它自己那层 [AppSegmentedBarSurface] 是「透明 + 极轻模糊」，模糊必须能采到
/// 这一层下面的滚动内容，所以这里不能再垫一层不透明色（垫了模糊就只采到
/// 这块底色，等于什么都没做）。
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
