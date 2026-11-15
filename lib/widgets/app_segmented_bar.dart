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

/// 紧凑分段条（全部 / 照片 / 动态图片 / 视频）：**整条一枚玻璃胶囊**。
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

/// 分段条的吸顶容器：统一高度、内边距和不透明底色。
///
/// 详情页套在 [PinnedBarSliver] 里，选封面时套在 AppBar.bottom 里，两处都用
/// 这一层，吸顶条的高度、内边距和底色才不会各写各的。
///
/// 底色保持不透明（[AppColors.bgPage]）：吸顶条下面是滚动的照片，这一层没垫实
/// 就会在接缝处透出内容。玻璃胶囊浮在这块底色上（[AppSegmentedBar]），
/// 和页面底色的接缝依旧是一条实底。
class AppSegmentedBarSurface extends StatelessWidget {
  final Widget child;
  final Color? background;

  const AppSegmentedBarSurface({super.key, required this.child, this.background});

  /// 吸顶条的底色：默认与页面背景同色，且不透明——滚动内容从它后面经过，
  /// 半透明就会在接缝处透出来。
  Color get color => background ?? AppColors.bgPage;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kAppSegmentedBarHeight,
      color: color,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: child,
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
