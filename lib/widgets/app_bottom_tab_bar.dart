import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LiquidGlassSettings;

import '../core/design/colors.dart';
import 'app_chrome_glass_bar.dart';
import 'app_glass.dart';
import 'app_glass_tone.dart';

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
/// 压一档，**档位按最坏的底衬定**。
///
/// 文字落上去的不是页面底色，而是「[appTabBarScrimAlpha] 的页面底色叠在照片
/// 上」。照片可以是纯白也可以是纯黑，合成底衬就在两端之间：
/// 浅色 ≈ #F9FAFB（纯白照片）～ #BCBCBE（纯黑照片），
/// 深色 ≈ #393C42（纯白照片）～ #0B0E14（纯黑照片）。
///
/// - 浅色 0.50 → 文字 #424853：对纯黑照片 4.89:1、对纯白照片 8.82:1。
///   旧的 0.18（#5C6370）在纯黑照片上只有 3.21:1——这就是「复杂背景下看不清」
///   的那个数；
/// - 深色 0.18 → 文字 #B5BCCA：最坏（纯白照片）也有 5.82:1，已经过线，
///   所以深色模式的观感保持原样，不为凑一个统一档位去洗亮未选中态。
///
/// 数字由 test/footer_contrast_test.dart 逐条钉住（浅/深 × 白/黑/红/蓝）。
const double appTabBarInactiveContrastStepLight = 0.50;
const double appTabBarInactiveContrastStepDark = 0.18;

/// 当前明暗模式下未选中项的颜色。
Color get appTabBarInactiveColor => Color.lerp(
      AppColors.textSecondary,
      AppColors.textPrimary,
      AppColors.isDark
          ? appTabBarInactiveContrastStepDark
          : appTabBarInactiveContrastStepLight,
    )!;

/// 未选中项的对比保护：同色 1px 描边的不透明度（上限 12%，再高就成发光字）。
///
/// 与三处吸顶条的描边同源：[kAppChromeHaloAlpha]（见 app_chrome_glass_bar.dart）。
const double appTabBarHaloAlpha = kAppChromeHaloAlpha;

/// 文字/图标的极轻描边：同色、10%、0 偏移 1px 模糊，不发光、不加底色。
List<Shadow> appTabBarHalo(Color color) => appChromeHalo(color);

/// 胶囊内部 scrim 的不透明度：**与其余 chrome 同一组数**
/// （[appGlassChromeScrimAlphaLight] / [appGlassChromeScrimAlphaDark]，
/// 现为 0.55 / 0.55 = 折射可见度 45%）。
///
/// 上一轮这里是 0.76 / 0.82：为了让未选中灰字在复杂背景下够稳，把合成底衬压到
/// 基本恒定，代价是 premium 的折射只剩 24% / 18% 的权重——真机上几乎看不见。
/// 这一轮按需求把 45% 的背景权重还给折射，底衬稳定性与文字对比度的代价由
/// test/footer_contrast_test.dart 逐条实测（四种极端背景 × 明暗），补偿方案
/// （甲/乙）也钉在那里，等产品决定。
///
/// 两档**与玻璃档位无关**：premium 与磨砂回退用同一组数，切档时胶囊的底色
/// 不会跟着换，未选中文字也就不会「在某个档位突然看不清」。
///
/// 回退：把这两个常量指回 [appGlassChromeScrimAlphaLight]/[appGlassChromeScrimAlphaDark]
/// 之外的值即可（上一轮是 0.76 / 0.82）。
const double appTabBarScrimAlphaLight = appGlassChromeScrimAlphaLight;
const double appTabBarScrimAlphaDark = appGlassChromeScrimAlphaDark;

/// 当前明暗模式下胶囊 scrim 的不透明度。
///
/// 唯一来源是 [appChromeScrimAlpha]（= chrome 那一组数）：footer 与三处吸顶条
/// 取同一个函数，不存在第二份 scrim。
double appTabBarScrimAlpha() => appChromeScrimAlpha();

/// 胶囊 scrim 的颜色：页面底色 + [appTabBarScrimAlpha]（合成公式见
/// app_tab_bar_contrast.dart）。
Color appTabBarScrimColor() => appChromeScrimColor();

/// 胶囊玻璃的模糊半径：**2**（= [appGlassChromeBlur]，premium 的最低档）。
///
/// 别名于 [appChromeBlur]：footer 与三处吸顶条同一个数。
///
/// 上一轮是 24：scrim 76%/82% 时背后只剩 24%/18% 的权重，糊大一点没代价，
/// 还能把照片纹理揉成一块底色。scrim 让到 55% 之后，那 45% 正是**要给折射用**
/// 的内容——再糊 24，斜面采样到的位移被抹平，「45% 可见度」就退化成一块更亮的
/// 灰板。所以模糊压到与其余 chrome 相同的最低档。
const double appTabBarBlur = appChromeBlur;

/// 胶囊自己的玻璃参数：光学档位照旧（premium 折射 / 拿不到时磨砂回退），
/// 只把模糊换成 [appTabBarBlur]。
///
/// 为什么在这里 copy 一份而不是改 [appGlassChromeSettings] /
/// [appGlassSettings]：那两个函数是**所有** chrome（筛选条、多选底栏、
/// 上传按钮、强制更新弹窗）共用的参数，胶囊只把模糊钉成 [appTabBarBlur]
/// 这一档（现在是和 chrome 相同的 2，给回退留一个按钮），不能连带改掉别人。
/// 档位判定与 [AppGlassSurface] 内部那条
/// （preferPremium 为真时 [appGlassPremiumAvailable]）完全一致，所以这里取的
/// 参数就是那个表面真正会用的参数。
LiquidGlassSettings appTabBarGlassSettings(BuildContext context) =>
    appChromeGlassSettings(context);

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
/// 可读性与折射是一对矛盾，这里两边各留一半：
/// 1. 玻璃内部叠一层 scrim（[AppGlassSurface.scrim]）：玻璃后面是滚动的照片，
///    白墙照片与深色照片的合成亮度差得远。[appTabBarScrimAlpha]（0.55，与其余
///    chrome 同一组数）+ [appTabBarBlur]（2）把背后内容的权重定在 45%——
///    这正是折射可见度（[appGlassChromeRefractionVisibility]）：底衬不再恒定
///    （代价见 [appGlassChromeScrimAlphaLight] 的实测数字），折射则真的能看见；
/// 2. 未选中文字/图标带一圈同色 1px 描边（[appTabBarHalo]，10% 透明度）：
///    内容颜色跳到极端时，字边缘也不会糊进去。都是「刚好够」，不做发光。
///
/// 上一轮的顺序是「先把底衬钉死（scrim 76%/82%），再在它上面选色」——底衬稳
/// 了，折射也没了。这一轮把 45% 还给折射，文字对比度的缺口用实测数字摊开，
/// 补偿方案（甲 halo / 乙 压深未选中色）等产品定，见
/// test/footer_contrast_test.dart。
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

  /// 胶囊想要的玻璃档位：premium（Impeller 全管线，折射/边缘扭曲）。
  ///
  /// 三个页面共用这一个数，改档位只改 [AppChromeGlassBar.preferredQuality]
  /// ——footer 与三处吸顶条是同一份材质，档位不可能只改其中一个。
  static const GlassQuality preferredQuality = AppChromeGlassBar.preferredQuality;

  /// 胶囊自建渲染层：premium 的 per-widget settings 只在自建层里生效。
  ///
  /// 只有静态 chrome 值得开；卡片仍然是 useOwnLayer: false。footer 与三处
  /// 吸顶条取同一个数（[AppChromeGlassBar.usesOwnLayer]）。
  static const bool usesOwnLayer = AppChromeGlassBar.usesOwnLayer;

  const AppBottomTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // 安全区算进外间距：胶囊自己浮在安全区上面，不贴屏幕底边。
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    // 材质整个交给 [AppChromeGlassBar]（与三处吸顶条同一份）：圆角是胶囊，
    // 其余参数一字不差。未选中文字/图标的墨色跟着**背景合成亮度**走（方案 C）：
    // 采样一变就重建这 3 个格子，取舍见 app_glass_tone.dart；选中态始终是主题色。
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sideInset,
        0,
        sideInset,
        bottomGap + safeBottom,
      ),
      child: AppChromeGlassBar(
        radius: radius,
        builder: (context, ink) => SizedBox(
          height: barHeight,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: _TabButton(
                    key: tabKey(index),
                    item: items[index],
                    selected: index == selectedIndex,
                    ink: ink,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final AppBottomTabItem item;
  final bool selected;

  /// 未选中文字/图标的墨色（由 [appGlassToneBuilder] 按背景亮度挑好）。
  final Color ink;

  final VoidCallback onTap;

  const _TabButton({
    super.key,
    required this.item,
    required this.selected,
    required this.ink,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : ink;
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
              // footer 未激活那一套（字号/行高/字重与三处吸顶条同一个来源）。
              style: appChromeLabelStyle(color, shadows: halo),
            ),
          ],
        ),
      ),
    );
  }
}
