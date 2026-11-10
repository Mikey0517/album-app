import 'package:flutter/material.dart';

import '../../api/gallery_api.dart';
import '../../core/album_view_settings.dart';
import '../../core/api_client.dart';
import '../../core/app_events.dart';
import '../../core/design/colors.dart';
import '../../core/responsive.dart';
import '../../core/design/text_styles.dart';
import '../../models/media.dart';
import '../../widgets/album_thumb.dart';
import '../../widgets/date_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/selection_footer.dart';
import '../../core/media_share_service.dart';
import '../download/batch_download.dart';
import '../viewer/media_viewer_page.dart';
import 'photo_timeline_scrubber.dart';

/// 朋友圈相册：只读聚合视图。
class FeedGalleryPage extends StatefulWidget {
  final void Function(bool selecting, int selected, int total)?
      onSelectionChanged;

  const FeedGalleryPage({super.key, this.onSelectionChanged});

  @override
  State<FeedGalleryPage> createState() => FeedGalleryPageState();
}

class FeedGalleryPageState extends State<FeedGalleryPage> {
  final ScrollController _scrollController = ScrollController();
  // 量一次分组头的实际滚动位置，时间轴才不会随滚动累积偏移。
  final GlobalKey _firstHeaderKey = GlobalKey();
  final List<Media> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _selecting = false;
  bool _batchDownloading = false;
  final Set<int> _selected = {};
  String? _error;
  String? _nextCursor;

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
      _items.length,
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
      });
    } else {
      if (_loading || _loadingMore || _nextCursor == null) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = await GalleryApi.feed(
        cursor: refresh ? null : _nextCursor,
        limit: 60,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) _items.clear();
        final existing = _items.map((e) => e.id).toSet();
        _items.addAll(page.items.where((e) => !existing.contains(e.id)));
        _selected.removeWhere(
          (id) => !_items.any((item) => item.id == id),
        );
        _nextCursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      if (_selecting) _notifySelection();
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
        _items,
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
    } else if (_items.isNotEmpty) {
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

  bool get _allSelected =>
      _items.isNotEmpty && _selected.length == _items.length;

  void _toggleSelectAll() {
    if (!_selecting) return;
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_items.map((item) => item.id));
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

  List<Media> get _selectedTargets => _items
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
              title: '还没有照片',
              subtitle: '发布一条带照片或视频的动态后，这里会显示照片',
            ),
          ],
        ),
      );
    }

    final sections = _sections;
    final displayItems = [
      for (final section in sections) ...section.items,
    ];
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final tileWidth = (MediaQuery.of(context).size.width - 2 * 3) / 4;
    final slivers = <Widget>[];
    var sectionStart = 0;
    for (final section in sections) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = responsiveColumns(context, 4);
        final metrics = buildTimelineMetrics(
          sections,
          width: constraints.maxWidth,
          columns: columns,
          headerHeight: _firstHeaderKey.currentContext?.size?.height ?? 48.0,
          base: timelineBaseOffset(_firstHeaderKey),
          fallbackLabel: (media) => _monthLabel(
            albumSortDate(media, AlbumViewSettings.sort.value),
          ),
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
                top: 0,
                bottom: 0,
                width: 30,
                child: PhotoTimelineScrubber(
                  controller: _scrollController,
                  itemCount: displayItems.length,
                  itemOffsets: metrics.offsets,
                  labels: metrics.labels,
                ),
              ),
          ],
        );
      },
    );
  }

  String _monthLabel(DateTime time) {
    final local = time.toLocal();
    return '${local.year}年${local.month}月';
  }
}
