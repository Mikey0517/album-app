import 'package:flutter/material.dart';

/// 把一条固定高度的横条做成吸顶 sliver。
///
/// 相册详情页的筛选条、日期分组头都用它：高度、吸顶行为只有一份实现，
/// 样式由传入的 child 决定（[AppSegmentedBarSurface] / DateHeader）。
class PinnedBarSliver extends StatelessWidget {
  final double height;
  final Widget child;

  const PinnedBarSliver({super.key, required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedBarDelegate(height: height, child: child),
    );
  }
}

class _PinnedBarDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _PinnedBarDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PinnedBarDelegate oldDelegate) {
    // 主题色在 build 时现取，文案不变也要重建。
    return height != oldDelegate.height || child != oldDelegate.child;
  }
}
