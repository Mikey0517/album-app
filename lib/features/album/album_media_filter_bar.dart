import 'package:flutter/material.dart';

import '../../widgets/app_segmented_bar.dart';
import '../../widgets/pinned_bar_sliver.dart';
import 'album_media_filter.dart';

/// 筛选后一个可见项都没有时的图标：详情页与朋友圈相册共用一份。
///
/// 文案不在这里：两页的前缀不同（「还没有…」/「筛选后没有…」），
/// 各自拼 [AlbumMediaFilterX.noun] 就行。
extension AlbumMediaFilterEmptyIcon on AlbumMediaFilter {
  IconData get emptyIcon => switch (this) {
        AlbumMediaFilter.all => Icons.image_not_supported_outlined,
        AlbumMediaFilter.photos => Icons.image_not_supported_outlined,
        AlbumMediaFilter.livePhotos => Icons.motion_photos_off_outlined,
        AlbumMediaFilter.videos => Icons.videocam_off_outlined,
      };
}

/// 相册的「全部 / 照片 / 动态照片 / 视频」筛选条，相册详情页与朋友圈相册共用这一份。
///
/// 两页的差异只有摆法：详情页套在页头下（或 AppBar.bottom），朋友圈相册
/// 套在 [AlbumMediaFilterSliver] 里吸顶。文案、数量口径、选中样式都从
/// [AppSegmentedBar] 这一层取，页面上不会出现第二套视觉。
///
/// 底子也在那一层：整条是一枚玻璃胶囊（与底部 footer 同一套材质参数），
/// 选中段只换文字颜色、不加填充块。
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
    // 顺序照 [AlbumMediaFilter.values]：枚举的顺序就是这里的顺序。
    return AppSegmentedBar(
      selectedIndex: selected.index,
      onChanged: (index) => onChanged(AlbumMediaFilter.values[index]),
      items: [
        for (final filter in AlbumMediaFilter.values)
          AppSegmentedItem(filter.label, count: counts.of(filter)),
      ],
    );
  }
}

/// 吸顶版筛选条：高度、内边距由 [PinnedBarSliver] + [AppSegmentedBarSurface]
/// 决定，和详情页完全相同。
///
/// [PinnedBarSliver] 的底衬显式传**透明**：底衬由 [AppSegmentedBarSurface]
/// 自己画（吸顶那一份是底部 footer 同款**玻璃**），吸顶 sliver 再垫一层页面
/// 底色的话，玻璃顶上会多一条白杠、下面也没有内容可采。
///
/// 这一条是**吸顶**的（照片会从它下面滚过去），所以材质与 footer 完全一致：
/// premium 折射 + 55% scrim（折射可见度 45%）+ 最低档模糊，refresh 全程是同一
/// 块玻璃（见 [AppChromeGlassBar]）。封面选择页里同一个
/// [AppSegmentedBarSurface] 挂在 AppBar 上（[AppSegmentedBarSurface.pinned]
/// 为假），那里仍是主题色浅渐变、没有玻璃。
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
      background: Colors.transparent,
      child: AppSegmentedBarSurface(
        pinned: true,
        child: AlbumMediaFilterBar(
          counts: counts,
          selected: selected,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
