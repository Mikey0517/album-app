import 'package:flutter/material.dart';

import '../core/design/bar_tint.dart';
import '../core/design/colors.dart';
import '../core/formatters.dart';
import 'app_bottom_tab_bar.dart';

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

/// 分段条吸顶条内部那枚胶囊的高度：46 减去上下各 7 的内边距。
///
/// 胶囊是**整条**筛选条的底子（不是每一段各一枚），圆角取它的一半
/// （[kAppSegmentedBarPillRadius]），所以它是一枚真正的 pill。
const double kAppSegmentedBarPillHeight = kAppSegmentedBarHeight - 14;

/// 胶囊圆角 = 高度/2。
const double kAppSegmentedBarPillRadius = kAppSegmentedBarPillHeight / 2;

/// 分段条上的一段：文案 + 可选数量。
///
/// 数量为 0 也照常显示——「视频 0」本身就是有用信息，不用先藏起来。
class AppSegmentedItem {
  final String label;
  final int? count;

  const AppSegmentedItem(this.label, {this.count});
}

/// 紧凑分段条（全部 / 照片 / 动态照片 / 视频）：**文字直接落在主题色浅渐变上**。
///
/// 视觉只有两条规则：
/// 1. 底子就是外面那层吸顶底衬（[AppSegmentedBarSurface]，浅渐变见 [BarTint]）。
///    这条栏自己**不再包玻璃**：每一段的容器里没有任何材质、没有底色块，
///    只有文字与数量；
/// 2. 选中态**只用文字颜色**表达：选中段的文案与数量换成 [AppColors.primary]，
///    未选中的是 [appTabBarInactiveColor]（和底部 tab 的未选中态同一档）。
///    没有实心胶囊、没有底色块、没有水波纹——和底部 tab 的选中态是同一种语言。
///
/// 数量用更小的字号挂在文案后面，靠字号和颜色分出主次，不加任何说明文字。
///
/// **为什么把玻璃去掉**：真机上这条胶囊在下拉刷新时会整块发黑——premium 档走
/// 的是「capture 背景纹理」那条管线，刷新那几帧采到未就绪的纹理，叠上 tint
/// 就是一块近黑（和「刷新时黑卡」同一个根因）。渐变底衬已经承担了材质，这里
/// 再留一层玻璃只是重复，于是整层删掉：没有玻璃 = 没有 capture = 不可能发黑。
/// 复现与回归见 test/refresh_black_bar_test.dart。
class AppSegmentedBar extends StatelessWidget {
  /// 整条内容带的 key（原来是玻璃胶囊的位置）：测试用它量高度与宽度。
  static const Key surfaceKey = ValueKey<String>('segmented-bar-content');

  /// 单段的 key：量文案、去掉填充块这类断言用。
  static Key segmentKey(int index) => ValueKey<String>('segmented-item-$index');

  final List<AppSegmentedItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const AppSegmentedBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
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
        ),
      );
    }
    final row = Row(mainAxisSize: MainAxisSize.min, children: segments);
    return SizedBox(
      key: surfaceKey,
      height: kAppSegmentedBarPillHeight,
      // 水平居中：四段不铺满时也居中；低分辨率窄屏上宁可横滑也不压字。
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: row,
        ),
      ),
    );
  }
}

/// 分段条的吸顶容器：统一高度、内边距，**主题色浅渐变底衬**。
///
/// 详情页套在 [PinnedBarSliver] 里，选封面时套在 AppBar.bottom 里，两处都用
/// 这一层，吸顶条的高度、内边距和底衬才不会各写各的。
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

  /// 底衬渐变：与日期分组条是同一份（[BarTint.gradient]）。
  LinearGradient get gradient => BarTint.gradient;

  @override
  Widget build(BuildContext context) {
    // 渐变铺满整条（含上下 7 的内边距）：内缩的只是内容。
    return SizedBox(
      height: kAppSegmentedBarHeight,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          child: child,
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final AppSegmentedItem item;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final count = item.count;
    // 选中只改颜色：主题色在本条内局部加深（[segmentedSelectedInk]），未选中用
    // 和底部 tab 同一档的中性灰。
    final color = selected ? segmentedSelectedInk : appTabBarInactiveColor;
    // 数量：未选中用 [AppColors.textOnGlass]；选中跟文案同色——降透明度
    // （0.72 / 0.85 / 0.9）在这层浅渐变上只有 2.6~3.9:1，只有满不透明才过 4.5。
    // 主次靠字号（11 vs 13）与字重表达，不靠把颜色调淡。
    final countColor = selected ? color : AppColors.textOnGlass;
    // 同色极轻描边：玻璃底衬上的小字边缘不会糊进去，不做发光。
    final halo = appTabBarHalo(color);
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
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                    shadows: halo,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    formatCount(count),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: countColor,
                      shadows: halo,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
