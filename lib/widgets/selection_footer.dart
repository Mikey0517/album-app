import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/text_styles.dart';
import 'app_bottom_tab_bar.dart';
import 'app_glass.dart';

/// 多选底栏上的一个操作：图标 + 文字。
class SelectionFooterAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// 危险动作（删除）：用 [AppColors.danger]，其余走中性的玻璃正文色。
  final bool danger;

  const SelectionFooterAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.danger = false,
  });
}

/// 多选态的浮动胶囊底栏（下载 / 移动 / 删除 / 分享）：**和底部 footer 同一块材质**。
///
/// 几何、档位、scrim 全部直接引用 [AppBottomTabBar] 的常量：左右各留
/// [sideInset]，底部离安全区再留 [bottomGap]，四角半径 = 高度/2，整条就是一枚
/// 胶囊。护栏 [AppBottomTabBar] 改一次参数，这里跟着走，不会分叉出第二套。
///
/// 里面四个操作等宽（[Expanded]）：图标在上、文字在下，居中；选中/危险动作只
/// 改颜色——普通操作 [appTabBarInactiveColor]（和底部 tab 的未选中态同一档，
/// 对玻璃底衬约 5.3:1），危险动作（删除）[AppColors.danger]，禁用
/// [AppColors.textTertiary]。没有 InkWell、没有水波纹、没有底色块。
///
/// **玻璃降级**：[AppGlassSurface] 自己处理。premium 不可用时退回磨砂档
/// （[appGlassSettings] + 重 scrim），连磨砂都跑不了（注入 minimal / 平台不支持
/// shader）时退成**同尺寸、同圆角**的不透明 [AppColors.bgSurface] + 1px 细边：
/// 布局一模一样，不退回通栏，也不白屏。
class SelectionFooter extends StatelessWidget {
  /// 胶囊高度（不含外边距与安全区），与底部 footer 同高。
  static const double barHeight = AppBottomTabBar.barHeight;

  /// 胶囊离屏幕左右两边的边距：与底部 footer 相同（18）。
  static const double sideInset = AppBottomTabBar.sideInset;

  /// 胶囊离底部安全区的间距：与底部 footer 相同（8）。
  static const double bottomGap = AppBottomTabBar.bottomGap;

  /// 胶囊圆角 = 高度/2，正好是 pill。
  static const double radius = barHeight / 2;

  /// 与底部胶囊同档：premium（拿不到时由 [AppGlassSurface] 自己退档）。
  static const GlassQuality preferredQuality = AppBottomTabBar.preferredQuality;

  /// 自建渲染层：和底部胶囊一样，premium 的 per-widget settings 只在自建层
  /// 里生效，而这条栏也是页面里的一块静态 chrome。
  static const bool usesOwnLayer = AppBottomTabBar.usesOwnLayer;

  /// 单个操作按钮的 key：测试用它在胶囊里量四个等宽的格子。
  static Key actionKey(int index) => ValueKey<String>('selection-action-$index');

  final List<SelectionFooterAction> actions;

  /// 是否在底部再让出安全区（低部手势条）。为 true 时胶囊浮在安全区上面。
  final bool safeArea;

  const SelectionFooter({
    super.key,
    required this.actions,
    this.safeArea = false,
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom =
        safeArea ? MediaQuery.viewPaddingOf(context).bottom : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sideInset,
        0,
        sideInset,
        bottomGap + safeBottom,
      ),
      child: AppGlassSurface(
        radius: radius,
        requestedQuality: preferredQuality,
        // 静态 chrome：优先 premium（折射），拿不到时 AppGlassSurface 自己
        // 退回磨砂档 + 重 scrim，这里不用分支。
        preferPremium: true,
        useOwnLayer: usesOwnLayer,
        // 玻璃后面是滚动的照片：内部叠一层页面底色 scrim，文字才有不随内容
        // 跳的底衬。薄厚跟着档位走（premium 20%/24%，磨砂回退 42%/50%）。
        scrim: true,
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              for (var index = 0; index < actions.length; index++)
                Expanded(
                  child: _ActionButton(
                    key: actionKey(index),
                    action: actions[index],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final SelectionFooterAction action;

  const _ActionButton({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    final color = !enabled
        ? AppColors.textTertiary
        : action.danger
            ? AppColors.danger
            : appTabBarInactiveColor;
    // 同色极轻描边（10%）：内容颜色跳到极端时字边缘也不会糊进玻璃里。
    final halo = enabled ? appTabBarHalo(color) : null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: action.label,
      onTap: action.onTap,
      excludeSemantics: true,
      // 无涟漪：和底部 tab 一致，点下去只有颜色/缩放的语义反馈。
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, size: 22, color: color, shadows: halo),
            const SizedBox(height: 3),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                fontSize: 11,
                height: 1.1,
                fontWeight: FontWeight.w500,
                color: color,
                shadows: halo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
