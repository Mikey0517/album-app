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

/// 日期分组头的高度：两页共用，吸顶区高度才算得准。
const double kTimelineDateHeaderHeight = 34;

/// 日期分组头与下面网格之间的留白。偏移表里也算这一份：少算一格间距，
/// 每过一组就差 4px，拖到后面的月份会越拖越偏。
const double kTimelineSectionGap = 4;

/// 视口再矮，轨道也至少留这么高，不然拖拽没有行程。
const double kTimelineMinTrackHeight = 120;

/// 右侧轨道的宽度。
const double kTimelineTrackWidth = 30;

/// 日期分组头的左右内边距（相册页 12 的网格留白 + 4，两页同值）。
const EdgeInsets kTimelineDateHeaderPadding = EdgeInsets.symmetric(
  horizontal: 16,
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

  /// 每个分组在内容里占的高度 = 分组头 + 与网格之间的留白。
  double get headerAdvance => dateHeaderExtent + kTimelineSectionGap;
}

/// 一页时间轴的几何与文案定位，两页共用同一份计算。
class AlbumTimelineLayout {
  const AlbumTimelineLayout._({
    required this.sticky,
    required this.trackTop,
    required this.metrics,
    required this.locator,
    required this.pinThresholds,
  });

  final TimelineStickySpec sticky;

  /// 轨道顶边 == 吸顶区下沿（视口极矮时抬高，保证至少有
  /// [kTimelineMinTrackHeight] 的拖拽行程）。同时就是偏移表的 topInset。
  final double trackTop;

  final TimelineMetrics metrics;
  final VisibleItemLocator locator;

  /// 每个分组头「顶到吸顶位」时的滚动偏移，按分组下标对齐。
  final List<double> pinThresholds;

  /// 按吸顶栈参数、网格几何和视口高度算出整页时间轴。
  ///
  /// 偏移表、顶部可见项定位、吸顶阈值表三者必须用同一个 [trackTop]：
  /// 拖到某个月份时那一行正好落在吸顶区下沿。
  factory AlbumTimelineLayout.compute({
    required List<AlbumSection> sections,
    required List<GlobalKey> sliverKeys,
    required double width,
    required int columns,
    required TimelineStickySpec sticky,
    required AlbumSort sort,
    required double viewHeight,
  }) {
    final trackTop = clampDouble(
      sticky.stickyBottom,
      0,
      math.max(0, viewHeight - kTimelineMinTrackHeight),
    );
    final metrics = buildTimelineMetrics(
      sections,
      width: width,
      columns: columns,
      headerHeight: sticky.headerAdvance,
      // 平铺模式没有分组头，但网格上面仍留着 kTimelineSectionGap 的空白：
      // 这段留白要算进基准偏移，拖到最上端时第一行才贴住吸顶区下沿。
      base: sticky.contentBase +
          (sticky.dateHeaderExtent == 0 ? kTimelineSectionGap : 0),
      topInset: trackTop,
      // 平铺模式没有分组头，退回按拍摄/添加月份显示，气泡才不会空着。
      fallbackLabel: (media) => timelineMonthLabel(albumSortDate(media, sort)),
    );
    final sliverStarts = timelineSliverStarts(sections);
    // 顶部可见项定位：topInset 直接用上面算好的吸顶区下沿，被吸顶条压住
    // 的那一行既不是跳转目标、也不该用来报月份。
    final locator = VisibleItemLocator(
      sliverStarts: sliverStarts,
      sliverKeys: sliverKeys,
      topInset: trackTop,
    );
    // 分组头「顶到吸顶位」的滚动量 = 该组第一行贴住吸顶条下沿时的偏移
    // （偏移表已扣掉 topInset，再减去分组头与照片之间的留白，就是分组头
    // 自己顶到吸顶位的时刻）。滚到点才把这一组的头换成吸顶版，其余分组头
    // 留在内容流里，吸顶区高度因此恒定。
    final pinThresholds = <double>[
      for (var i = 0; i < sections.length; i++)
        if (sections[i].header == null ||
            i >= sliverStarts.length ||
            sliverStarts[i] >= metrics.offsets.length)
          double.infinity
        else
          math.max(0.0, metrics.offsets[sliverStarts[i]] - kTimelineSectionGap),
    ];
    return AlbumTimelineLayout._(
      sticky: sticky,
      trackTop: trackTop,
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
Widget timelineDateHeader(AlbumSection section, {Widget? trailing}) {
  return DateHeader(
    text: section.header ?? '',
    height: kTimelineDateHeaderHeight,
    padding: kTimelineDateHeaderPadding,
    trailing: trailing,
  );
}

/// 只钉当前分组：吸顶的那一个头套 [PinnedBarSliver]，其余分组头是内容流里
/// 的普通横条。多个 pinned 头在 Flutter 里会互相堆叠，吸顶区就随滚动越叠
/// 越厚（每组 34px），照片被一条条空白顶下去。
Widget timelineDateHeaderSliver({required bool pinned, required Widget child}) {
  return pinned
      ? PinnedBarSliver(height: kTimelineDateHeaderHeight, child: child)
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

/// 右侧时间轴：轨道顶边 == 吸顶区下沿，跳转按 offsets，气泡取顶部可见项。
///
/// 轨道是宿主的 [Positioned]，两页的 top / 宽度只在这里写一次，滑块和气泡
/// 不会浮到吸顶条上面。
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