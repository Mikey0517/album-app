import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/radius.dart';
import '../core/formatters.dart';

/// 页内筛选条的统一高度：相册详情页（以及选封面时的筛选）都用它。
///
/// 注意：它只用于**页内筛选**（全部 / 照片 / 视频）。相册总页的
/// 朋友圈 / 家庭 / 私人 相册是「层级」，用 [AppCategoryMenu] 的标题下拉，
/// 不要用这条分段条——层级和筛选看起来必须不一样。
const double kAppSegmentedBarHeight = 46;

/// 分段条上的一段：文案 + 可选数量。
///
/// 数量为 0 也照常显示——「视频 0」本身就是有用信息，不用先藏起来。
class AppSegmentedItem {
  final String label;
  final int? count;

  const AppSegmentedItem(this.label, {this.count});
}

/// 紧凑分段条（全部 / 照片 / 视频）。
///
/// 选中态是一枚实心胶囊，未选中是描边胶囊；数量用更小的字号挂在文案后面，
/// 靠字号和颜色分出主次，不加任何说明文字。
class AppSegmentedBar extends StatelessWidget {
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
          item: items[i],
          selected: i == selectedIndex,
          onTap: () => onChanged(i),
        ),
      );
    }
    final row = Row(mainAxisSize: MainAxisSize.min, children: segments);
    // 低分辨率窄屏上三段文案加数量可能超宽，宁可横滑也不压字。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: row,
    );
  }
}

/// 分段条的吸顶容器：统一高度、内边距和不透明底色。
///
/// 详情页套在 [PinnedBarSliver] 里，选封面时套在 AppBar.bottom 里，两处都用
/// 这一层，吸顶条的高度、内边距和底色才不会各写各的。
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
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final count = item.count;
    return Semantics(
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 32,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.borderLight,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color:
                            selected ? Colors.white : AppColors.textSecondary,
                      ),
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
                        color: selected
                            ? Colors.white.withOpacity(0.8)
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
