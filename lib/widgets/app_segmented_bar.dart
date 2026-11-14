import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/radius.dart';
import '../core/formatters.dart';

/// 分段条的统一样式：相册详情页的筛选条与相册主页的 Tab 条共用同一套
/// 高度、圆角、字重和间距，两个页面看起来才是一家。
const double kAppSegmentedBarHeight = 46;

/// 分段条上的一段：文案 + 可选数量。
///
/// 数量为 0 也照常显示——「视频 0」本身就是有用信息，不用先藏起来。
class AppSegmentedItem {
  final String label;
  final int? count;

  const AppSegmentedItem(this.label, {this.count});
}

/// 紧凑分段条（全部 / 照片 / 视频、朋友圈相册 / 家庭相册 / 私人相册）。
///
/// 选中态是一枚实心胶囊，未选中是描边胶囊；数量用更小的字号挂在文案后面，
/// 靠字号和颜色分出主次，不加任何说明文字。
class AppSegmentedBar extends StatelessWidget {
  final List<AppSegmentedItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// true：等分撑满一行（相册主页的 Tab）；false：紧贴内容（详情页筛选）。
  final bool expanded;

  const AppSegmentedBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) segments.add(const SizedBox(width: 6));
      final segment = _Segment(
        item: items[i],
        selected: i == selectedIndex,
        expanded: expanded,
        onTap: () => onChanged(i),
      );
      segments.add(expanded ? Expanded(child: segment) : segment);
    }
    final row = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: segments,
    );
    if (expanded) return row;
    // 低分辨率窄屏上三段文案加数量可能超宽，宁可横滑也不压字。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: row,
    );
  }
}

/// 分段条的吸顶容器：统一高度、内边距和背景。
///
/// 详情页套在 [PinnedBarSliver] 里，相册主页套在 AppBar.bottom 里，
/// 两处都用这一层，吸顶条的高度和内边距才不会各写各的。
class AppSegmentedBarSurface extends StatelessWidget {
  final Widget child;
  final Color? background;

  const AppSegmentedBarSurface({super.key, required this.child, this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kAppSegmentedBarHeight,
      color: background ?? AppColors.bgPage,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: child,
    );
  }
}

class _Segment extends StatelessWidget {
  final AppSegmentedItem item;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _Segment({
    required this.item,
    required this.selected,
    required this.expanded,
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
              padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 12),
              child: Row(
                mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
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

