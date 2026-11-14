import 'package:flutter/material.dart';

import '../core/design/colors.dart';

/// 把一条固定高度的横条做成吸顶 sliver。
///
/// 相册详情页的筛选条、日期分组头都用它：高度、吸顶行为、**不透明底色**
/// 只有一份实现，样式由传入的 child 决定（[AppSegmentedBarSurface] /
/// DateHeader）。
///
/// 底色必须垫在这一层：吸顶条下面是滚动的照片，任何一处没垫实都会在接缝
/// 处透出内容，看起来就是「吸顶条和内容之间有一条缝」。
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

  /// 吸顶条底色：默认与页面背景同色，且不透明。
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
