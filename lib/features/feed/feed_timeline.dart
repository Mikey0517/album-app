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
class FeedTimeline {
  const FeedTimeline({
    required this.items,
    required this.sliverStarts,
    required this.sliverKeys,
  });

  const FeedTimeline.empty()
      : items = const <Post>[],
        sliverStarts = const <int>[],
        sliverKeys = const <GlobalKey>[];

  /// 按 sliver 顺序扁平化的动态。
  final List<Post> items;

  /// 每个 SliverList 在 [items] 里的起始下标，与 [sliverKeys] 一一对应。
  final List<int> sliverStarts;

  /// 每个 SliverList 的 key，用来问渲染树「顶部看得见的是哪一项」。
  final List<GlobalKey> sliverKeys;

  /// 发布时间（本地时区）→ 「2024年8月」。
  static String monthLabel(DateTime time) {
    final local = time.toLocal();
    return '${local.year}年${local.month}月';
  }

  /// 顶部可见动态的月份；还没布局完、量不到时返回空串。
  String get visibleMonthLabel {
    for (var i = 0; i < sliverKeys.length; i++) {
      if (i >= sliverStarts.length) break;
      final localIndex = firstVisibleSliverChildIndex(sliverKeys[i]);
      if (localIndex == null) continue;
      final index = sliverStarts[i] + localIndex;
      if (index < 0 || index >= items.length) continue;
      return monthLabel(items[index].postedAt);
    }
    return '';
  }
}
