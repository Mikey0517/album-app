import 'package:flutter/material.dart';

import '../../widgets/app_segmented_bar.dart';
import '../../widgets/pinned_bar_sliver.dart';
import 'album_media_filter.dart';

/// 相册的「全部 / 照片 / 视频」筛选条，相册详情页与朋友圈相册共用这一份。
///
/// 两页的差异只有摆法：详情页套在页头下（或 AppBar.bottom），朋友圈相册
/// 套在 [AlbumMediaFilterSliver] 里吸顶。文案、数量口径、选中样式都从
/// [AppSegmentedBar] 这一层取，页面上不会出现第二套视觉。
class AlbumMediaFilterBar extends StatelessWidget {
  final AlbumMediaCounts counts;
  final AlbumMediaFilter selected;
  final ValueChanged<AlbumMediaFilter> onChanged;

  const AlbumMediaFilterBar({
    super.key,
    required this.counts,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 数量始终取全量：切筛选时数字不跳，用户知道自己漏掉了多少。
    return AppSegmentedBar(
      selectedIndex: selected.index,
      onChanged: (index) => onChanged(AlbumMediaFilter.values[index]),
      items: [
        AppSegmentedItem(AlbumMediaFilter.all.label, count: counts.total),
        AppSegmentedItem(AlbumMediaFilter.photos.label, count: counts.photos),
        AppSegmentedItem(AlbumMediaFilter.videos.label, count: counts.videos),
      ],
    );
  }
}

/// 吸顶版筛选条：高度、内边距、不透明底色由 [PinnedBarSliver] +
/// [AppSegmentedBarSurface] 决定，和详情页完全相同。
class AlbumMediaFilterSliver extends StatelessWidget {
  final AlbumMediaCounts counts;
  final AlbumMediaFilter selected;
  final ValueChanged<AlbumMediaFilter> onChanged;

  const AlbumMediaFilterSliver({
    super.key,
    required this.counts,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PinnedBarSliver(
      height: kAppSegmentedBarHeight,
      child: AppSegmentedBarSurface(
        child: AlbumMediaFilterBar(
          counts: counts,
          selected: selected,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
