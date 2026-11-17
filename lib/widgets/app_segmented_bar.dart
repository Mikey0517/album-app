import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/formatters.dart';
import 'app_bottom_tab_bar.dart';
import 'app_glass.dart';

/// 页内筛选条的统一高度：相册详情页（以及选封面时的筛选）都用它。
///
/// 注意：它只用于**页内筛选**（全部 / 照片 / 视频）。相册总页的
/// 朋友圈 / 家庭 / 私人 相册是「层级」，用 [AppCategoryMenu] 的标题下拉，
/// 不要用这条分段条——层级和筛选看起来必须不一样。
const double kAppSegmentedBarHeight = 46;

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

/// 紧凑分段条（全部 / 照片 / 动态照片 / 视频）：**整条一枚玻璃胶囊**。
///
/// 视觉只有两条规则：
/// 1. 底子是一块玻璃（[AppGlassSurface]），与底部 footer / 多选底栏同一套材质
///    参数（[preferredQuality] = [AppBottomTabBar.preferredQuality]，
///    [preferPremium]，同样的 premium 光学参数），圆角 = 高度/2；
/// 2. 选中态**只用文字颜色**表达：选中段的文案与数量换成 [AppColors.primary]，
///    未选中的是 [appTabBarInactiveColor]（和底部 tab 的未选中态同一档）。
///    没有实心胶囊、没有底色块、没有水波纹——和底部 tab 的选中态是同一种语言。
///
/// 数量用更小的字号挂在文案后面，靠字号和颜色分出主次，不加任何说明文字。
///
/// **玻璃降级**：[AppGlassSurface] 自己处理——premium 拿不到退回磨砂档；
/// 连磨砂都跑不了（注入 minimal / 平台不支持 shader）时退成同高度、同圆角的
/// 不透明 [AppColors.bgSurface] + 1px 细边，布局一模一样，不跳版也不白屏。
class AppSegmentedBar extends StatelessWidget {
  /// 与底部胶囊同档（premium）；拿不到时 AppGlassSurface 自己退档。
  static const GlassQuality preferredQuality = AppBottomTabBar.preferredQuality;

  /// 想优先要 premium（折射/边缘扭曲）：这条栏是静态 chrome，不跟着内容滚。
  static const bool preferPremium = true;

  /// 玻璃胶囊本身的 key：测试用它量「整条是一枚胶囊」。
  static const Key surfaceKey = ValueKey<String>('segmented-bar-capsule');

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
    return AppGlassSurface(
      key: surfaceKey,
      // 整条一枚胶囊：圆角 = 高度/2，玻璃和内容同形状。
      radius: kAppSegmentedBarPillRadius,
      requestedQuality: preferredQuality,
      preferPremium: preferPremium,
      child: SizedBox(
        height: kAppSegmentedBarPillHeight,
        // 水平居中：四段不铺满时也居中；低分辨率窄屏上宁可横滑也不压字。
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: row,
          ),
        ),
      ),
    );
  }
}

/// 吸顶底衬的模糊半径（sigma）。取值见 [AppSegmentedBarSurface.blur]。
const double kAppSegmentedBarBlur = 8;

/// 分段条的吸顶容器：统一高度、内边距，**透明底衬 + 极轻模糊**。
///
/// 详情页套在 [PinnedBarSliver] 里，选封面时套在 AppBar.bottom 里，两处都用
/// 这一层，吸顶条的高度、内边距和底衬才不会各写各的。
///
/// **为什么不再是 [AppColors.bgPage] 实底**：吸顶条是一条横贯整屏的窄带，垫成
/// 页面底色之后，[AppGlassBackdrop] 的渐变（或用户挑的背景图）到这里就被截成
/// 一条白杠——从相册封面往下看，页面上半段是渐变、这一条是纯色，接缝比「透出
/// 内容」更刺眼。现在底衬是**透明的**（[color] 的 alpha = 0），背景渐变原样穿过
/// 这一条。
///
/// **为什么还要一层模糊**：透明之后，吸顶条下面是滚动的照片。实测（条纹替身
/// 压在条带下、量条带里相邻像素的平均亮度差）：
/// - 纯透明：0.2096 —— 条纹一条条看得清清楚楚；
/// - 加 8% 的 [AppColors.bgPage] 蒙版：0.2087 —— 只压掉 0.4%，等于没加；
/// - 加 [kAppSegmentedBarBlur] 的模糊：0.0060 —— 与完全不透明底衬（0.0072）
///   同一档，纹理彻底被揉开，只剩一层柔和色雾。
/// 所以这里选的是用户给的「极轻 blur」那条兜底，不是蒙版：蒙版按透明度只削掉
/// 一点亮度，纹理还在；模糊直接把「看得出内容」这件事去掉，同时让背景渐变
/// 继续穿过（模糊对渐变几乎没有影响）。
///
/// 模糊层铺满整条（46 高，含上下 7 的内边距），不是只糊中间那 32——否则条带
/// 上下边缘会各留一条锋利的内容，反而更脏。
class AppSegmentedBarSurface extends StatelessWidget {
  final Widget child;

  /// 额外的蒙版色；默认 null = 完全透明。给了颜色就压在模糊层**下面**，
  /// 吸顶条会变回半透明底衬（调用点自己负责说明为什么）。
  final Color? background;

  /// 底衬的模糊半径（sigma）；0 = 不模糊，纯透明。
  final double blur;

  const AppSegmentedBarSurface({
    super.key,
    required this.child,
    this.background,
    this.blur = kAppSegmentedBarBlur,
  });

  /// 模糊层（[BackdropFilter]）的 key：测试用它断言「底衬是透明 + 轻模糊」。
  static const Key blurKey = ValueKey<String>('segmented-bar-surface-blur');

  /// 底衬的颜色：默认**完全透明**，让 [AppGlassBackdrop] 透上来。
  Color get color => background ?? Colors.transparent;

  @override
  Widget build(BuildContext context) {
    // 内容先内缩：模糊层要盖住整条（含内边距），所以 padding 在模糊里面。
    Widget band = Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: child,
    );
    if (blur > 0) {
      band = ClipRect(
        child: BackdropFilter(
          key: blurKey,
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: band,
        ),
      );
    }
    final veil = color;
    if (veil.a > 0) {
      band = DecoratedBox(decoration: BoxDecoration(color: veil), child: band);
    }
    return SizedBox(height: kAppSegmentedBarHeight, child: band);
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
    // 选中只改颜色（主题色），未选中用和底部 tab 同一档的中性灰。
    final color = selected ? AppColors.primary : appTabBarInactiveColor;
    final countColor =
        selected ? AppColors.primary.withValues(alpha: 0.72) : AppColors.textOnGlass;
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
