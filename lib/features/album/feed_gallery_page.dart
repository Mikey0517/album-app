import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/gallery_api.dart';
import '../../core/album_view_settings.dart';
import '../../core/api_client.dart';
import '../../core/app_events.dart';
import '../../core/design/colors.dart';
import '../../core/design/text_styles.dart';
import '../../core/media_share_service.dart';
import '../../core/responsive.dart';
import '../../models/media.dart';
import '../../models/paged.dart';
import '../../widgets/album_thumb.dart';
import '../../widgets/app_segmented_bar.dart';
import '../../widgets/date_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/selection_footer.dart';
import '../download/batch_download.dart';
import '../viewer/media_viewer_page.dart';
import 'album_media_filter.dart';
import 'album_media_filter_bar.dart';
import 'photo_timeline_scrubber.dart';

/// 朋友圈相册：只读聚合视图。
class FeedGalleryPage extends StatefulWidget {
  final void Function(bool selecting, int selected, int total)?
      onSelectionChanged;

  /// 照片数量回报给父级 tab 条上的数字；只在加载成功后报。
  final ValueChanged<int>? onCountChanged;

  /// 分页数据入口，测试注入用；生产环境走 [GalleryApi.feed]。
  /// 入参是游标（null 表示第一页）。
  final Future<Paged<Media>> Function(String? cursor)? loader;

  const FeedGalleryPage({
    super.key,
    this.onSelectionChanged,
    this.onCountChanged,
    this.loader,
  });

  @override
  State<FeedGalleryPage> createState() => FeedGalleryPageState();
}

class FeedGalleryPageState extends State<FeedGalleryPage> {
  /// 筛选后当前没有任何可见项、后面却还有页时，最多自动补读这么多页。
  /// 整库只有照片时不会为了找视频把整条时间轴翻完。
  static const int _maxEmptyScanPages = 5;

  final ScrollController _scrollController = ScrollController();
  // 量一次分组头的实际滚动位置，时间轴才不会随滚动累积偏移。
  final GlobalKey _firstHeaderKey = GlobalKey();
  // 每个日期分组的网格 sliver 一个 key：时间轴气泡靠它实时取顶部可见项。
  final List<GlobalKey> _gridKeys = [];
  final List<Media> _items = [];
  /// 页内类型筛选：和相册详情页同一个模型、同一根分段条，进页面默认「全部」。
  AlbumMediaFilter _filter = AlbumMediaFilter.all;
  int _emptyScanPages = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _selecting = false;
  bool _batchDownloading = false;
  final Set<int> _selected = {};
  String? _error;
  String? _nextCursor;

  /// 筛选条上的数量：始终取全量，切筛选时数字不跳。
  AlbumMediaCounts get _counts => AlbumMediaCounts.from(_items);

  /// 当前筛选下的可见集合：网格、日期分组、时间轴、全选、下载都从它算。
  List<Media> get _visibleItems => filterAlbumMedia(_items, _filter);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    AppEvents.feedGalleryRevision.addListener(_onPostsChanged);
    AlbumViewSettings.sort.addListener(_onViewChanged);
    AlbumViewSettings.group.addListener(_onViewChanged);
    _load(refresh: true);
  }

  @override
  void dispose() {
    AppEvents.feedGalleryRevision.removeListener(_onPostsChanged);
    AlbumViewSettings.sort.removeListener(_onViewChanged);
    AlbumViewSettings.group.removeListener(_onViewChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPostsChanged() {
    _load(refresh: true);
  }

  void _onViewChanged() {
    if (mounted) setState(() {});
  }

  void _notifySelection() {
    widget.onSelectionChanged?.call(
      _selecting,
      _selected.length,
      // 总数按可见项报：父级的「全选 / 取消全选」才对得上眼睛看到的那些。
      _visibleItems.length,
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _emptyScanPages = 0;
      });
    } else {
      if (_loading || _loadingMore || _nextCursor == null) return;
      setState(() => _loadingMore = true);
    }
    try {
      final cursor = refresh ? null : _nextCursor;
      final loader = widget.loader;
      final page = loader != null
          ? await loader(cursor)
          : await GalleryApi.feed(cursor: cursor, limit: 60);
      if (!mounted) return;
      setState(() {
        if (refresh) _items.clear();
        final existing = _items.map((e) => e.id).toSet();
        _items.addAll(page.items.where((e) => !existing.contains(e.id)));
        _pruneSelection();
        _nextCursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      // 还有下一页时报的不是总数，tab 上的数字会一直涨；只有拉到底才报。
      if (_nextCursor == null) widget.onCountChanged?.call(_items.length);
      if (_selecting) _notifySelection();
      _scanWhileFilteredEmpty();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_items.isEmpty || refresh) _error = ApiClient.errorText(e);
      });
      if (_items.isNotEmpty && !refresh) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorText(e))),
        );
      }
    }
  }

  /// 选中集合只保留「当前筛选下可见」的项：多选数量、下载内容都和眼睛一致。
  void _pruneSelection() {
    final visibleIds = <int>{for (final item in _visibleItems) item.id};
    _selected.removeWhere((id) => !visibleIds.contains(id));
  }

  void _selectFilter(AlbumMediaFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _emptyScanPages = 0;
      _pruneSelection();
    });
    _notifySelection();
    _scanWhileFilteredEmpty();
  }

  /// 筛选后一个可见项都没有、后面却还有页时，静默把下一页读进来继续找：
  /// 否则「筛选后没有视频」会在时间轴还没拉完时就骗人。每换一次筛选最多
  /// 补读 [_maxEmptyScanPages] 页，且靠 [_loadingMore] 串行，不会并发打满。
  void _scanWhileFilteredEmpty() {
    if (_filter == AlbumMediaFilter.all) return;
    if (_visibleItems.isNotEmpty) return;
    if (_nextCursor == null || _loading || _loadingMore) return;
    if (_emptyScanPages >= _maxEmptyScanPages) return;
    _emptyScanPages++;
    unawaited(_load());
  }

  void _open(List<Media> items, int index) {
    Navigator.of(context).push(
      MediaViewerPage.route(
        items: List<Media>.unmodifiable(items),
        initialIndex: index,
        heroPrefix: 'gallery_',
      ),
    );
  }

  List<AlbumSection> get _sections => albumSections(
        _visibleItems,
        AlbumViewSettings.sort.value,
        AlbumViewSettings.group.value,
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selecting) _exitSelection();
      },
      child: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_selecting) _buildSelectionBar(),
        ],
      ),
    );
  }

  void toggleSelection() {
    if (_selecting) {
      _exitSelection();
    } else if (_visibleItems.isNotEmpty) {
      _enterSelection();
    }
  }

  void exitSelection() {
    if (_selecting) _exitSelection();
  }

  void _enterSelection() {
    setState(() {
      _selecting = true;
      _selected.clear();
    });
    _notifySelection();
  }

  void _enterSelectionWith(Media media) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(media.id);
    });
    _notifySelection();
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    _notifySelection();
  }

  void _toggleSelect(Media media) {
    setState(() {
      if (!_selected.add(media.id)) _selected.remove(media.id);
    });
    _notifySelection();
  }

  bool get _allSelected {
    final visible = _visibleItems;
    return visible.isNotEmpty && _selected.length == visible.length;
  }

  void _toggleSelectAll() {
    if (!_selecting) return;
    final visible = _visibleItems;
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(visible.map((item) => item.id));
      }
    });
    _notifySelection();
  }

  bool _isSectionSelected(List<Media> items) {
    return items.isNotEmpty &&
        items.every((item) => _selected.contains(item.id));
  }

  void _toggleSectionSelection(List<Media> items) {
    if (!_selecting) return;
    setState(() {
      if (_isSectionSelected(items)) {
        for (final item in items) {
          _selected.remove(item.id);
        }
      } else {
        for (final item in items) {
          _selected.add(item.id);
        }
      }
    });
    _notifySelection();
  }

  void toggleAll() => _toggleSelectAll();

  Future<void> _downloadSelected() async {
    if (_batchDownloading) return;
    final targets = _selectedTargets;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要下载的内容')),
      );
      return;
    }
    setState(() => _batchDownloading = true);
    final result = await downloadMediaBatch(context: context, medias: targets);
    if (!mounted) return;
    setState(() {
      _batchDownloading = false;
      _selecting = false;
      _selected.clear();
    });
    _notifySelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.failed == 0
              ? '已保存 ${result.success} 项到相册'
              : '已保存 ${result.success} 项，${result.failed} 项失败',
        ),
      ),
    );
  }

  /// 批量下载/分享只发当前筛选下看得见的项。
  List<Media> get _selectedTargets => _visibleItems
      .where((item) => _selected.contains(item.id))
      .toList(growable: false);

  Future<void> _shareSelected() async {
    final targets = _selectedTargets;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要分享的内容')),
      );
      return;
    }
    await shareMedia(context, targets);
  }

  Widget _buildSelectionBar() {
    return SelectionFooter(
      safeArea: true,
      actions: [
        SelectionFooterAction(
          icon: Icons.download_outlined,
          label: _batchDownloading ? '保存中' : '下载',
          onTap:
              _selected.isEmpty || _batchDownloading ? null : _downloadSelected,
        ),
        SelectionFooterAction(
          icon: Icons.ios_share,
          label: '分享',
          onTap: _selected.isEmpty || _batchDownloading ? null : _shareSelected,
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const LoadingView(message: '正在整理照片');
    }
    if (_error != null && _items.isEmpty) {
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
    if (_items.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            EmptyState(
              icon: Icons.photo_camera_back_outlined,
              title: '暂无照片或视频',
            ),
          ],
        ),
      );
    }

    final sections = _sections;
    final displayItems = [
      for (final section in sections) ...section.items,
    ];
    // 每个日期分组的网格 sliver 一个 key：气泡文案靠它们实时取顶部可见项。
    final gridKeys = _gridKeysFor(sections.length);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final tileWidth = (MediaQuery.of(context).size.width - 2 * 3) / 4;
    // 筛选条压在最上面并吸顶：翻到哪一年它都在，随时能放假筛选。
    final slivers = <Widget>[
      AlbumMediaFilterSliver(
        counts: _counts,
        selected: _filter,
        onChanged: _selectFilter,
      ),
    ];
    if (displayItems.isEmpty) {
      // 有数据、但当前筛选下一个可见项都没有：只留筛选条 + 一句空状态。
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildFilteredEmpty(),
        ),
      );
      return _wrapScroll(slivers, sections, displayItems, gridKeys);
    }

    var sectionStart = 0;
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      if (section.header != null) {
        slivers.add(
          SliverToBoxAdapter(
            child: DateHeader(
              key: identical(section, sections.first) ? _firstHeaderKey : null,
              text: section.header!,
              height: null,
              padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
              trailing: _selecting
                  ? TextButton(
                      onPressed: _batchDownloading
                          ? null
                          : () => _toggleSectionSelection(section.items),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _isSectionSelected(section.items) ? '取消全选' : '全选',
                      ),
                    )
                  : null,
            ),
          ),
        );
      }
      final sectionOffset = sectionStart;
      sectionStart += section.items.length;
      slivers.add(
        SliverGrid.builder(
          // 时间轴要靠这个 key 问渲染树「这一组顶部露出的是哪一格」。
          key: sectionIndex < gridKeys.length ? gridKeys[sectionIndex] : null,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: responsiveColumns(context, 4),
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: section.items.length,
          itemBuilder: (context, index) {
            final media = section.items[index];
            final globalIndex = sectionOffset + index;
            final selected = _selected.contains(media.id);
            return Stack(
              fit: StackFit.expand,
              children: [
                AlbumThumb(
                  media: media,
                  radius: 0,
                  cacheWidth: (tileWidth * dpr).round(),
                  heroTag: 'gallery_${media.id}',
                  onTap: _selecting
                      ? () => _toggleSelect(media)
                      : () => _open(displayItems, globalIndex),
                  onLongPress: _selecting
                      ? () => _toggleSelect(media)
                      : () => _enterSelectionWith(media),
                ),
                if (_selecting)
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.white.withOpacity(0.6),
                          width: selected ? 3 : 1,
                        ),
                        color: selected
                            ? AppColors.primary.withOpacity(0.12)
                            : Colors.black.withOpacity(0.06),
                      ),
                    ),
                  ),
                if (_selecting)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IgnorePointer(
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : Colors.black.withOpacity(0.35),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }
    if (_loadingMore) {
      slivers.add(
        const SliverToBoxAdapter(
          child: SizedBox(height: 64, child: LoadingView(compact: true)),
        ),
      );
    } else if (_nextCursor == null) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 20, bottom: 36),
            child: Center(
              child: Text('时间轴到底了', style: AppText.caption),
            ),
          ),
        ),
      );
    }

    return _wrapScroll(slivers, sections, displayItems, gridKeys);
  }

  /// 筛选后没有可见项：文案只说这一件事，动作是回到「全部」。
  Widget _buildFilteredEmpty() {
    final noVideos = _filter == AlbumMediaFilter.videos;
    return EmptyState(
      icon: noVideos
          ? Icons.videocam_off_outlined
          : Icons.image_not_supported_outlined,
      title: noVideos ? '筛选后没有视频' : '筛选后没有照片',
      action: FilledButton(
        onPressed: () => _selectFilter(AlbumMediaFilter.all),
        child: const Text('看全部'),
      ),
    );
  }

  /// 网格 + 右侧时间轴。吸顶区只有筛选条这一层，时间轴的基准偏移和
  /// 压住的高度都取它：拖动到某个月份时那一行正好落在筛选条下沿。
  Widget _wrapScroll(
    List<Widget> slivers,
    List<AlbumSection> sections,
    List<Media> displayItems,
    List<GlobalKey> gridKeys,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = responsiveColumns(context, 4);
        const stickyExtent = kAppSegmentedBarHeight;
        final metrics = buildTimelineMetrics(
          sections,
          width: constraints.maxWidth,
          columns: columns,
          headerHeight: _dateHeaderExtent(),
          base: stickyExtent,
          topInset: stickyExtent,
          fallbackLabel: (media) => timelineMonthLabel(
            albumSortDate(media, AlbumViewSettings.sort.value),
          ),
        );
        // 顶部可见项：和相册详情页同一份定位，topInset 就是吸顶筛选条的高度，
        // 被它压住的那一行不参与气泡文案。
        final sliverStarts = <int>[];
        var sliverStart = 0;
        for (final section in sections) {
          sliverStarts.add(sliverStart);
          sliverStart += section.items.length;
        }
        final visibleLocator = VisibleItemLocator(
          sliverStarts: sliverStarts,
          sliverKeys: gridKeys,
          topInset: stickyExtent,
        );
        final showScrubber = !_selecting && displayItems.length > 12;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _load(refresh: true),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: slivers,
              ),
            ),
            if (showScrubber)
              Positioned(
                right: 0,
                // 从吸顶条下沿开始：轨道不会压住筛选条，拖动比例也不算上它。
                top: stickyExtent,
                bottom: 0,
                width: 30,
                child: PhotoTimelineScrubber(
                  controller: _scrollController,
                  itemCount: displayItems.length,
                  itemOffsets: metrics.offsets,
                  // 跳转仍按 offsets，气泡文案实时取顶部可见项（已扣吸顶区）。
                  liveLabel: () => albumVisibleMonthLabel(
                    displayItems,
                    visibleLocator,
                    sort: AlbumViewSettings.sort.value,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 日期头的实际高度（它只给上下留白、高度自适应，只能量）。
  ///
  /// 量不到时退回默认值：重建途中日期头可能还没布局，直接问
  /// [BuildContext.size] 会抛异常，所以先看 render box 有没有尺寸。
  double _dateHeaderExtent() {
    final context = _firstHeaderKey.currentContext;
    if (context == null) return 48;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return 48;
    return render.size.height;
  }

  /// 每个日期分组的网格 sliver 一个 key，跟着分组数量增减。
  List<GlobalKey> _gridKeysFor(int count) {
    while (_gridKeys.length < count) {
      _gridKeys.add(GlobalKey());
    }
    if (_gridKeys.length > count) {
      _gridKeys.removeRange(count, _gridKeys.length);
    }
    return _gridKeys;
  }
}
