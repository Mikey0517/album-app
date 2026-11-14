import 'package:flutter/material.dart';

import '../../api/post_api.dart';
import '../../core/api_client.dart';
import '../../core/app_events.dart';
import '../../core/design/colors.dart';
import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';
import '../../models/media.dart';
import '../../models/post.dart';
import '../../widgets/date_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../album/photo_timeline_scrubber.dart';
import '../viewer/media_viewer_page.dart';
import 'compose_page.dart';
import 'feed_timeline.dart';
import 'on_this_day_page.dart';
import 'post_card.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final ScrollController _scrollController = ScrollController();
  final List<Post> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _nextCursor;
  final GlobalKey _scrollViewKey = GlobalKey();
  final Map<int, GlobalKey> _postKeys = {};
  // 每个日期分组的 SliverList 一个 key，时间轴靠它读「顶部可见的是哪条动态」。
  final Map<String, GlobalKey> _groupSliverKeys = {};
  FeedTimeline _timeline = const FeedTimeline.empty();
  String? _floatingDate;
  bool _dateUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    _scheduleFloatingDateUpdate();
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _load();
    }
  }

  void _scheduleFloatingDateUpdate() {
    if (_dateUpdateScheduled) return;
    _dateUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dateUpdateScheduled = false;
      _updateFloatingDate();
    });
  }

  void _updateFloatingDate() {
    if (!mounted || _posts.isEmpty) return;
    final scrollContext = _scrollViewKey.currentContext;
    final scrollBox = scrollContext?.findRenderObject();
    if (scrollBox is! RenderBox || !scrollBox.hasSize) return;
    final viewportTop = scrollBox.localToGlobal(Offset.zero).dy;
    // 吸顶日期头自身占 36 高，只取它下方第一条可见动态。
    final contentTop = viewportTop + 36;
    String? nextDate;
    for (final post in _posts) {
      final context = _postKeys[post.id]?.currentContext;
      final box = context?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom <= contentTop + 1) continue;
      nextDate = formatDayHeader(post.postedAt);
      break;
    }
    if (nextDate != null && nextDate != _floatingDate) {
      setState(() => _floatingDate = nextDate);
    }
  }

  /// 时间轴上要显示的月份 = 顶部可见那条动态的月份。
  String _timelineMonthLabel() => _timeline.visibleMonthLabel;

  /// 评论输入等场景键盘弹起时收起时间轴，别和输入法抢右侧手势区；
  /// 以后若加多选态，把 enabled 传 false 即可。
  bool get _showTimeline =>
      shouldShowFeedTimeline(_posts.length) &&
      MediaQuery.of(context).viewInsets.bottom == 0;

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_loading || _loadingMore || _nextCursor == null) return;
      setState(() => _loadingMore = true);
    }

    try {
      final page = await PostApi.list(
        cursor: refresh ? null : _nextCursor,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) _posts.clear();
        final existing = _posts.map((e) => e.id).toSet();
        _posts.addAll(page.items.where((e) => !existing.contains(e.id)));
        _nextCursor = page.nextCursor;
        _postKeys.removeWhere(
          (id, _) => !_posts.any((post) => post.id == id),
        );
        if (refresh) _floatingDate = null;
        if (_floatingDate == null && _posts.isNotEmpty) {
          _floatingDate = formatDayHeader(_posts.first.postedAt);
        }
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      _scheduleFloatingDateUpdate();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_posts.isEmpty || refresh) {
          _error = ApiClient.errorText(e);
        }
      });
      if (_posts.isNotEmpty && !refresh) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorText(e))),
        );
      }
    }
  }

  void _openOnThisDay() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OnThisDayPage()),
    );
  }

  Future<void> _compose() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (context) => const ComposePage()),
    );
    if (created == true) {
      AppEvents.notifyPostChanged();
      await _load(refresh: true);
    }
  }

  void _openMedia(List<Media> medias, int index) {
    Navigator.of(context).push(
      MediaViewerPage.route(
        items: medias,
        initialIndex: index,
        heroPrefix: 'feed_',
      ),
    );
  }

  Map<String, List<Post>> get _groups {
    final groups = <String, List<Post>>{};
    for (final post in _posts) {
      groups.putIfAbsent(dayKey(post.postedAt), () => []).add(post);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('朋友圈'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openOnThisDay,
            tooltip: '那年今日',
            icon: const Icon(Icons.history_rounded, size: 23),
          ),
          IconButton(
            onPressed: _compose,
            tooltip: '发布动态',
            icon: const Icon(Icons.add_a_photo_outlined, size: 22),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _posts.isEmpty) {
      return const LoadingView(message: '正在加载动态');
    }
    if (_error != null && _posts.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '加载失败',
        subtitle: _error!,
        action: FilledButton(
          onPressed: () => _load(refresh: true),
          child: const Text('重新加载'),
        ),
      );
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _load(refresh: true),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 120),
                child: EmptyState(
                  icon: Icons.photo_camera_outlined,
                  title: '还没有动态',
                  subtitle: '点右上角发布第一条',
                  action: FilledButton(
                    onPressed: _compose,
                    child: const Text('发动态'),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final groups = _groups;
    final headerText = _floatingDate ?? formatDayHeader(_posts.first.postedAt);
    final slivers = <Widget>[
      SliverPersistentHeader(
        pinned: true,
        delegate: _FloatingDateHeaderDelegate(headerText),
      ),
    ];
    final sliverKeys = <GlobalKey>[];
    final sliverStarts = <int>[];
    final timelinePosts = <Post>[];
    groups.forEach((key, posts) {
      final sliverKey = _groupSliverKeys.putIfAbsent(key, () => GlobalKey());
      sliverKeys.add(sliverKey);
      sliverStarts.add(timelinePosts.length);
      timelinePosts.addAll(posts);
      slivers.add(
        SliverList(
          key: sliverKey,
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final post = posts[index];
              final postKey = _postKeys.putIfAbsent(post.id, () => GlobalKey());
              return PostCard(
                key: postKey,
                post: post,
                onOpenMedia: _openMedia,
                onDeleted: () {
                  setState(() => _posts.removeWhere((e) => e.id == post.id));
                  _postKeys.remove(post.id);
                  _scheduleFloatingDateUpdate();
                },
              );
            },
            childCount: posts.length,
          ),
        ),
      );
    });
    _groupSliverKeys.removeWhere((key, _) => !groups.containsKey(key));
    _timeline = FeedTimeline(
      items: timelinePosts,
      sliverStarts: sliverStarts,
      sliverKeys: sliverKeys,
      // 吸顶日期头压住的那条动态不该用来报月份。
      topInset: kFeedDateHeaderHeight,
    );

    if (_loadingMore) {
      slivers.add(
        const SliverToBoxAdapter(
          child: SizedBox(
            height: 64,
            child: LoadingView(compact: true),
          ),
        ),
      );
    } else if (_nextCursor == null) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 20, bottom: 36),
            child: Center(
              child: Text('已经到底啦', style: AppText.caption),
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => _load(refresh: true),
          child: CustomScrollView(
            key: _scrollViewKey,
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: slivers,
          ),
        ),
        // 时间轴浮在列表右侧、RefreshIndicator 之外：竖直拖拽由它自己接管，
        // 列表不会跟着下拉；jumpTo 也不产生 overscroll，不会误触下拉刷新。
        if (_showTimeline)
          FeedTimelineLayer(
            controller: _scrollController,
            label: _timelineMonthLabel,
          ),
      ],
    );
  }
}

/// 吸顶日期头的高度：动态流顶部那条「几月几日」。
///
/// 时间轴轨道的顶边就取它：轨道从吸顶日期头下沿一直长到视口底部，
/// 拖到最上端时滑块贴住日期头下沿，不会浮上去盖住它；拖到最上端也正好
/// 是第一条动态（吸顶头自己不占滚动内容）。
const double kFeedDateHeaderHeight = 36;

/// 动态流右侧时间轴：从吸顶日期头下沿到视口底部。
///
/// 单独成一层是为了让「轨道顶边 = 吸顶条下沿」这条几何关系可测：宿主把它
/// 直接放进 Stack，和相册详情页一样只保留一处顶边定义。
class FeedTimelineLayer extends StatelessWidget {
  const FeedTimelineLayer({
    super.key,
    required this.controller,
    required this.label,
  });

  final ScrollController controller;

  /// 气泡文案：顶部可见那条动态的月份。
  final String Function() label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: kFeedDateHeaderHeight,
      bottom: 0,
      width: 30,
      child: PhotoTimelineScrubber(
        controller: controller,
        progressLabel: label,
      ),
    );
  }
}

class _FloatingDateHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String text;

  _FloatingDateHeaderDelegate(this.text);

  @override
  double get minExtent => kFeedDateHeaderHeight;

  @override
  double get maxExtent => kFeedDateHeaderHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DateHeader(text: text, height: kFeedDateHeaderHeight);
  }

  @override
  bool shouldRebuild(covariant _FloatingDateHeaderDelegate oldDelegate) {
    // 主题切换时颜色是运行时取色，日期文字不变也要重建。
    return true;
  }
}
