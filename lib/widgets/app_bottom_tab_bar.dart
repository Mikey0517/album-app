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

/// 未选中项的颜色：在 [AppColors.textSecondary] 上往 [AppColors.textPrimary]
/// 压 18%。
///
/// 胶囊里是磨砂玻璃 + 42%/50% 的 scrim，底衬已经拉回页面底色附近，但
/// 中性灰 textSecondary（#6B7280）对这块底衬只有约 4.4:1——差一点点过不了
/// 4.5。压深这一档把余量做到约 5.3:1；深色模式同一条公式自动变亮（约 7.8:1）。
const double appTabBarInactiveContrastStep = 0.18;

/// 当前明暗模式下未选中项的颜色。
Color get appTabBarInactiveColor => Color.lerp(
      AppColors.textSecondary,
      AppColors.textPrimary,
      appTabBarInactiveContrastStep,
    )!;

/// 未选中项的对比保护：同色 1px 描边的不透明度（上限 12%，再高就成发光字）。
const double appTabBarHaloAlpha = 0.10;

/// 文字/图标的极轻描边：同色、10%、0 偏移 1px 模糊，不发光、不加底色。
List<Shadow> appTabBarHalo(Color color) => [
      Shadow(color: color.withValues(alpha: appTabBarHaloAlpha), blurRadius: 1),
    ];

/// 悬浮胶囊式底部 tab：等宽三格、图标 + 文字。
///
/// 不再是贴边通栏：整条栏浮在页面底部，左右各留 [sideInset]，底部离安全区
/// 再留 [bottomGap]，四角是半径 [radius]（= 高度/2）的胶囊。玻璃底子和胶囊
/// 同形状（[AppGlassSurface] 收到同一个 radius）。
///
/// 选中态只改颜色：实心 / 线框图标切换 + [AppColors.primary] /
/// [appTabBarInactiveColor]，点下去没有涟漪、没有底色、没有 hover 高亮
/// （[InkWell] 换成了无涟漪的 [GestureDetector] + 显式 [Semantics]）。
///
/// 可读性是这里唯一「加了东西」的地方，两条一起做：
/// 1. 玻璃内部叠一层低透明 scrim（[AppGlassSurface.scrim]）：玻璃后面的
///    内容是滚动的照片，颜色会变，未选中的灰字需要一个不跳的底衬。薄厚跟着
///    档位走：premium 20%/24%，磨砂回退 42%/50%；
/// 2. 未选中文字/图标带一圈同色 1px 描边（[appTabBarHalo]，10% 透明度）：
///    内容颜色跳到极端时，字边缘也不会糊进去。都是「刚好够」，不做发光。
///
/// **玻璃档位**：胶囊要 premium（折射/边缘扭曲），并且自建渲染层
/// （[usesOwnLayer]）——premium 的 per-widget settings 只在自建层里生效，
/// 而它又确实是页面里唯一一块静态 chrome，抓一次纹理不心疼。列表里的卡片
/// 一律还是 standard（见 [AppGlassSurface.preferPremium] 的注释）。
/// premium 不可用（非 Impeller / 自适应降档 / initialize 失败 / minimal）时，
/// [AppGlassSurface] 自己把整块退回磨砂实现，再不行退化成同尺寸、同圆角的
/// 不透明 [AppColors.bgSurface] 加一圈细边——不会退回通栏，也不会白屏。
///
/// **三个页面共用这一份参数**：朋友圈 / 相册 / 我的都由 [HomePage] 渲染
/// 同一个 [AppBottomTabBar] 实例（见 HomePage 的注释），页面自己不再画
/// footer。所以「同一组件、同一组参数、同一套 scrim 与档位」是结构上成立的，
/// [preferredQuality] / [usesOwnLayer] 这两个常量就是那份参数的唯一来源。
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
  /// 只给「必须完整露在胶囊上方」的东西用（右侧时间轴轨道、气泡这类不能被
  /// 玻璃压住的手势控件）。滚动内容**不用**它——见 [contentBottomInset]。
  static double overlayInset(BuildContext context) =>
      barHeight + bottomGap + MediaQuery.viewPaddingOf(context).bottom;

  /// 滚动内容自己的末尾留白：半个胶囊高（28）。
  ///
  /// 页面不再为胶囊整体让出 [overlayInset]：那样胶囊正下方永远是一块空
  /// 底色，磨砂没有可模糊的东西。留半个胶囊高就够——最后一项能滑到胶囊
  /// 下沿附近，滚的过程中内容一直从胶囊底下穿过。
  static const double contentBottomInset = barHeight / 2;

  final List<AppBottomTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 单个 tab 的 key。没有 InkWell 可找了，测试用它在整条栏里定位三个等宽
  /// 格子。
  static Key tabKey(int index) => ValueKey<String>('bottom-tab-$index');

  /// 想用的玻璃档位；null = [preferredQuality]（premium），拿不到时由
  /// [AppGlassSurface] 回退到磨砂档。
  final GlassQuality? requestedQuality;

  /// 胶囊想要的玻璃档位：premium（Impeller 全管线，折射/边缘扭曲）。
  ///
  /// 三个页面共用这一个数，改档位只改这里。
  static const GlassQuality preferredQuality = GlassQuality.premium;

  /// 胶囊自建渲染层：premium 的 per-widget settings 只在自建层里生效。
  ///
  /// 只有这一块静态 chrome 值得开；卡片仍然是 useOwnLayer: false。
  static const bool usesOwnLayer = true;

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
        requestedQuality: requestedQuality ?? preferredQuality,
        // 静态 chrome 优先 premium（折射）；拿不到时 AppGlassSurface 自己
        // 退回磨砂档 + 重 scrim，这里不用分支。
        preferPremium: true,
        useOwnLayer: usesOwnLayer,
        // 玻璃后面是滚动的照片：内部叠一层页面底色 scrim，未选中的灰字才有
        // 一块不随内容跳的底衬。厚度按档位取（premium 20%/24%，回退 42%/50%）。
        scrim: true,
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
    final color = selected ? AppColors.primary : appTabBarInactiveColor;
    // 同色极轻描边：两档同等清晰度，不做发光、不加背景块。
    final halo = appTabBarHalo(color);
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
              shadows: halo,
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
                shadows: halo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
