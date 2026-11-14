import 'package:flutter/widgets.dart';

import '../../models/post.dart';
import '../album/photo_timeline_scrubber.dart';

/// 动态少于这个数就不显示右侧时间轴，太少时拖拽没有意义。
const int kFeedTimelineMinPosts = 12;

/// 动态流右侧时间轴是否出现。
bool shouldShowFeedTimeline(int postCount) =>
    postCount >= kFeedTimelineMinPosts;

/// 动态流右侧时间轴的数据来源：把「顶部可见那条动态」映射成月份文案。
///
/// 动态流的卡片高度不定，没法像网格那样预先算偏移表，所以：
/// 跳转按滚动比例做；月份从渲染树里现读——每个日期分组的 SliverList 挂一个
/// [GlobalKey]，按 sliver 顺序找到第一条露出视口的动态，取它的发布时间。
///
/// 「顶部可见是谁」的定位与相册网格共用 [VisibleItemLocator]，
/// 月份写法共用 [timelineMonthLabel]，两边不会各写一份。
class FeedTimeline {
  const FeedTimeline({
    required this.items,
    required this.sliverStarts,
    required this.sliverKeys,
    this.topInset = 0,
  });

  const FeedTimeline.empty()
      : items = const <Post>[],
        sliverStarts = const <int>[],
        sliverKeys = const <GlobalKey>[],
        topInset = 0;

  /// 按 sliver 顺序扁平化的动态。
  final List<Post> items;

  /// 每个 SliverList 在 [items] 里的起始下标，与 [sliverKeys] 一一对应。
  final List<int> sliverStarts;

  /// 每个 SliverList 的 key，用来问渲染树「顶部看得见的是哪一项」。
  final List<GlobalKey> sliverKeys;

  /// 吸顶日期头压住的高度：被它压住的那条动态不参与月份文案。
  final double topInset;

  /// 发布时间（本地时区）→ 「2024年8月」。
  static String monthLabel(DateTime time) => timelineMonthLabel(time);

  VisibleItemLocator get _locator => VisibleItemLocator(
        sliverStarts: sliverStarts,
        sliverKeys: sliverKeys,
        topInset: topInset,
      );

  /// 顶部可见动态的月份；还没布局完、量不到时返回空串。
  String get visibleMonthLabel {
    final index = _locator.visibleIndex;
    if (index == null || index < 0 || index >= items.length) return '';
    return monthLabel(items[index].postedAt);
  }
}
