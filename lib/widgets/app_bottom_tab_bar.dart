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

/// 微信式底部 tab：等宽分格、图标 + 文字。
///
/// 玻璃用在「底子」上：整条底部栏是一块玻璃（满宽直角，铺满 56 + 安全区），
/// 里面三个 tab 只是普通图标 + 文字，选中=主题色实心图标，未选中=中性灰线框，
/// 没有滑块/胶囊指示器，也没有跟手动画。
///
/// 玻璃不可用（没有自适应档位 / initialize 失败）或档位降到
/// [GlassQuality.minimal] 时，退化成原来那块不透明 [AppColors.bgSurface]
/// 加顶部 1px 最浅分隔线——布局一模一样，只是没有玻璃质感。
class AppBottomTabBar extends StatelessWidget {
  /// 内容高度（不含底部安全区）。
  static const double barHeight = 56;

  final List<AppBottomTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

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
    // 安全区放在玻璃里面，玻璃自己铺满到屏幕底边。
    final content = SafeArea(
      top: false,
      child: SizedBox(
        height: barHeight,
        child: Row(
          children: [
            for (var index = 0; index < items.length; index++)
              Expanded(
                child: _TabButton(
                  item: items[index],
                  selected: index == selectedIndex,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      ),
    );

    // 静态 chrome，独此一块：自己开一层渲染上下文（它上面没有任何
    // LiquidGlassLayer 可以复用 backdrop）。
    return AppGlassSurface(
      radius: 0,
      requestedQuality: requestedQuality,
      useOwnLayer: true,
      // 退化到不透明表面时保留顶部那条 1px 最浅分隔线。
      border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      child: content,
    );
  }
}

class _TabButton extends StatelessWidget {
  final AppBottomTabItem item;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        highlightColor: AppColors.primary.withValues(alpha: 0.04),
        child: Semantics(
          button: true,
          selected: selected,
          label: item.label,
          excludeSemantics: true,
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
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
