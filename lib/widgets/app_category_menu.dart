import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/text_styles.dart';
import '../core/formatters.dart';

/// 分类下拉的命中目标：测试与无障碍都认它。
const Key appCategoryMenuKey = ValueKey<String>('app-category-menu');

/// 一个分类：文案 + 可选数量（数量没加载完就先不给）。
class AppCategoryItem {
  final String label;
  final int? count;

  const AppCategoryItem(this.label, {this.count});
}

/// 分类标题下拉：当前分类名 + caret，点开是分类清单（名称 + 数量）。
///
/// 它表达的是「我在哪一层」——相册总页的 朋友圈 / 家庭 / 私人 相册。
/// 相册详情页里的「全部 / 照片 / 视频」是页内筛选，用 AppSegmentedBar 表达。
/// 两个层级不同，形式也必须不同：层级用标题，筛选才用分段条。
class AppCategoryMenu extends StatelessWidget {
  final List<AppCategoryItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const AppCategoryMenu({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = items[selectedIndex];
    return PopupMenuButton<int>(
      key: appCategoryMenuKey,
      tooltip: '切换分类',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (var i = 0; i < items.length; i++)
          _item(items[i], selected: i == selectedIndex, index: i),
      ],
      // 标题本身就是按钮：点分类名弹出清单，不再靠说明文字告诉用户「可以切」。
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                current.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<int> _item(
    AppCategoryItem item, {
    required bool selected,
    required int index,
  }) {
    return PopupMenuItem<int>(
      value: index,
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ),
          if (item.count != null) ...[
            const SizedBox(width: 18),
            Text(
              formatCount(item.count!),
              style: AppText.caption.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
