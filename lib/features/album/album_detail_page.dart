import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show clampDouble;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/album_api.dart';
import '../../core/album_view_settings.dart';
import '../../core/api_client.dart';
import '../../core/app_events.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/shadow.dart';
import '../../core/design/text_styles.dart';
import '../../core/media_cache.dart';
import '../../core/media_picker.dart';
import '../../core/media_share_service.dart';
import '../../core/media_store.dart';
import '../../core/responsive.dart';
import '../../core/source_media_cleanup.dart';
import '../../core/upload_manager.dart';
import '../../core/url_utils.dart';
import '../../models/album.dart';
import '../../models/media.dart';
import '../../widgets/album_thumb.dart';
import '../../widgets/app_segmented_bar.dart';
import '../../widgets/date_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/pinned_bar_sliver.dart';
import '../../widgets/selection_footer.dart';
import '../download/batch_download.dart';
import '../viewer/media_viewer_page.dart';
import 'album_media_filter.dart';
import 'album_media_filter_bar.dart';
import 'album_share_sheet.dart';
import 'album_title_dialog.dart';
import 'photo_timeline_scrubber.dart';

class AlbumDetailPage extends StatefulWidget {
  final Album album;
  final bool coverPickMode;

  /// 数据加载入口，测试注入用；生产环境走 [AlbumApi.detail]。
  final Future<AlbumDetail> Function(int albumId)? loader;

  const AlbumDetailPage({
    super.key,
    required this.album,
    this.coverPickMode = false,
    this.loader,
  });

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  // 网格：四周 12，格间距 2，圆角 4，一整块马赛克。
  static const double _pagePadding = 12;
  static const double _gridSpacing = 2;
  static const double _gridRadius = AppRadius.xs;
  static const double _dateHeaderHeight = 34;
  static const double _sectionGap = 4;
  // 底部留白 = FAB 高度 + 边距 + 一点余量，最后一行不会被上传按钮压住。
  static const double _fabClearance = 108;
  static const double _headerCoverHeight = 216;
  static const double _headerPlainHeight = 136;

  static const int _uploadLimit = 500;

  late Album _album = widget.album;
  final List<Media> _items = [];
  AlbumMediaFilter _filter = AlbumMediaFilter.all;
  bool _loading = true;
  String? _error;
  bool _selecting = false;
  bool _batchDownloading = false;
  bool _batchDeleting = false;
  bool _batchMoving = false;
  final Set<int> _selected = {};
  int? _coverSelectedId;
  final ScrollController _gridScroll = ScrollController();
  // 点按由缩略图自己处理，滑动多选要跨格命中，所以给每格留一个 key。
  final Map<int, GlobalKey> _tileKeys = {};
  // 每个日期分组的网格 sliver 一个 key：时间轴气泡靠它实时取顶部可见项。
  final List<GlobalKey> _gridSliverKeys = [];
  bool? _dragSelectValue;
  // 封面在顶上时状态栏图标要转成白色，完全收起后回到深色。
  bool _headerScrolled = false;
  // 当前该吸顶的那个日期分组（-1 = 还没滚到第一个分组头）。
  // 只给这一个分组头套 PinnedBarSliver：多个 pinned 头在 Flutter 里会互相
  // 堆叠，吸顶区就随滚动越叠越厚（每组 34px），照片被一条条空白顶下去。
  int _pinnedSection = -1;
  // 每个分组头「顶到吸顶位」时的滚动偏移，按分组下标对齐；滚动时只比这张表。
  List<double> _pinThresholds = const <double>[];

  /// 能上传/删除照片（可写及以上）。
  bool get _canEdit => _album.canEditMedia;

  /// 能改名/改封面/删相册（管理员及以上）。
  bool get _canManage => _album.canManage;

  bool get _hasCover => (_album.coverThumb ?? '').isNotEmpty;

  AlbumMediaCounts get _counts => AlbumMediaCounts.from(_items);

  List<Media> get _visibleItems => filterAlbumMedia(_items, _filter);

  List<AlbumSection> get _sections => albumSections(
        _visibleItems,
        AlbumViewSettings.sort.value,
        AlbumViewSettings.group.value,
      );

  bool get _busy => _batchDownloading || _batchDeleting || _batchMoving;

  @override
  void initState() {
    super.initState();
    AlbumViewSettings.sort.addListener(_onViewChanged);
    AlbumViewSettings.group.addListener(_onViewChanged);
    AppEvents.albumContentRevision.addListener(_onAlbumContentChanged);
    _gridScroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    AlbumViewSettings.sort.removeListener(_onViewChanged);
    AlbumViewSettings.group.removeListener(_onViewChanged);
    AppEvents.albumContentRevision.removeListener(_onAlbumContentChanged);
    _gridScroll.removeListener(_onScroll);
    _gridScroll.dispose();
    super.dispose();
  }

  /// 只在跨过阈值时重建一次，滚动过程中不会每帧 setState。
  void _onScroll() {
    final pixels = _gridScroll.hasClients ? _gridScroll.offset : 0.0;
    final scrolled = pixels > 110;
    final pinned = _pinnedSectionAt(pixels);
    if (scrolled == _headerScrolled && pinned == _pinnedSection) return;
    setState(() {
      _headerScrolled = scrolled;
      _pinnedSection = pinned;
    });
  }

  /// 最后一个已经顶到吸顶位的分组；还没到第一个分组头时是 -1。
  int _pinnedSectionAt(double pixels) {
    var index = -1;
    for (var i = 0; i < _pinThresholds.length; i++) {
      if (_pinThresholds[i] <= pixels + 0.01) index = i;
    }
    return index;
  }

  void _onViewChanged() {
    if (mounted) setState(() {});
  }

  /// 重启后补传完成时，当前相册页静默刷新。
  void _onAlbumContentChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final loader = widget.loader;
      final detail = loader != null
          ? await loader(widget.album.id)
          : await AlbumApi.detail(widget.album.id);
      if (!mounted) return;
      setState(() {
        _album = detail.album;
        _items
          ..clear()
          ..addAll(detail.items);
        _pruneSelection();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiClient.errorText(e);
      });
      if (_items.isNotEmpty) {
        _snack(ApiClient.errorText(e));
      }
    }
  }

  /// 选中集合只保留「当前筛选下可见」的项，多选数量才和眼睛看到的一致。
  void _pruneSelection() {
    final visibleIds = <int>{};
    for (final item in _items) {
      if (_filter.matches(item)) visibleIds.add(item.id);
    }
    _selected.removeWhere((id) => !visibleIds.contains(id));
    _tileKeys.removeWhere((id, _) => !_items.any((item) => item.id == id));
  }

  void _selectFilter(AlbumMediaFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _pruneSelection();
      if (widget.coverPickMode && _coverSelectedId != null) {
        final selected = _items.where((item) => item.id == _coverSelectedId);
        if (selected.isEmpty || !filter.matches(selected.first)) {
          _coverSelectedId = null;
        }
      }
    });
  }

  /// 上传成功后问用户要不要删掉手机相册里的原图（只删这一批上传成功的）。
  /// 弹窗、删除与结果提示都在 [source_media_cleanup.dart] 里，动态页共用同一份。
  Future<void> _offerDeleteOriginals() async {
    // 删除系统相册原图只有 Android 实现，iOS 上不提示（也不提前消费掉待提示的条目）。
    if (!supportsSourceMediaCleanup || !mounted) return;
    final uploaded =
        UploadManager.instance.takeCompletedWithSource(albumId: _album.id);
    if (uploaded.isEmpty) return;
    final targets = <SourceTarget>[
      for (final item in uploaded)
        (uri: item.sourceUri!, isVideo: item.isVideo),
    ];
    // 先取 messenger：删除要等系统确认弹窗，期间页面被关掉也要能提示结果。
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmDeleteSourceMedia(
      context,
      targets,
      targetLabel: '「${_album.title}」',
    );
    if (!confirmed) return;
    await deleteSourceMedia(targets, messenger: messenger);
  }

  Future<void> _shareAlbum() async {
    await showAlbumShareSheet(context, _album);
    if (!mounted) return;
    // 重新拉一次，刷新分享人数与封面等信息。
    await _load(silent: true);
  }

  Future<void> _upload() async {
    if (!_canEdit) return;
    PickedMediaResult picked;
    try {
      picked = await pickMultipleMediaFiles(limit: _uploadLimit);
    } catch (e) {
      if (mounted) _snack('无法打开相册：$e');
      return;
    }
    if (!mounted) return;
    if (picked.failedCount > 0) {
      _snack('存储空间不足，${picked.failedCount} 个文件没能读取');
    }
    if (picked.isEmpty) return;
    UploadManager.instance.enqueue(
      albumId: _album.id,
      files: picked.files,
      sourceUris: picked.uris,
      onFinished: () {
        if (mounted) _load(silent: true);
        unawaited(_offerDeleteOriginals());
      },
    );
  }

  Future<void> _rename() async {
    final title = await showAlbumTitleDialog(
      context,
      heading: '重命名相册',
      actionLabel: '保存',
      initialTitle: _album.title,
    );
    if (title == null || !mounted || title == _album.title) return;
    try {
      final album = await AlbumApi.rename(_album.id, title);
      if (!mounted) return;
      setState(() => _album = album);
    } catch (e) {
      if (!mounted) return;
      _snack(ApiClient.errorText(e));
    }
  }

  Future<void> _deleteAlbum() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${_album.title}」？', style: AppText.titleMedium),
        content: const Text(
          '不再被其他相册或朋友圈动态引用的照片和视频会被永久删除。',
          style: AppText.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AlbumApi.delete(_album.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack(ApiClient.errorText(e));
    }
  }

  void _openViewer(List<Media> items, int index) {
    Navigator.of(context).push(
      MediaViewerPage.route(
        items: List<Media>.unmodifiable(items),
        initialIndex: index,
        heroPrefix: 'album_${_album.id}_',
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---------------------------------------------------------------------------
  // 结构
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.coverPickMode) return _buildCoverPicker();
    // 没有 AppBar 接管状态栏，白色封面上的图标得自己换色。
    final lightStatusBar = _hasCover && !_selecting && !_headerScrolled;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            lightStatusBar ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            lightStatusBar ? Brightness.dark : Brightness.light,
      ),
      child: PopScope(
        canPop: !_selecting,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _selecting) _exitSelection();
        },
        child: Scaffold(
          // 空相册的入口在空状态里，右下角就不再叠一个同样的按钮。
          floatingActionButton: _selecting || !_canEdit || _items.isEmpty
              ? null
              : _DetailFab(onPressed: _upload),
          // 没选中任何一项时不出操作条，屏幕只留内容。
          bottomNavigationBar:
              _selecting && _selected.isNotEmpty ? _buildSelectionBar() : null,
          body: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildCoverPicker() {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          tooltip: '取消',
        ),
        title: const Text('选择封面'),
        actions: [
          TextButton(
            onPressed: _coverSelectedId == null ? null : _confirmCover,
            child: const Text('确定'),
          ),
        ],
        bottom: _items.isEmpty
            ? null
            : PreferredSize(
                preferredSize:
                    const Size.fromHeight(kAppSegmentedBarHeight),
                child: AppSegmentedBarSurface(
                  child: AlbumMediaFilterBar(
                    counts: _counts,
                    selected: _filter,
                    onChanged: _selectFilter,
                  ),
                ),
              ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = responsiveColumns(context, 4);
        final gridWidth =
            math.max(0.0, constraints.maxWidth - _pagePadding * 2);
        final tileWidth = (gridWidth - _gridSpacing * (columns - 1)) / columns;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final sections = _sections;
        final displayItems = [for (final section in sections) ...section.items];
        // 网格 sliver 及它们的第一项在扁平列表里的下标：气泡文案靠它们
        // 实时取「现在顶部是哪一张」，与朋友圈动态流共用同一套定位。
        final gridKeys = _gridKeysFor(sections.length);
        final sliverStarts = <int>[];
        var sliverStart = 0;
        for (final section in sections) {
          sliverStarts.add(sliverStart);
          sliverStart += section.items.length;
        }

        final headerMax = _headerMaxExtent(context);
        final headerMin = _headerMinExtent(context);
        final filterExtent = _filterBarExtent;
        final dateHeaderExtent = _dateHeaderExtent;
        // 吸顶区（折叠头 + 筛选条 + 日期分组头）压住的高度，也是时间轴轨道的
        // 顶边。**只在这里算一次**：轨道的 Positioned(top:) 和偏移表的 topInset
        // 都取这个值。以前 topInset 另外又加了 _sectionGap，结果拖到最上端时
        // 第一行照片落在吸顶条下面 4px 处，接缝处就是一条 4px 的空白。
        // 轨道也不能从 0 起算：那样命中区会压住吸顶条，滑块浮到筛选 tab 上面，
        // 拖动比例还会把吸顶这一段算进去。
        final stickyBottom = headerMin + filterExtent + dateHeaderExtent;
        // 视口极矮时轨道至少要留 120 高，其他情况下 timelineTop == stickyBottom。
        final timelineTop = clampDouble(
          stickyBottom,
          0,
          math.max(0, constraints.maxHeight - 120),
        );
        // 行的内容偏移 = 头部 + 筛选条 + 分组头；吸顶区把这三层都压住。
        // topInset 用轨道顶边同一个值，拖到轨道最上端时第一行正好贴住吸顶条。
        final metrics = buildTimelineMetrics(
          sections,
          width: gridWidth,
          columns: columns,
          headerHeight: dateHeaderExtent + _sectionGap,
          base: headerMax + filterExtent,
          topInset: timelineTop,
          // 平铺模式没有分组头，退回按拍摄月份显示，气泡才不会空着。
          fallbackLabel: (media) => timelineMonthLabel(
            albumSortDate(media, AlbumViewSettings.sort.value),
          ),
        );
        // 顶部可见项定位：topInset 直接用上面算好的吸顶区下沿，被吸顶条压住
        // 的那一行既不是跳转目标、也不该用来报月份。
        final visibleLocator = VisibleItemLocator(
          sliverStarts: sliverStarts,
          sliverKeys: gridKeys,
          topInset: timelineTop,
        );
        final showScrubber = !_selecting &&
            !widget.coverPickMode &&
            displayItems.length > 12;

        // 每个分组头「顶到吸顶位」的滚动量 = 该组第一行正好贴在吸顶条下沿时
        // 的偏移（offset 表已扣掉 topInset，减去分组头与照片之间的 _sectionGap
        // 就是分组头自身顶到吸顶位的时刻）。滚到点才把这一组的头换成吸顶版，
        // 其余分组头留在内容流里，吸顶区高度因此恒定。
        final pinThresholds = <double>[
          for (var i = 0; i < sections.length; i++)
            if (sections[i].header == null ||
                i >= sliverStarts.length ||
                sliverStarts[i] >= metrics.offsets.length)
              double.infinity
            else
              math.max(0.0, metrics.offsets[sliverStarts[i]] - _sectionGap),
        ];
        _pinThresholds = pinThresholds;
        _pinnedSection = _pinnedSectionAt(
          _gridScroll.hasClients ? _gridScroll.offset : 0.0,
        );

        final scrollView = CustomScrollView(
          controller: _gridScroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: _buildSlivers(
            context,
            sections: sections,
            gridKeys: gridKeys,
            pinnedSection: _pinnedSection,
            columns: columns,
            tileWidth: tileWidth,
            dpr: dpr,
            displayItems: displayItems,
          ),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _load(silent: true),
              child: _selecting
                  // 多选态下横向划过格子即可连选/连消，竖向滚动不受影响。
                  ? GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: (details) =>
                          _startDragSelect(details.globalPosition),
                      onHorizontalDragUpdate: (details) =>
                          _applyDragSelect(details.globalPosition),
                      onHorizontalDragEnd: (_) => _endDragSelect(),
                      onHorizontalDragCancel: _endDragSelect,
                      child: scrollView,
                    )
                  : scrollView,
            ),
            if (showScrubber)
              Positioned(
                right: 0,
                top: timelineTop,
                bottom: 0,
                width: 30,
                child: PhotoTimelineScrubber(
                  controller: _gridScroll,
                  itemCount: displayItems.length,
                  itemOffsets: metrics.offsets,
                  // 跳转仍按 offsets（越拖越准），气泡文案改成实时取顶部可见项。
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

  List<Widget> _buildSlivers(
    BuildContext context, {
    required List<AlbumSection> sections,
    required List<GlobalKey> gridKeys,
    required int pinnedSection,
    required int columns,
    required double tileWidth,
    required double dpr,
    required List<Media> displayItems,
  }) {
    final slivers = <Widget>[];

    if (!widget.coverPickMode) {
      slivers.add(_buildHeader(context));
      if (_items.isNotEmpty) {
        slivers.add(
          AlbumMediaFilterSliver(
            counts: _counts,
            selected: _filter,
            onChanged: _selectFilter,
          ),
        );
      }
    }

    if (_loading && _items.isEmpty) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: LoadingView(message: '正在打开相册'),
        ),
      );
      return slivers;
    }
    if (_error != null && _items.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: '加载失败',
            subtitle: _error,
            action: FilledButton(
              onPressed: () => _load(),
              child: const Text('重新加载'),
            ),
          ),
        ),
      );
      return slivers;
    }
    if (_items.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.photo_library_outlined,
            title: '相册还是空的',
            action: _canEdit
                ? FilledButton(
                    onPressed: _upload,
                    child: const Text('添加媒体'),
                  )
                : null,
          ),
        ),
      );
      return slivers;
    }
    if (displayItems.isEmpty) {
      final noVideos = _filter == AlbumMediaFilter.videos;
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: noVideos
                ? Icons.videocam_off_outlined
                : Icons.image_not_supported_outlined,
            title: noVideos ? '还没有视频' : '还没有照片',
            action: FilledButton(
              onPressed: () => _selectFilter(AlbumMediaFilter.all),
              child: const Text('看全部'),
            ),
          ),
        ),
      );
      return slivers;
    }

    var sectionStart = 0;
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      if (section.header != null) {
        final header = DateHeader(
          text: section.header!,
          height: _dateHeaderHeight,
          padding: const EdgeInsets.symmetric(horizontal: _pagePadding + 4),
          trailing: Text(
            '${section.items.length}',
            style: AppText.caption,
          ),
        );
        // 只有「当前分组」这一个头吸顶，其余分组头是内容流里的普通 34 高横条。
        // 两者几何完全一样（同样 34 高、同为不透明底色），所以滚动到阈值时切换
        // 不会跳：那一刻它的内容位置本来就已经和吸顶位重合。
        slivers.add(
          sectionIndex == pinnedSection
              ? PinnedBarSliver(height: _dateHeaderHeight, child: header)
              : SliverToBoxAdapter(child: header),
        );
      }
      final start = sectionStart;
      sectionStart += section.items.length;
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            _pagePadding,
            _sectionGap,
            _pagePadding,
            0,
          ),
          sliver: SliverGrid.builder(
            // 时间轴要靠这个 key 问渲染树「这一组顶部露出的是哪一格」。
            key: sectionIndex < gridKeys.length ? gridKeys[sectionIndex] : null,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: _gridSpacing,
              crossAxisSpacing: _gridSpacing,
            ),
            itemCount: section.items.length,
            itemBuilder: (context, index) {
              final media = section.items[index];
              return _buildTile(
                media: media,
                index: start + index,
                displayItems: displayItems,
                tileWidth: tileWidth,
                dpr: dpr,
              );
            },
          ),
        ),
      );
    }
    slivers.add(
      const SliverToBoxAdapter(child: SizedBox(height: _fabClearance)),
    );
    return slivers;
  }

  Widget _buildHeader(BuildContext context) {
    final counts = _counts;
    // 空相册不摆 0 / 0，让人一眼看到的是「这里还没有东西」。
    final subtitle = _items.isEmpty
        ? null
        : _album.isPrivate && !_album.isOwner
            ? '来自 ${_album.ownerLabel} · ${_album.roleLabel} · '
                '${counts.photos} 张照片 · ${counts.videos} 个视频'
            : '${counts.photos} 张照片 · ${counts.videos} 个视频';
    final delegate = _AlbumHeaderDelegate(
      topPadding: MediaQuery.paddingOf(context).top,
      // 多选态直接把头图收成一条工具栏，屏幕让给勾选。
      contentHeight: _selecting
          ? kToolbarHeight
          : (_hasCover ? _headerCoverHeight : _headerPlainHeight),
      title: _selecting ? '已选 ${_selected.length} 项' : _album.title,
      subtitle: _selecting ? null : subtitle,
      coverUrl: _selecting || !_hasCover ? null : fullUrl(_album.coverThumb!),
      leading: _selecting
          ? IconButton(
              onPressed: _exitSelection,
              icon: const Icon(Icons.close),
              tooltip: '退出选择',
            )
          : const BackButton(),
      actions: _selecting ? _selectionActions() : _browseActions(),
      toolbarIcon:
          _album.isPrivate && !_album.isOwner ? Icons.lock_outline : null,
    );
    return SliverPersistentHeader(pinned: true, delegate: delegate);
  }

  List<Widget> _selectionActions() {
    return [
      TextButton(
        onPressed: _busy ? null : _toggleSelectAll,
        child: Text(_allSelected ? '取消全选' : '全选'),
      ),
    ];
  }

  List<Widget> _browseActions() {
    return [
      IconButton(
        onPressed: () => showAlbumViewMenu(context),
        tooltip: '排序与视图',
        icon: const Icon(Icons.tune_rounded, size: 22),
      ),
      if (_canEdit || _canManage)
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'rename') _rename();
            if (value == 'delete') _deleteAlbum();
            if (value == 'share') _shareAlbum();
          },
          tooltip: '相册操作',
          icon: const Icon(Icons.more_horiz, size: 22),
          itemBuilder: (context) => [
            if (_album.isPrivate && _album.isOwner)
              PopupMenuItem<String>(
                value: 'share',
                child: Text(
                  _album.shareCount > 0
                      ? '分享管理（${_album.shareCount} 人）'
                      : '分享给家人',
                ),
              ),
            if (_canManage) ...[
              const PopupMenuItem<String>(
                  value: 'rename', child: Text('重命名')),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text('删除相册', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ],
        ),
    ];
  }

  Widget _buildTile({
    required Media media,
    required int index,
    required List<Media> displayItems,
    required double tileWidth,
    required double dpr,
  }) {
    final tileKey = _tileKeys.putIfAbsent(media.id, () => GlobalKey());
    final selected = widget.coverPickMode
        ? _coverSelectedId == media.id
        : _selected.contains(media.id);
    final showSelection = _selecting || widget.coverPickMode;
    final radius = BorderRadius.circular(_gridRadius);
    return Stack(
      key: tileKey,
      fit: StackFit.expand,
      children: [
        AlbumThumb(
          media: media,
          radius: _gridRadius,
          cacheWidth: (tileWidth * dpr).round(),
          heroTag:
              widget.coverPickMode ? null : 'album_${_album.id}_${media.id}',
          onTap: widget.coverPickMode
              ? () => setState(() => _coverSelectedId = media.id)
              : _selecting
                  ? () => _toggleSelect(media)
                  : () => _openViewer(displayItems, index),
          onLongPress: widget.coverPickMode
              ? () => setState(() => _coverSelectedId = media.id)
              : _selecting
                  ? () => _toggleSelect(media)
                  : () => _enterSelectionWith(media),
        ),
        if (showSelection)
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : Colors.white.withOpacity(0.5),
                  width: selected ? 2.5 : 1,
                ),
                color: selected
                    ? AppColors.primary.withOpacity(0.14)
                    : Colors.black.withOpacity(0.04),
              ),
            ),
          ),
        if (showSelection)
          Positioned(
            top: 5,
            right: 5,
            child: IgnorePointer(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : Colors.black.withOpacity(0.35),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  double get _filterBarExtent =>
      widget.coverPickMode || _items.isEmpty ? 0 : kAppSegmentedBarHeight;

  double get _dateHeaderExtent =>
      AlbumViewSettings.group.value == AlbumGroup.flat ? 0 : _dateHeaderHeight;

  double _headerMinExtent(BuildContext context) => widget.coverPickMode
      ? 0
      : MediaQuery.paddingOf(context).top + kToolbarHeight;

  double _headerMaxExtent(BuildContext context) {
    if (widget.coverPickMode) return 0;
    final top = MediaQuery.paddingOf(context).top;
    final extra = _selecting
        ? kToolbarHeight
        : (_hasCover ? _headerCoverHeight : _headerPlainHeight);
    return top + math.max(kToolbarHeight, extra);
  }

  /// 每个日期分组的网格 sliver 一个 key，复用到分组数量变化为止。
  List<GlobalKey> _gridKeysFor(int count) {
    while (_gridSliverKeys.length < count) {
      _gridSliverKeys.add(GlobalKey());
    }
    if (_gridSliverKeys.length > count) {
      _gridSliverKeys.removeRange(count, _gridSliverKeys.length);
    }
    return _gridSliverKeys;
  }

  // ---------------------------------------------------------------------------
  // 多选
  // ---------------------------------------------------------------------------

  void _enterSelectionWith(Media media) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(media.id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
      _dragSelectValue = null;
    });
  }

  void _toggleSelect(Media media) {
    setState(() {
      if (!_selected.add(media.id)) _selected.remove(media.id);
    });
  }

  bool get _allSelected {
    final visible = _visibleItems;
    return visible.isNotEmpty && _selected.length == visible.length;
  }

  void _toggleSelectAll() {
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
  }

  void _startDragSelect(Offset globalPosition) {
    final id = _tileAt(globalPosition);
    if (id == null) return;
    setState(() => _dragSelectValue = !_selected.contains(id));
    _applyDragSelect(globalPosition);
  }

  void _applyDragSelect(Offset globalPosition) {
    final value = _dragSelectValue;
    if (value == null) return;
    final id = _tileAt(globalPosition);
    if (id == null) return;
    final changed = value ? _selected.add(id) : _selected.remove(id);
    if (changed) setState(() {});
  }

  void _endDragSelect() {
    if (_dragSelectValue == null) return;
    setState(() => _dragSelectValue = null);
  }

  /// 滑动多选靠命中检测找格子：只有真正建出来的格子有 render box，
  /// 划出屏幕的格子自然命中不到，松手前滚回来还能接着选。
  int? _tileAt(Offset globalPosition) {
    for (final entry in _tileKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final local = box.globalToLocal(globalPosition);
      if (local.dx < 0 ||
          local.dy < 0 ||
          local.dx > box.size.width ||
          local.dy > box.size.height) {
        continue;
      }
      return entry.key;
    }
    return null;
  }

  Widget _buildSelectionBar() {
    return SelectionFooter(
      safeArea: true,
      actions: [
        SelectionFooterAction(
          icon: Icons.download_outlined,
          label: _batchDownloading ? '保存中' : '下载',
          onTap: _selected.isEmpty || _busy ? null : _downloadSelected,
        ),
        if (_canEdit)
          SelectionFooterAction(
            icon: Icons.drive_file_move_outline,
            label: _batchMoving ? '移动中' : '移动',
            onTap: _selected.isEmpty || _busy ? null : _moveSelected,
          ),
        if (_canEdit)
          SelectionFooterAction(
            icon: Icons.delete_outline,
            label: _batchDeleting ? '删除中' : '删除',
            onTap: _selected.isEmpty || _busy ? null : _deleteSelected,
          ),
        SelectionFooterAction(
          icon: Icons.ios_share,
          label: '分享',
          onTap: _selected.isEmpty || _busy ? null : _shareSelected,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 批量操作
  // ---------------------------------------------------------------------------

  Future<void> _moveSelected() async {
    if (_busy) return;
    final selected = _selected.toList(growable: false);
    if (selected.isEmpty) return;
    List<Album> albums;
    try {
      albums = await AlbumApi.list();
    } catch (e) {
      if (mounted) _snack(ApiClient.errorText(e));
      return;
    }
    final targets =
        albums.where((album) => album.id != _album.id).toList(growable: false);
    if (targets.isEmpty) {
      _snack('还没有其他相册可以移动');
      return;
    }
    if (!mounted) return;
    final target = await showModalBottomSheet<Album>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('移动到相册', style: AppText.titleMedium),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: targets.length,
                  itemBuilder: (context, index) {
                    final album = targets[index];
                    return ListTile(
                      onTap: () => Navigator.pop(context, album),
                      leading: Icon(
                        Icons.photo_album_outlined,
                        color: AppColors.textSecondary,
                      ),
                      title: Text(album.title, style: AppText.body),
                      subtitle: Text(
                        '${album.mediaCount} 项',
                        style: AppText.caption,
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: AppColors.textTertiary,
                        size: 18,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (target == null || !mounted) return;

    setState(() => _batchMoving = true);
    var success = 0;
    var failed = 0;
    for (final mediaId in selected) {
      try {
        await AlbumApi.moveMedia(_album.id, target.id, mediaId);
        success++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    await _load(silent: true);
    if (!mounted) return;
    setState(() {
      _batchMoving = false;
      _selecting = false;
      _selected.clear();
    });
    _snack(
      failed == 0
          ? '已移动 $success 项到「${target.title}」'
          : '已移动 $success 项，$failed 项失败',
    );
  }

  Future<void> _deleteSelected() async {
    if (_busy) return;
    final targets = _items
        .where((item) => _selected.contains(item.id))
        .toList(growable: false);
    if (targets.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('从相册移除 ${targets.length} 项？', style: AppText.titleMedium),
        content: const Text(
          '只解除它们和这个相册的关系；文件不再被其他相册或动态引用时才会删除。',
          style: AppText.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _batchDeleting = true);
    var success = 0;
    var failed = 0;
    for (final media in targets) {
      try {
        await AlbumApi.removeMedia(_album.id, media.id);
        success++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    await _load(silent: true);
    if (!mounted) return;
    setState(() {
      _batchDeleting = false;
      _selecting = false;
      _selected.clear();
    });
    _snack(
      failed == 0 ? '已移除 $success 项' : '已移除 $success 项，$failed 项失败',
    );
  }

  Future<void> _shareSelected() async {
    final targets = _items
        .where((item) => _selected.contains(item.id))
        .toList(growable: false);
    if (targets.isEmpty) return;
    await shareMedia(context, targets);
  }

  Future<void> _downloadSelected() async {
    if (_batchDownloading) return;
    final targets = _items
        .where((item) => _selected.contains(item.id))
        .toList(growable: false);
    if (targets.isEmpty) {
      _snack('请先选择要下载的内容');
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
    _snack(
      result.failed == 0
          ? '已保存 ${result.success} 项到相册'
          : '已保存 ${result.success} 项，${result.failed} 项失败',
    );
  }

  Future<void> _confirmCover() async {
    final mediaId = _coverSelectedId;
    if (mediaId == null) return;
    try {
      await AlbumApi.setCover(_album.id, mediaId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _snack(ApiClient.errorText(e));
    }
  }
}

/// 相册头：封面随滚动折叠成一条工具栏，展开时露出相册名与照片/视频数量。
///
/// 自己算收缩进度，是为了让「展开标题块」和「工具栏标题」交叉淡入淡出，
/// 中间不会出现两块同名文字；折叠后的高度也和详情页算时间轴时用的
/// 吸顶高度是同一个数。
class _AlbumHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double topPadding;
  final double contentHeight;
  final String title;
  final String? subtitle;
  final String? coverUrl;
  final Widget leading;
  final List<Widget> actions;
  final IconData? toolbarIcon;

  _AlbumHeaderDelegate({
    required this.topPadding,
    required this.contentHeight,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.leading,
    required this.actions,
    required this.toolbarIcon,
  });

  double get _toolbarExtent => topPadding + kToolbarHeight;

  @override
  double get minExtent => _toolbarExtent;

  @override
  double get maxExtent => math.max(
      _toolbarExtent, topPadding + math.max(kToolbarHeight, contentHeight));

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 1.0 : clampDouble(shrinkOffset / range, 0.0, 1.0);
    final hasCover = coverUrl != null;
    final foreground = hasCover
        ? Color.lerp(Colors.white, AppColors.textPrimary, t)!
        : AppColors.textPrimary;
    final surfaceOpacity = hasCover ? t : 1.0;
    // 两块标题不重叠：展开块先淡出，工具栏标题再淡入。
    final blockOpacity = t < 0.45 ? clampDouble(1 - t / 0.45, 0.0, 1.0) : 0.0;
    final titleOpacity =
        t > 0.45 ? clampDouble((t - 0.45) / 0.4, 0.0, 1.0) : 0.0;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: AppColors.bgPage),
          if (hasCover) _cover(context, t),
          // 工具栏底色：折叠过程中渐显，保证图标和标题始终读得清。
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _toolbarExtent,
            child: IgnorePointer(
              child: ColoredBox(
                color: AppColors.bgPage.withOpacity(surfaceOpacity),
              ),
            ),
          ),
          if (blockOpacity > 0.01)
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: IgnorePointer(
                child: Opacity(
                  opacity: blockOpacity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.titleLarge.copyWith(
                          color:
                              hasCover ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: hasCover
                                ? Colors.white.withOpacity(0.86)
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _toolbarExtent,
            child: Padding(
              padding: EdgeInsets.only(top: topPadding),
              child: IconTheme(
                data: IconThemeData(color: foreground, size: 22),
                child: Row(
                  children: [
                    leading,
                    Expanded(
                      child: titleOpacity > 0.01
                          ? Opacity(
                              opacity: titleOpacity,
                              child: Row(
                                children: [
                                  if (toolbarIcon != null) ...[
                                    Icon(toolbarIcon, size: 13),
                                    const SizedBox(width: 4),
                                  ],
                                  Flexible(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.titleMedium
                                          .copyWith(color: foreground),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 4),
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cover(BuildContext context, double t) {
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: maxExtent,
      child: Opacity(
        opacity: clampDouble(1 - math.max(0.0, t - 0.7) / 0.3, 0.0, 1.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: -t * 24,
              height: maxExtent + 24,
              child: CachedNetworkImage(
                cacheManager: MediaCache.manager,
                imageUrl: coverUrl!,
                fit: BoxFit.cover,
                memCacheWidth: (width * dpr).round(),
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (context, url) =>
                    ColoredBox(color: AppColors.mediaPlaceholder),
                errorWidget: (context, url, error) =>
                    ColoredBox(color: AppColors.mediaPlaceholder),
              ),
            ),
            // 底部压深：白色相册名和小字压在任何封面上都能读。
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x33000000),
                    Color(0x00000000),
                    Color(0xAA000000),
                  ],
                  stops: [0.0, 0.35, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _AlbumHeaderDelegate oldDelegate) {
    return topPadding != oldDelegate.topPadding ||
        contentHeight != oldDelegate.contentHeight ||
        title != oldDelegate.title ||
        subtitle != oldDelegate.subtitle ||
        coverUrl != oldDelegate.coverUrl ||
        leading != oldDelegate.leading ||
        actions != oldDelegate.actions ||
        toolbarIcon != oldDelegate.toolbarIcon;
  }
}

class _DetailFab extends StatefulWidget {
  final VoidCallback onPressed;

  const _DetailFab({required this.onPressed});

  @override
  State<_DetailFab> createState() => _DetailFabState();
}

class _DetailFabState extends State<_DetailFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '添加媒体',
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: AppShadow.fab,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onPressed,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Icon(
                    Icons.add_a_photo_outlined,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
