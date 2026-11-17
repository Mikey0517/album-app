import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LiquidGlassSettings;

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
const double appTabBarHaloAlpha = 0.10;

/// 文字/图标的极轻描边：同色、10%、0 偏移 1px 模糊，不发光、不加底色。
List<Shadow> appTabBarHalo(Color color) => [
      Shadow(color: color.withValues(alpha: appTabBarHaloAlpha), blurRadius: 1),
    ];

/// 胶囊内部 scrim 的不透明度：浅色 **76%**、深色 **82%**。
///
/// 根因不在文字色，而在底衬：玻璃后面是滚动的照片，合成亮度随内容在
/// 「纯黑照片 ≈ #BCBCBE」到「纯白照片 ≈ #F9FAFB」之间漂，固定文字色不可能
/// 同时在两端都够看。给文字描边/加粗只能救回零点几的对比度，唯一稳的做法是
/// 把材质本身的不透明度提到足够高，让合成底色基本恒定，再在这个稳定底色上
/// 选色——iOS 的 UITabBar 也是这么做的，不是给文字加描边。
///
/// 76%/82% 是「底衬够稳」与「还看得出是玻璃」的交点：背后内容的权重只剩
/// 24%/18%，上面那两端的差被压到 1/4；玻璃质感由 blur [appTabBarBlur] 与
/// 玻璃自己的折射/高光给，不靠把 scrim 让薄。
///
/// 两档**与玻璃档位无关**：premium 与磨砂回退用同一组数，切档时胶囊的底色
/// 不会跟着换，未选中文字也就不会「在某个档位突然看不清」。
const double appTabBarScrimAlphaLight = 0.76;
const double appTabBarScrimAlphaDark = 0.82;

/// 当前明暗模式下胶囊 scrim 的不透明度。
double appTabBarScrimAlpha() =>
    AppColors.isDark ? appTabBarScrimAlphaDark : appTabBarScrimAlphaLight;

/// 胶囊 scrim 的颜色：页面底色 + [appTabBarScrimAlpha]（合成公式见
/// app_tab_bar_contrast.dart）。
Color appTabBarScrimColor() =>
    AppColors.bgPage.withValues(alpha: appTabBarScrimAlpha());

/// 胶囊玻璃的模糊半径：**24**。
///
/// scrim 提到 76%/82% 之后，背后内容只剩 24%/18% 的权重，模糊大了也揉不出
/// 新东西；提到 24 是为了把那 24% 充分揉开——同一段照片的明暗细节被抹平成
/// 一块底色，比 scrim 本身更「抗」复杂背景（白墙照片和深色照片的差别不再有
/// 纹理，只剩一点整体明暗）。
const double appTabBarBlur = 24;

/// 胶囊自己的玻璃参数：光学档位照旧（premium 折射 / 拿不到时磨砂回退），
/// 只把模糊换成 [appTabBarBlur]。
///
/// 为什么在这里 copy 一份而不是改 [appGlassChromeSettings] /
/// [appGlassSettings]：那两个函数是**所有** chrome（筛选条、多选底栏、
/// 上传按钮、强制更新弹窗）共用的参数，胶囊要的是「重 scrim + 大模糊」这一
/// 套特例，不能连带改掉别人。档位判定与 [AppGlassSurface] 内部那条
/// （preferPremium 为真时 [appGlassPremiumAvailable]）完全一致，所以这里取的
/// 参数就是那个表面真正会用的参数。
LiquidGlassSettings appTabBarGlassSettings(BuildContext context) {
  final base = appGlassPremiumAvailable(context)
      ? appGlassChromeSettings(context)
      : appGlassSettings(context);
  return base.copyWith(blur: appTabBarBlur);
}

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
/// 1. 玻璃内部叠一层**重** scrim（[AppGlassSurface.scrim]）：玻璃后面是滚动的
///    照片，白墙照片与深色照片的合成亮度差得远，固定文字色不可能两端都够看。
///    所以先让底衬稳定——[appTabBarScrimAlpha]（76%/82%，两个玻璃档位同一组数）
///    + [appTabBarBlur]（24），把背后内容的权重压到 24%/18% 并揉平；
/// 2. 未选中文字/图标带一圈同色 1px 描边（[appTabBarHalo]，10% 透明度）：
///    内容颜色跳到极端时，字边缘也不会糊进去。都是「刚好够」，不做发光。
///
/// 顺序很重要：**先把底衬钉住，再在它上面选色**。反过来的做法（固定文字色、
/// 靠描边/加粗去追背景）在纯黑与纯白照片之间必然有一端失效。
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
        // 一块不随内容跳的底衬。厚度不跟档位走（premium 与回退同一组数，
        // 见 [appTabBarScrimAlpha]）；模糊由 [appTabBarGlassSettings] 提到 24。
        scrim: true,
        settings: appTabBarGlassSettings(context),
        scrimColor: appTabBarScrimColor(),
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
