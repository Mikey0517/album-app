import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/text_styles.dart';
import 'app_glass.dart';

/// 底部 tab 的一项。图标分选中/未选中两个变体（实心 / 线框）。
class AppBottomTabItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const AppBottomTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 悬浮胶囊式底部 tab：等宽三格、图标 + 文字。
///
/// 不再是贴边通栏：整条栏浮在页面底部，左右各留 [sideInset]，底部离安全区
/// 再留 [bottomGap]，四角是半径 [radius]（= 高度/2）的胶囊。玻璃底子和胶囊
/// 同形状（[AppGlassSurface] 收到同一个 radius）。
///
/// 选中态只改颜色：实心 / 线框图标切换 + [AppColors.primary] /
/// [AppColors.textSecondary]，点下去没有涟漪、没有底色、没有 hover 高亮
/// （[InkWell] 换成了无涟漪的 [GestureDetector] + 显式 [Semantics]）。
///
/// 玻璃不可用（没有自适应档位 / initialize 失败）或档位降到
/// [GlassQuality.minimal] 时，退化成同尺寸、同圆角的不透明
/// [AppColors.bgSurface] 加一圈细边——不会退回通栏。
class AppBottomTabBar extends StatelessWidget {
  /// 内容高度（胶囊高度，不含底部安全区与外边距）。
  static const double barHeight = 56;

  /// 胶囊离屏幕左右两边的边距。
  static const double sideInset = 18;

  /// 胶囊离底部安全区的间距。
  static const double bottomGap = 8;

  /// 胶囊圆角 = 高度/2，正好是 pill。
  static const double radius = barHeight / 2;

  /// 悬浮胶囊盖住页面内容的实际高度：胶囊 + 离安全区的间距 + 安全区本身。
  ///
  /// 页面（朋友圈 / 相册 / 我的）按它给列表留底部 padding，滚到底时最后
  /// 一条内容不会藏在胶囊下面。
  static double overlayInset(BuildContext context) =>
      barHeight + bottomGap + MediaQuery.viewPaddingOf(context).bottom;

  final List<AppBottomTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 单个 tab 的 key。没有 InkWell 可找了，测试用它在整条栏里定位三个等宽
  /// 格子。
  static Key tabKey(int index) => ValueKey<String>('bottom-tab-$index');

  /// 想用的玻璃档位；null = 跟随自适应上限。
  final GlassQuality? requestedQuality;

  const AppBottomTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.requestedQuality,
  });

  @override
  Widget build(BuildContext context) {
    // 安全区算进外间距：胶囊自己浮在安全区上面，不贴屏幕底边。
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final content = SizedBox(
      height: barHeight,
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++)
            Expanded(
              child: _TabButton(
                key: tabKey(index),
                item: items[index],
                selected: index == selectedIndex,
                onTap: () => onSelected(index),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sideInset,
        0,
        sideInset,
        bottomGap + safeBottom,
      ),
      child: AppGlassSurface(
        radius: radius,
        requestedQuality: GlassQuality.standard,
        useOwnLayer: false,
        child: content,
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final AppBottomTabItem item;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    // 选中只改颜色（图标实心化 + 主色），不加水波纹、不加背景块。
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.selectedIcon : item.icon,
              size: 22,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                fontSize: 10.5,
                height: 1.1,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
