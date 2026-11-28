import 'package:flutter/material.dart';

import '../core/design/bar_tint.dart';
import '../core/design/colors.dart';
import '../core/formatters.dart';
import 'app_bottom_tab_bar.dart';
import 'app_chrome_glass_bar.dart';

/// 页内筛选条的统一高度：相册详情页（以及选封面时的筛选）都用它。
///
/// 注意：它只用于**页内筛选**（全部 / 照片 / 视频）。相册总页的
/// 朋友圈 / 家庭 / 私人 相册是「层级」，用 [AppCategoryMenu] 的标题下拉，
/// 不要用这条分段条——层级和筛选看起来必须不一样。
const double kAppSegmentedBarHeight = 46;

/// 选中段文字在**本条内**的加深比例：把 [AppColors.primary] 往黑色混这么多。
///
/// 底衬是主题色自己的浅渐变（[BarTint]），选中文案直接写 primary 只有 **3.85:1**
/// （浅色）：primary 对纯页面底色本来就只有 4.13:1，渐变再花掉 0.28。这里不动
/// 全局主题色（底部 tab、按钮都在用），只在这条带子里把它混黑一成二：浅色
/// **4.75:1**（最浓的那条扫描线上 4.52:1）、深色 **5.46:1**（最浓处 4.98:1），
/// 两条都过 WCAG AA 4.5。断言见 test/segmented_bar_backdrop_test.dart。
const double kSegmentedSelectedInkDarken = 0.12;

/// 当前明暗模式下选中段的文字色 = 主题色在本条内混黑 [kSegmentedSelectedInkDarken]。
Color get segmentedSelectedInk => Color.lerp(
      AppColors.primary,
      const Color(0xFF000000),
      kSegmentedSelectedInkDarken,
    )!;

/// 吸顶条内部内容带的高度：46 减去上下各 7 的内边距。
///
/// 内容带只是四段文字所在的高度，本身不画底子；底子是整条筛选条后面的
/// 玻璃（[AppChromeGlassBar]）。
const double kAppSegmentedBarPillHeight = kAppSegmentedBarHeight - 14;

/// 分段条上的一段：文案 + 可选数量。
///
/// 数量为 0 也照常显示——「视频 0」本身就是有用信息，不用先藏起来。
class AppSegmentedItem {
  final String label;
  final int? count;

  const AppSegmentedItem(this.label, {this.count});
}

/// 紧凑分段条（全部 / 照片 / 动态照片 / 视频）：**文字直接落在底衬上**。
///
/// 视觉只有两条规则：
/// 1. 底子由外面那层 [AppSegmentedBarSurface] 画：吸顶那一份是底部 footer 同款
///    玻璃，非吸顶那一份是主题色浅渐变（[BarTint]）。这条栏自己**不包材质**：
///    每一段的容器里没有底色块、没有玻璃，只有文字与数量；
/// 2. 选中态**只用文字颜色**表达：选中段的文案与数量换成主题色（本条内局部加深
///    [segmentedSelectedInk]）。没有实心胶囊、没有底色块、没有水波纹——和底部
///    tab 的选中态是同一种语言。
///
/// 未选中的文字有两套，跟着底衬走：
/// - 玻璃上（吸顶那一份）：与 footer 未激活标签同一套——自动墨色
///   [appGlassToneInk] + 同一档字号/字重（[appChromeLabelStyle]）；
/// - 浅渐变上（非吸顶那一份）：[appTabBarInactiveColor] 与
///   [AppColors.textOnGlass]，字号大一号。
///
/// **玻璃为什么现在敢回来**：真机上这条胶囊早先在下拉刷新时会整块发黑——premium
/// 档走「capture 背景纹理」那条管线，玻璃层被重建的那一帧采到未就绪的纹理，叠上
/// tint 就是一块近黑。现在玻璃层挂常量 key 的 RepaintBoundary（[AppChromeGlassBar]），
/// 刷新全程是同一个 Element，capture 不会重抓，黑条那一帧就不存在。
/// 复现与回归见 test/refresh_black_bar_test.dart。
class AppSegmentedBar extends StatelessWidget {
  /// 整条内容带的 key（原来是玻璃胶囊的位置）：测试用它量高度与宽度。
  static const Key surfaceKey = ValueKey<String>('segmented-bar-content');

  /// 单段的 key：量文案、去掉填充块这类断言用。
  static Key segmentKey(int index) => ValueKey<String>('segmented-item-$index');

  final List<AppSegmentedItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// 深色底（隐藏空间这类纯黑页面）：文字用浅色、选中用主题色，不铺浅渐变。
  final bool onDark;

  const AppSegmentedBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) segments.add(const SizedBox(width: 6));
      segments.add(
        _Segment(
          key: segmentKey(i),
          item: items[i],
          selected: i == selectedIndex,
          onTap: () => onChanged(i),
          onDark: onDark,
        ),
      );
    }
    final row = Row(mainAxisSize: MainAxisSize.min, children: segments);
    return SizedBox(
      key: surfaceKey,
      height: kAppSegmentedBarPillHeight,
      // 靠左排：分类是「一组筛选项」，要从条带左边读起，不是一行居中的标题。
      // 低分辨率窄屏上宁可横滑也不压字。
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: row,
        ),
      ),
    );
  }
}

/// 分段条的容器：统一高度、内边距；**吸顶那一份是一整块玻璃里的一行，非吸顶
/// 那一份是主题色浅渐变**。
///
/// **材质只有一种来源**：这一层自己不画玻璃。
/// - 相册吸顶区的分类行套在 [AppChromeGlassBar] 的 [AppChromeInk] 里（玻璃与
///   墨色都由那一块给，分类行与日期行共用）——此时它只排内容；
/// - 选封面时套在 AppBar.bottom 里（它背后没有内容经过，不需要材质），此时它
///   铺主题色浅渐变。
/// 两处都用这一层，高度与内边距才不会各写各的。
///
/// **为什么不再是 [AppColors.bgPage] 实底**：吸顶条是一条横贯整屏的窄带，垫成
/// 页面底色之后，[AppGlassBackdrop] 的渐变（或用户挑的背景图）到这里就被截成
/// 一条白杠——从相册封面往下看，页面上半段是渐变、这一条是纯色，接缝比「透出
/// 内容」更刺眼。
///
/// **为什么从「透明 + blur 8」换成浅渐变**：用户反馈「模糊透明有点奇怪」——
/// 那层雾既挡不住滚过的内容（实测条纹纹理只从 0.2096 掉到 0.0060 是靠 blur，
/// 而 blur 本身看着就是一层糊），又没有自己的颜色。现在底衬是主题色本身，只是
/// 很淡：纵向 alpha 浅色 0.10 → 0.02、深色 0.14 → 0.04（参数只有一份，见
/// [BarTint]，日期条用的是同一套）。条带因此有一层自己的色，页面背景的渐变/
/// 图片仍从渐变里隐约透上来，**没有任何 [BackdropFilter]**。
///
/// 渐变铺满整条（46 高，含上下各 7 的内边距），不是只画中间那 32——否则条带
/// 上下边缘会各留一条没被染过色的内容。
class AppSegmentedBarSurface extends StatelessWidget {
  final Widget child;

  const AppSegmentedBarSurface({super.key, required this.child});

  /// 不在玻璃里时那一份底衬渐变：与日期分组条是同一份（[BarTint.gradient]）。
  ///
  /// 在一整块玻璃里时它不画渐变——底衬是 [AppChromeGlassBar] 的玻璃。
  LinearGradient get gradient => BarTint.gradient;

  /// 内容内边距：上下各 7（46 - 14 = 32 的内容带）。
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(12, 7, 12, 7);

  @override
  Widget build(BuildContext context) {
    // 已经在一整块玻璃里（相册吸顶区的分类行，[AppChromeInk] 在祖先里）：
    // 材质与墨色都由那块玻璃给，这一层只排内容——不画渐变、也不再包一层
    // 玻璃。两条吸顶条各自画材质时，那两层就是两行之间那条接缝。
    if (AppChromeInk.maybeOf(context) != null) {
      return SizedBox(
        height: kAppSegmentedBarHeight,
        width: double.infinity,
        child: Padding(padding: contentPadding, child: child),
      );
    }
    // 不在玻璃里（选封面页的 AppBar.bottom）：渐变铺满整条（含上下 7 的
    // 内边距），内缩的只是内容。
    return SizedBox(
      height: kAppSegmentedBarHeight,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: Padding(padding: contentPadding, child: child),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final AppSegmentedItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool onDark;

  const _Segment({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final count = item.count;
    // 两种底衬、两套文字：
    // - 吸顶那一份是玻璃（[AppChromeInk] 在祖先里）：文字用**footer 未激活那
    //   一套**——自动墨色 + 与 footer 标签同字号/字重（[appChromeLabelStyle]）；
    // - 非吸顶那一份是主题色浅渐变：沿用原来那套（未选中 [appTabBarInactiveColor]，
    //   数量 [AppColors.textOnGlass]），字大一号。
    final glassInk = AppChromeInk.maybeOf(context);
    final Color color;
    final TextStyle style;
    final TextStyle countStyle;
    if (onDark) {
      // 纯黑页面：未选中浅白、选中主题色；数量跟着正文走，只降一点亮度。
      color = selected ? AppColors.primary : Colors.white.withValues(alpha: 0.78);
      final countColor = selected
          ? AppColors.primary
          : Colors.white.withValues(alpha: 0.55);
      final halo = appTabBarHalo(color);
      style = TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: color,
        shadows: halo,
      );
      countStyle = TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: countColor,
        shadows: halo,
      );
    } else if (glassInk != null) {
      // 选中段仍用主题色（本条内局部加深 [segmentedSelectedInk]），未选中段与
      // 数量用与 footer 同一档的自动墨色。
      color = selected ? segmentedSelectedInk : glassInk;
      style = appChromeLabelStyle(color, shadows: appChromeHalo(color));
      countStyle = style;
    } else {
      // 选中只改颜色：主题色在本条内局部加深（[segmentedSelectedInk]），未选中用
      // 和底部 tab 同一档的中性灰。
      color = selected ? segmentedSelectedInk : appTabBarInactiveColor;
      // 数量：未选中用 [AppColors.textOnGlass]；选中跟文案同色——降透明度
      // （0.72 / 0.85 / 0.9）在这层浅渐变上只有 2.6~3.9:1，只有满不透明才过 4.5。
      // 主次靠字号（11 vs 13）与字重表达，不靠把颜色调淡。
      final countColor = selected ? color : AppColors.textOnGlass;
      // 同色极轻描边：底衬上的小字边缘不会糊进去，不做发光。
      final halo = appTabBarHalo(color);
      style = TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: color,
        shadows: halo,
      );
      countStyle = TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: countColor,
        shadows: halo,
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // 没有任何底色块：选中态就只有文字颜色这一处差别。
        child: SizedBox(
          height: kAppSegmentedBarPillHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
                if (count != null) ...[
                  const SizedBox(width: 4),
                  Text(formatCount(count), style: countStyle),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
