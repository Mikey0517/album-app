import 'package:flutter/material.dart';

import '../../widgets/app_chrome_glass_bar.dart';
import '../../widgets/app_segmented_bar.dart';
import '../../widgets/date_header.dart';
import '../../widgets/pinned_bar_sliver.dart';
import 'album_media_filter.dart';
import 'album_timeline_layout.dart';

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
/// 套在 [AlbumPinnedChromeSliver] 的吸顶玻璃里。文案、数量口径、选中样式都从
/// [AppSegmentedBar] 这一层取，页面上不会出现第二套视觉。
///
/// 底子也在那一层：整条落在一整块玻璃里（与底部 footer 同一套材质参数），
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

/// 相册页吸顶区（**一整块玻璃**）的高度：分类行 46 + 日期行 34 = 80。
///
/// 两行不是两条各自带玻璃的吸顶 sliver 上下堆叠——那样两行之间会露出一条接缝
/// （两条玻璃的底衬/描边叠在一起，滚动的照片从缝里透出来）。现在它们同时塞进
/// 同一个 [AppChromeGlassBar.pinned]，一块 roundRect 同时容纳两行，只有整块
/// 吸顶（见 [AlbumPinnedChromeSliver]）。
const double kAlbumPinnedChromeHeight =
    kAppSegmentedBarHeight + kTimelineDateHeaderHeight;

/// 相册页的吸顶区：**一整块玻璃**，上面一行分类（全部 / 照片 / 动态照片 /
/// 视频），下面一行日期（当前那一组的日期 + 张数）。
///
/// **为什么是一块**：两块独立的吸顶条（46 + 38）上下堆叠时，两条的底衬、
/// scrim、描边在交界处各画一遍，滚动的照片从缝里透出来就是一条「接缝」。
/// 塞进同一个 [AppChromeGlassBar.pinned] 的 children 之后，接缝从结构上就不
/// 存在：只有一块玻璃、一层底衬（[kAppChromePinnedBackplateAlpha] = 0.9）。
///
/// **只有整块吸顶**：两条各自是 pinned sliver 时各自吸顶、各自叠，滚过几组
/// 就叠几层；现在这一个 [PinnedBarSliver] 是吸顶区里唯一钉住的东西，高度恒定
/// （[kAlbumPinnedChromeHeight]），行内容各自更新。
///
/// **两行怎么读墨色**：玻璃条把自动墨色放进 [AppChromeInk]，分类行与日期行
/// 自己取（[AppSegmentedBarSurface] / [DateHeader] 的 build 里那一段），所以
/// 两行与 footer 是同一档墨色，不需要在这里再传一遍颜色。
///
/// **刷新不换材质**：整块玻璃仍是一个 [AppChromeGlassBar]（常量 key 的
/// RepaintBoundary + 固定位置的 AppGlassSurface），下拉刷新期间日期行的文案
/// 会变，但玻璃层的 Element 不变——不会抓到未完成的那一帧（复现见
/// test/refresh_black_bar_test.dart）。
class AlbumPinnedChromeSliver extends StatelessWidget {
  const AlbumPinnedChromeSliver({
    super.key,
    this.counts,
    required this.selected,
    required this.onChanged,
    this.dateText,
    this.dateCount,
    this.dateTrailing,
  });

  /// 分类行的计数；null = 这一页没有分类行（选封面时筛选条挂在 AppBar 上）。
  final AlbumMediaCounts? counts;

  /// 分类行当前选中的那一格。
  final AlbumMediaFilter selected;

  /// 分类行的点击回调（四段照旧工作）。
  final ValueChanged<AlbumMediaFilter> onChanged;

  /// 日期行的文案（当前分组的日期）；null = 没有日期行（平铺分组）。
  final String? dateText;

  /// 日期行右侧的张数（当前分组）。
  final int? dateCount;

  /// 日期行右侧的附加控件（朋友圈相册多选态的「全选」）。
  final Widget? dateTrailing;

  bool get _hasFilterRow => counts != null;

  bool get _hasDateRow => dateText != null;

  /// 整块玻璃的高度：有分类行就 [kAppSegmentedBarHeight]，有日期行就
  /// [kTimelineDateHeaderHeight]（34，不是内容流分组头的 38）。
  double get height =>
      (_hasFilterRow ? kAppSegmentedBarHeight : 0) +
      (_hasDateRow ? kTimelineDateHeaderHeight : 0);

  @override
  Widget build(BuildContext context) {
    return PinnedBarSliver(
      height: height,
      // 底衬全部交给那块玻璃：sliver 自己再垫一层页面底色，玻璃顶上会多一条
      // 白杠，玻璃也没有内容可采。
      background: Colors.transparent,
      child: AppChromeGlassBar.pinned(
        children: [
          if (_hasFilterRow)
            AppSegmentedBarSurface(
              child: AlbumMediaFilterBar(
                counts: counts!,
                selected: selected,
                onChanged: onChanged,
              ),
            ),
          if (_hasDateRow)
            DateHeader(
              text: dateText!,
              height: kTimelineDateHeaderHeight,
              padding: kPinnedDateRowPadding,
              count: dateCount,
              trailing: dateTrailing,
            ),
        ],
      ),
    );
  }
}
