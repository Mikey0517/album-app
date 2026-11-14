import 'dart:math' as math;
import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';

import '../../core/album_view_settings.dart';
import '../../models/media.dart';
import '../../widgets/date_header.dart';
import '../../widgets/pinned_bar_sliver.dart';
import 'photo_timeline_scrubber.dart';

/// 相册详情页与朋友圈相册的吸顶栈 / 时间轴几何：**只在这里算一次**。
///
/// 两页的差异只剩「有没有折叠封面头」这一个参数（[TimelineStickySpec.headerMin]
/// / [TimelineStickySpec.headerMax]）：吸顶栈高度、偏移表、topInset、气泡取值
/// 全部走这一份实现，所以同样的拖动在两页落在同一个位置、报出同一个月。

/// 日期分组头文字区的高度：两页共用，吸顶区高度才算得准。
const double kTimelineDateHeaderHeight = 34;

/// 日期分组头与下面网格之间的留白。偏移表里也算这一份：少算一格间距，
/// 每过一组就差 4px，拖到后面的月份会越拖越偏。
///
/// 它是分组头**自己的下内边距**（见 [kTimelineDateHeaderPadding]），不是网格的
/// 顶部内边距：分组头整块不透明，吸顶时这段留白也被底色盖住，吸顶条下沿与第一
/// 行照片之间才不会透出页面底色（那正是「时间条与吸顶分类条之间有一条缝」）。
const double kTimelineSectionGap = 4;

/// 日期分组头的整体高度 = 文字区 + 与网格之间的留白。
///
/// 吸顶栈高度、偏移表、网格顶部内边距都取这一个数：分组头涨到哪儿，照片就从
/// 哪儿开始，两者之间没有第三处几何。
const double kTimelineDateHeaderExtent =
    kTimelineDateHeaderHeight + kTimelineSectionGap;

/// 网格顶部内边距：0。
///
/// 留白已经算在分组头里（[kTimelineSectionGap]），网格自己再加一份就会在吸顶条
/// 下沿和第一行照片之间留出一条页面底色的缝——这一份只在这里写，两页都引用它。
const double kTimelineGridTopPadding = 0;

/// 视口再矮，轨道也至少留这么高，不然拖拽没有行程。
const double kTimelineMinTrackHeight = 120;

/// 右侧轨道的宽度。
const double kTimelineTrackWidth = 30;

/// 日期分组头的内边距：左右 16（相册页 12 的网格留白 + 4，两页同值），
/// 下面 4 = 与网格之间的留白，跟着分组头的底色一起铺满。
const EdgeInsets kTimelineDateHeaderPadding = EdgeInsets.fromLTRB(
  16,
  0,
  16,
  kTimelineSectionGap,
);

/// 吸顶栈的组成：折叠页头 + 筛选条 + 日期分组头。
///
/// [headerMin] 是折叠后的页头（朋友圈相册没有页头，传 0），[headerMax] 是
/// 展开的页头。两者之差就是「跳转时页头顺带收起」的那一段。
class TimelineStickySpec {
  const TimelineStickySpec({
    required this.headerMin,
    required this.headerMax,
    required this.filterExtent,
    required this.dateHeaderExtent,
  });

  final double headerMin;
  final double headerMax;

  /// 筛选条高度（没有筛选条时传 0）。
  final double filterExtent;

  /// 日期分组头高度（平铺分组时传 0）。
  final double dateHeaderExtent;

  /// 吸顶区总高 = 折叠头 + 筛选条 + 日期头。轨道顶边与 topInset 都取它：
  /// 被吸顶条压住的那一行既不是跳转目标，也不该用来报月份。
  double get stickyBottom => headerMin + filterExtent + dateHeaderExtent;

  /// 内容流里第一组的基准偏移 = 展开头 + 筛选条。
  double get contentBase => headerMax + filterExtent;

  /// 每个分组在内容里占的高度 = 分组头（已含与网格之间的留白，见
  /// [kTimelineDateHeaderExtent]）。留白不再单独加一次，否则吸顶条下沿与第一
  /// 行照片之间会多出一条页面底色。
  double get headerAdvance => dateHeaderExtent;
}

/// 一页时间轴的几何与文案定位，两页共用同一份计算。
class AlbumTimelineLayout {
  const AlbumTimelineLayout._({
    required this.sticky,
    required this.contentTop,
    required this.metrics,
    required this.locator,
    required this.pinThresholds,
  });

  final TimelineStickySpec sticky;

  /// 内容区起点 == 吸顶区下沿（视口极矮时抬高，保证至少有
  /// [kTimelineMinTrackHeight] 的拖拽行程）。同时就是偏移表的 topInset。
  ///
  /// 第一行照片、轨道顶边、topInset、吸顶阈值都从这一个数出发：吸顶条下沿到
  /// 轨道顶边之间因此不存在任何一段「谁也没画」的页面底色。
  final double contentTop;

  /// 轨道顶边：与 [contentTop] 是同一个数（只为调用处读起来顺），不重新计算。
  double get trackTop => contentTop;

  final TimelineMetrics metrics;
  final VisibleItemLocator locator;

  /// 每个分组头「顶到吸顶位」时的滚动偏移，按分组下标对齐。
  final List<double> pinThresholds;

  /// 按吸顶栈参数、网格几何和视口高度算出整页时间轴。
  ///
  /// 偏移表、顶部可见项定位、吸顶阈值表三者必须用同一个 [contentTop]：
  /// 拖到某个月份时那一行正好落在吸顶区下沿，也就是内容区起点。
  factory AlbumTimelineLayout.compute({
    required List<AlbumSection> sections,
    required List<GlobalKey> sliverKeys,
    required double width,
    required int columns,
    required TimelineStickySpec sticky,
    required AlbumSort sort,
    required double viewHeight,
  }) {
    final contentTop = clampDouble(
      sticky.stickyBottom,
      0,
      math.max(0, viewHeight - kTimelineMinTrackHeight),
    );
    final metrics = buildTimelineMetrics(
      sections,
      width: width,
      columns: columns,
      headerHeight: sticky.headerAdvance,
      // 基准偏移就是内容流里第一组的起点。分组头自己吃掉了与网格之间的留白
      // （[kTimelineDateHeaderExtent]），网格顶部不再另加内边距，所以这里也不
      // 需要再补 kTimelineSectionGap：补了第一行就会比吸顶区下沿低一截。
      base: sticky.contentBase,
      topInset: contentTop,
      // 平铺模式没有分组头，退回按拍摄/添加月份显示，气泡才不会空着。
      fallbackLabel: (media) => timelineMonthLabel(albumSortDate(media, sort)),
    );
    final sliverStarts = timelineSliverStarts(sections);
    // 顶部可见项定位：topInset 直接用上面算好的吸顶区下沿，被吸顶条压住
    // 的那一行既不是跳转目标、也不该用来报月份。
    final locator = VisibleItemLocator(
      sliverStarts: sliverStarts,
      sliverKeys: sliverKeys,
      topInset: contentTop,
    );
    // 分组头「顶到吸顶位」的滚动量 = 该组第一行贴住吸顶条下沿时的偏移。
    // 偏移表已扣掉 topInset（= 吸顶区下沿），而第一行正好从分组头下沿开始
    // （留白算在分组头里，网格顶部不再加内边距），所以就是 offsets 本身，
    // 不用再减 kTimelineSectionGap——多减一次分组头就会提前 4px 吸顶。
    // 滚到点才把这一组的头换成吸顶版，其余分组头留在内容流里，吸顶区高度
    // 因此恒定。
    final pinThresholds = <double>[
      for (var i = 0; i < sections.length; i++)
        if (sections[i].header == null ||
            i >= sliverStarts.length ||
            sliverStarts[i] >= metrics.offsets.length)
          double.infinity
        else
          math.max(0.0, metrics.offsets[sliverStarts[i]]),
    ];
    return AlbumTimelineLayout._(
      sticky: sticky,
      contentTop: contentTop,
      metrics: metrics,
      locator: locator,
      pinThresholds: pinThresholds,
    );
  }

  /// 气泡文案：吸顶区下沿以下第一项的月份（两页同一句）。
  String liveMonthLabel(List<Media> displayItems, AlbumSort sort) {
    return albumVisibleMonthLabel(displayItems, locator, sort: sort);
  }
}

/// 扁平化后每条分组网格的第一个子项下标，[VisibleItemLocator] 用它换算下标。
List<int> timelineSliverStarts(List<AlbumSection> sections) {
  final starts = <int>[];
  var start = 0;
  for (final section in sections) {
    starts.add(start);
    start += section.items.length;
  }
  return starts;
}

/// 日期分组头：高度与内边距只在这里写一次，两页（以及平铺模式的占位）
/// 用的是同一份几何。
///
/// 高度取 [kTimelineDateHeaderExtent]（34 + 4）：与网格之间的留白是它自己的
/// 下内边距，整块不透明，所以滚动中不会从分组头下沿透出页面底色。
Widget timelineDateHeader(AlbumSection section, {Widget? trailing}) {
  return DateHeader(
    text: section.header ?? '',
    height: kTimelineDateHeaderExtent,
    padding: kTimelineDateHeaderPadding,
    trailing: trailing,
  );
}

/// 只钉当前分组：吸顶的那一个头套 [PinnedBarSliver]，其余分组头是内容流里
/// 的普通横条。多个 pinned 头在 Flutter 里会互相堆叠，吸顶区就随滚动越叠
/// 越厚（每组 38px），照片被一条条空白顶下去。
///
/// 吸顶版与内容流版同高（[kTimelineDateHeaderExtent]）：吸顶那一刻分组头的
/// 位置本来就正好在吸顶位，两者不会互相挤动，吸顶条下沿也不会漏缝。
Widget timelineDateHeaderSliver({required bool pinned, required Widget child}) {
  return pinned
      ? PinnedBarSliver(height: kTimelineDateHeaderExtent, child: child)
      : SliverToBoxAdapter(child: child);
}

/// 「只钉当前分组」的滚动状态：阈值表 + 当前该吸顶的分组下标。
class TimelinePinState {
  List<double> _thresholds = const <double>[];
  int _pinnedSection = -1;

  /// 当前该吸顶的分组下标；-1 = 还没滚到第一个分组头。
  int get pinnedSection => _pinnedSection;

  /// 最后一个已经顶到吸顶位的分组。
  int pinnedSectionAt(double pixels) {
    var index = -1;
    for (var i = 0; i < _thresholds.length; i++) {
      if (_thresholds[i] <= pixels + 0.01) index = i;
    }
    return index;
  }

  /// build 里每帧登记最新阈值表，并按当前滚动位置同步吸顶分组（不重建）。
  void register(List<double> thresholds, double pixels) {
    _thresholds = thresholds;
    _pinnedSection = pinnedSectionAt(pixels);
  }

  /// 滚动时调用：吸顶分组变了返回 true，页面据此重建一次。
  bool onScroll(double pixels) {
    final next = pinnedSectionAt(pixels);
    if (next == _pinnedSection) return false;
    _pinnedSection = next;
    return true;
  }
}

/// 右侧时间轴：轨道顶边 == 内容区起点 == 吸顶区下沿，跳转按 offsets，气泡取
/// 顶部可见项。
///
/// 轨道是宿主的 [Positioned]，两页的 top / 宽度只在这里写一次，滑块和气泡
/// 不会浮到吸顶条上面。[trackTop] 只能传 [AlbumTimelineLayout.contentTop]：
/// 那个数同时决定第一行照片的落点，轨道因此永远贴着第一行，不会在吸顶条和
/// 轨道之间留出页面底色。
Widget timelineScrubberLayer({
  required ScrollController controller,
  required int itemCount,
  required List<double> itemOffsets,
  required double trackTop,
  required String Function() liveLabel,
}) {
  return Positioned(
    right: 0,
    top: trackTop,
    bottom: 0,
    width: kTimelineTrackWidth,
    child: PhotoTimelineScrubber(
      controller: controller,
      itemCount: itemCount,
      itemOffsets: itemOffsets,
      liveLabel: liveLabel,
    ),
  );
}