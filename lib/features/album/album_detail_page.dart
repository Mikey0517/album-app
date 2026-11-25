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
import '../../widgets/app_bottom_tab_bar.dart';
import '../../widgets/app_glass.dart';
import '../../widgets/app_glass_tone.dart';
import '../../widgets/app_segmented_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/selection_footer.dart';
import '../download/batch_download.dart';
import '../viewer/media_viewer_page.dart';
import 'album_media_filter.dart';
import 'album_media_filter_bar.dart';
import 'album_share_sheet.dart';
import 'album_timeline_layout.dart';
import 'album_title_dialog.dart';

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
  // 系统删除确认框已经弹出来了，避免同一批重复弹。
  bool _offeringDeleteOriginals = false;
  final Set<int> _selected = {};
  int? _coverSelectedId;
  final ScrollController _gridScroll = ScrollController();
  // 点按由缩略图自己处理，拖拽连选要跨格命中，所以给每格留一个 key。
  final Map<int, GlobalKey> _tileKeys = {};
  // 长按进入多选后不松手继续拖 = 连续选中；多选态直接横向划过 = 连选/连消。
  // 指针簿记和命中采样都在 widgets/album_thumb.dart 的 AlbumGridDragSelect 里，
  // 朋友圈相册用的是同一个——两页不各写一份。
  late final AlbumGridDragSelect _dragSelect = AlbumGridDragSelect(
    isEnabled: () => _selecting,
    hitTest: _tileAt,
    isSelected: (mediaId) => _selected.contains(mediaId),
    onChanged: _applyDragSelection,
  );
  // 每个日期分组的网格 sliver 一个 key：时间轴气泡靠它实时取顶部可见项。
  final List<GlobalKey> _gridSliverKeys = [];
  // 封面在顶上时状态栏图标要转成白色，完全收起后回到深色。
  bool _headerScrolled = false;
  // 只钉当前分组的日期头：阈值表、吸顶分组都由公共组件算，
  // 和朋友圈相册是同一份实现（见 album_timeline_layout.dart）。
  final TimelinePinState _pin = TimelinePinState();

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

  /// 右下角上传按钮：能写的用户一直有（空相册也一样，见 [_buildSlivers] 的空状态）；
  /// 多选态让开底栏，首次加载与整页加载失败时不叠在提示上。
  bool get _showUploadFab =>
      _canEdit && !_selecting && !_loading && !(_error != null && _items.isEmpty);

  @override
  void initState() {
    super.initState();
    AlbumViewSettings.sort.addListener(_onViewChanged);
    AlbumViewSettings.group.addListener(_onViewChanged);
    AppEvents.albumContentRevision.addListener(_onAlbumContentChanged);
    _gridScroll.addListener(_onScroll);
    UploadManager.instance.addListener(_onUploadsChanged);
    _load();
    // 上一次上传如果是在页面关掉之后才完成的，这里补一次系统确认框。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_offerDeleteOriginals());
    });
  }

  @override
  void dispose() {
    AlbumViewSettings.sort.removeListener(_onViewChanged);
    AlbumViewSettings.group.removeListener(_onViewChanged);
    AppEvents.albumContentRevision.removeListener(_onAlbumContentChanged);
    UploadManager.instance.removeListener(_onUploadsChanged);
    _gridScroll.removeListener(_onScroll);
    _gridScroll.dispose();
    super.dispose();
  }

  /// 只在跨过阈值时重建一次，滚动过程中不会每帧 setState。
  void _onScroll() {
    final pixels = _gridScroll.hasClients ? _gridScroll.offset : 0.0;
    final scrolled = pixels > 110;
    // 吸顶分组换人时才需要重建：只钉当前分组，其余分组头留在内容流里。
    final pinChanged = _pin.onScroll(pixels);
    if (scrolled == _headerScrolled && !pinChanged) return;
    setState(() => _headerScrolled = scrolled);
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

  /// 上传完成后把这一批原图交给系统弹窗确认删除（只删这一批上传成功的）。
  ///
  /// 不在 App 里再弹一层「删不删」：确认就是系统那个列出照片的弹窗。
  Future<void> _offerDeleteOriginals() async {
    // 删除系统相册原图只有 Android 实现，iOS 上不提示（也不提前消费掉待提示的条目）。
    if (!supportsSourceMediaCleanup || !mounted || _offeringDeleteOriginals) {
      return;
    }
    final uploaded =
        UploadManager.instance.takeCompletedWithSource(albumId: _album.id);
    if (uploaded.isEmpty) return;
    final targets = <SourceTarget>[
      for (final item in uploaded)
        (uri: item.sourceUri!, isVideo: item.isVideo),
    ];
    // 先取 messenger：删除要等系统确认弹窗，期间页面被关掉也要能提示结果。
    final messenger = ScaffoldMessenger.of(context);
    _offeringDeleteOriginals = true;
    try {
      await deleteSourceMedia(targets, messenger: messenger);
    } finally {
      _offeringDeleteOriginals = false;
    }
  }

  /// 上传状态一变就看看有没有「传完了、还没提示过删除原图」的条目。
  ///
  /// 以前只靠批量结束的回调，页面刚好被关掉就再也没人提示。现在队列空闲时补
  /// 一次，进来时也会在首帧后补一次。
  void _onUploadsChanged() {
    if (!mounted || _offeringDeleteOriginals) return;
    if (UploadManager.instance.isBusy) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_offerDeleteOriginals());
    });
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
        // 页面底色和「相册 tab」是同一份实现、同一组参数：[AppGlassBackdrop]
        // 的页面底色 + 渐变（或用户自定义背景图 + 同一档可读性遮罩）。从 tab
        // 里看「朋友圈相册」和从列表 push 进来的相册详情原来是两种底（前者是
        // 渐变，后者是 Scaffold 的 bgPage 实底），现在两处逐项一致；Scaffold
        // 自己不上色，背景从它下面透上来。
        child: AppGlassBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            // 上传按钮浮在右下角：平移由 [AlbumUploadFabLocation] 负责让开右侧
            // 时间轴的轨道区（默认 endFloat 的 16 会让按钮压在轨道上）。
            floatingActionButtonLocation: const AlbumUploadFabLocation(),
            // 空相册也留着它：空状态里不再另放「添加媒体」，上传入口只有右下角
            // 这一个（只读用户、多选态、首次加载、整页没加载出来时没有）。
            floatingActionButton:
                _showUploadFab ? AlbumUploadFab(onPressed: _upload) : null,
            // 没选中任何一项时不出操作条，屏幕只留内容。
            bottomNavigationBar: _selecting && _selected.isNotEmpty
                ? _buildSelectionBar()
                : null,
            // 多选底栏和底部 footer 一样是**浮**在内容上的胶囊：body 一直铺到
            // 屏幕底边，照片从玻璃底下穿过，折射才有东西可采。没有操作条时
            // bottomNavigationBar 为 null，布局和以前完全一样。
            extendBody: true,
            body: _buildBody(),
          ),
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
        // 每个日期分组的网格 sliver 一个 key：气泡文案靠它实时取顶部可见项。
        final gridKeys = _gridKeysFor(sections.length);
        // 吸顶区：一整块玻璃里的分类行 + 日期行。第一组的日期从一开始就摆在
        // 那块玻璃里（内容流里没有它），所以日期行有没有、摆哪一组，都由
        // 「第一个带分组头的分组」决定。
        final firstHeader = timelineFirstHeaderIndex(sections);
        final dateRowExtent =
            firstHeader >= 0 ? kTimelineDateHeaderHeight : 0.0;
        // 吸顶栈、偏移表、topInset、气泡定位、吸顶阈值全部由公共组件算：
        // 两页只有「有没有折叠封面头」这一个参数不同。
        final layout = AlbumTimelineLayout.compute(
          sections: sections,
          sliverKeys: gridKeys,
          width: gridWidth,
          columns: columns,
          sticky: TimelineStickySpec(
            headerMin: _headerMinExtent(context),
            headerMax: _headerMaxExtent(context),
            filterExtent: _filterBarExtent,
            dateRowExtent: dateRowExtent,
            dateHeaderExtent: _dateHeaderExtent,
          ),
          sort: AlbumViewSettings.sort.value,
          viewHeight: constraints.maxHeight,
        );
        // 这一帧的阈值表 + 当前吸顶分组（只钉当前分组）。
        _pin.register(
          layout.pinThresholds,
          _gridScroll.hasClients ? _gridScroll.offset : 0.0,
        );
        final showScrubber = !_selecting &&
            !widget.coverPickMode &&
            displayItems.length > 12;

        final scrollView = CustomScrollView(
          controller: _gridScroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: _buildSlivers(
            context,
            sections: sections,
            gridKeys: gridKeys,
            firstHeader: firstHeader,
            pinnedSection: _pin.pinnedSection,
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
              // Listener 常挂着（不是多选态才挂）：长按进入多选的那一次按下，
              // 指针的命中路径在按下的瞬间就定死了，后插进来的 Listener 收不到
              // 这根手指后续的 move——「长按不松手继续拖」就断在这里。
              // 它不参与手势竞技场，所以竖向滚动、长按、单击全都照旧。
              child: Listener(
                onPointerDown: _dragSelect.onPointerDown,
                onPointerMove: _dragSelect.onPointerMove,
                onPointerUp: _dragSelect.onPointerUp,
                onPointerCancel: _dragSelect.onPointerCancel,
                child: scrollView,
              ),
            ),
            if (showScrubber)
              // 轨道顶边 = 吸顶区下沿；跳转按 offsets（越拖越准），气泡实时
              // 取吸顶区下沿以下第一项。这一层和朋友圈相册是同一份实现。
              timelineScrubberLayer(
                controller: _gridScroll,
                itemCount: displayItems.length,
                itemOffsets: layout.metrics.offsets,
                trackTop: layout.trackTop,
                liveLabel: () => layout.liveMonthLabel(
                  displayItems,
                  AlbumViewSettings.sort.value,
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
    required int firstHeader,
    required int pinnedSection,
    required int columns,
    required double tileWidth,
    required double dpr,
    required List<Media> displayItems,
  }) {
    final slivers = <Widget>[];

    if (!widget.coverPickMode) {
      slivers.add(_buildHeader(context));
    }
    if (_items.isNotEmpty) {
      // 吸顶区只有**一块玻璃**：分类行 + 日期行，一起钉、一起滚。日期行显示
      // 当前那一组（还没滚到第一组时就是第一组），与两条独立吸顶条相比，
      // 两行之间既没有接缝，也不会各自吸顶叠成两层。
      final displayed = pinnedSection >= 0 ? pinnedSection : firstHeader;
      final section = displayed >= 0 && displayed < sections.length
          ? sections[displayed]
          : null;
      slivers.add(
        AlbumPinnedChromeSliver(
          counts: widget.coverPickMode ? null : _counts,
          selected: _filter,
          onChanged: _selectFilter,
          dateText: section?.header,
          dateCount: section?.items.length,
        ),
      );
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
        const SliverFillRemaining(
          hasScrollBody: false,
          // 空相册不摆按钮：上传入口就是右下角那个圆钮（见 [_showUploadFab]），
          // 只读用户没有入口，也不需要一句解释自己是只读。
          child: EmptyState(
            icon: Icons.photo_library_outlined,
            title: '相册还是空的',
          ),
        ),
      );
      return slivers;
    }
    if (displayItems.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            // 图标与「照片 / 动态照片 / 视频」的名字都取自筛选本身，
            // 三处空状态不会再各写一句。
            icon: _filter.emptyIcon,
            title: '还没有${_filter.noun}',
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
      // 第一组的日期摆在吸顶那块玻璃里（见 [AlbumPinnedChromeSliver]），
      // 内容流里不再有它：多一条就会同一句日期出现两次，而且第一行照片会被
      // 顶低一个分组头。其余分组的头是内容流里的普通 38 高横条，滚到玻璃
      // 底下就被盖住——那一刻玻璃里的日期行正好换成这一组。
      // 张数用 [DateHeader.count] 传：它和日期文字用同一套自动墨色。
      if (section.header != null && sectionIndex != firstHeader) {
        slivers.add(
          timelineDateHeaderSliver(
            section: section,
            count: section.items.length,
          ),
        );
      }
      final start = sectionStart;
      sectionStart += section.items.length;
      slivers.add(
        SliverPadding(
          // 顶部内边距取时间轴那一份（= 0）：分组头与网格之间的留白已经算在
          // 分组头自己身上，网格再补一份就会在吸顶条下沿漏出页面底色。
          padding: const EdgeInsets.fromLTRB(
            _pagePadding,
            kTimelineGridTopPadding,
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
    // 头部只留相册名：以前展开态下面还有一行「N 张照片 · M 个视频」，那行统计
    // 与筛选条角标里的数字重复，用户明确要求去掉（角标不动）。
    final delegate = _AlbumHeaderDelegate(
      topPadding: MediaQuery.paddingOf(context).top,
      // 多选态直接把头图收成一条工具栏，屏幕让给勾选。
      contentHeight: _selecting
          ? kToolbarHeight
          : (_hasCover ? _headerCoverHeight : _headerPlainHeight),
      title: _selecting ? '已选 ${_selected.length} 项' : _album.title,
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
                  ? () => _longPressTile(media)
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
                      : Colors.white.withValues(alpha: 0.5),
                  width: selected ? 2.5 : 1,
                ),
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.04),
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
                      : Colors.black.withValues(alpha: 0.35),
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

  /// 吸顶玻璃里分类行的高度：选封面时筛选条挂在 AppBar 上、空相册没有分类行。
  double get _filterBarExtent =>
      widget.coverPickMode || _items.isEmpty ? 0 : kAppSegmentedBarHeight;

  /// 内容流里日期分组头的整体高度（含与网格之间的留白）：平铺分组时没有。
  ///
  /// 玻璃里那一行日期是 [kTimelineDateHeaderHeight]（34，没有那 4px 留白），
  /// 两者不是同一个数，各管各的。
  double get _dateHeaderExtent =>
      AlbumViewSettings.group.value == AlbumGroup.flat
          ? 0
          : kTimelineDateHeaderExtent;

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
    // 长按这一下手指还按在屏幕上：接着拖就是连续选中。方向在这里就定死
    // （= 这一格刚被选上），不然留到第一次 move 再按「从已选中项起手」反推，
    // 会得到「连续取消」，正好和用户的意思相反。
    _dragSelect.startFromLongPress(media.id);
  }

  void _exitSelection() {
    _dragSelect.reset();
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelect(Media media) {
    setState(() {
      if (!_selected.add(media.id)) _selected.remove(media.id);
    });
  }

  /// 多选态长按：先翻这一格，再把这一轮拖拽的方向接上去（手指还按着）。
  void _longPressTile(Media media) {
    _toggleSelect(media);
    _dragSelect.startFromLongPress(media.id);
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

  /// 拖拽连选把手指划过的格子一次交过来；选中集合变了才重建。
  void _applyDragSelection(Set<int> mediaIds, bool select) {
    var changed = false;
    for (final mediaId in mediaIds) {
      final hit = select ? _selected.add(mediaId) : _selected.remove(mediaId);
      if (hit) changed = true;
    }
    if (changed) setState(() {});
  }

  /// 拖拽连选靠命中检测找格子：只有真正建出来的格子有 render box，
  /// 划出屏幕的格子自然命中不到，滚回来还能接着选。
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
            // 危险动作：用现有语义色（AppColors.danger），不是正文色。
            danger: true,
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

/// 相册头：封面随滚动折叠成一条工具栏，展开时只露出相册名。
///
/// 自己算收缩进度，是为了让「展开标题块」和「工具栏标题」交叉淡入淡出，
/// 中间不会出现两块同名文字；折叠后的高度也和详情页算时间轴时用的
/// 吸顶高度是同一个数。
class _AlbumHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double topPadding;
  final double contentHeight;
  final String title;
  final String? coverUrl;
  final Widget leading;
  final List<Widget> actions;
  final IconData? toolbarIcon;

  _AlbumHeaderDelegate({
    required this.topPadding,
    required this.contentHeight,
    required this.title,
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
          // 没有封面时这一块**不垫自己的底色**：页面背景（[AppGlassBackdrop]）
          // 直接从下面透上来，和「相册 tab」里的观感一致——同一个相册从 tab
          // 进入和从列表 push 进入，顶部不再是「一块白底 + 下面渐变」两种底。
          // 有封面时这张底只做封面图的衬底（折叠过程中它会被 bgPage 工具栏
          // 盖住），所以照旧。
          ColoredBox(color: hasCover ? AppColors.bgPage : Colors.transparent),
          if (hasCover) _cover(context, t),
          // 工具栏底色：折叠过程中渐显，保证图标和标题始终读得清。
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _toolbarExtent,
            child: IgnorePointer(
              child: ColoredBox(
                color: AppColors.bgPage.withValues(alpha: surfaceOpacity),
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
                  // 展开态只剩相册名：统计行（N 张照片 · M 个视频）已删除。
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleLarge.copyWith(
                      color: hasCover ? Colors.white : AppColors.textPrimary,
                    ),
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
        coverUrl != oldDelegate.coverUrl ||
        leading != oldDelegate.leading ||
        actions != oldDelegate.actions ||
        toolbarIcon != oldDelegate.toolbarIcon;
  }
}

/// 「上传照片」按钮：相册页右下角的**玻璃圆钮**，和多选底栏 / footer 同一套材质。
///
/// 形状：圆形，直径 [diameter]（就是原来胶囊的高度 48）；里面只有一个「+」
/// 图标（[iconSize]），没有文字、也没有左右内边距——宽度不再由内容撑开，
/// 落点也就稳定（[AlbumUploadFabLocation] 用同一个直径算右缘）。图标用主题色，
/// 玻璃自己给底衬。
///
/// 材质：走 [AppGlassSurface]——档位取 [preferredQuality]（与底部胶囊同档，
/// [AppBottomTabBar.preferredQuality]）、[preferPremium]，所以光学参数
/// （thickness 28 / refractiveIndex 1.38 / chromaticAberration 0.10 / blur 3）
/// 和 footer 是同一份；内部叠一层 scrim，浮在照片上文字也不跳。
///
/// 降级：premium 拿不到退回磨砂档；连磨砂都跑不了（注入 minimal / 平台不支持
/// shader）时退成同尺寸、同圆角的不透明 [AppColors.bgSurface] + 1px 细边，
/// 布局一模一样，不跳版也不白屏。
class AlbumUploadFab extends StatefulWidget {
  /// 直径（也是高度，不含外边距）。圆形按钮没有「宽度由内容撑开」这回事。
  static const double diameter = 48;

  /// 圆角 = 半径，正好是一个圆。
  static const double radius = diameter / 2;

  /// 「+」图标的尺寸。
  static const double iconSize = 22;

  /// 按钮右缘到时间轴轨道**左缘**的最小间距（见 [AlbumUploadFabLocation]）。
  static const double trackGap = 8;

  /// 按钮下缘离底部安全区的间距。
  static const double bottomGap = 16;

  /// 与底部胶囊同档：premium（拿不到时由 [AppGlassSurface] 自己退档）。
  static const GlassQuality preferredQuality = AppBottomTabBar.preferredQuality;

  /// 玻璃表面自己的 key：测试用它量「按钮矩形不与时间轴轨道相交」。
  static const Key surfaceKey = ValueKey<String>('album-upload-fab');

  final VoidCallback onPressed;

  const AlbumUploadFab({super.key, required this.onPressed});

  @override
  State<AlbumUploadFab> createState() => _AlbumUploadFabState();
}

class _AlbumUploadFabState extends State<AlbumUploadFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '上传照片',
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AppGlassSurface(
            key: AlbumUploadFab.surfaceKey,
            radius: AlbumUploadFab.radius,
            requestedQuality: AlbumUploadFab.preferredQuality,
            // 静态 chrome：优先 premium（折射），拿不到时自己退回磨砂档。
            preferPremium: true,
            // 后面是滚动的照片墙：叠一层 scrim 给图标一块稳定底衬。
            scrim: true,
            child: SizedBox(
              width: AlbumUploadFab.diameter,
              height: AlbumUploadFab.diameter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onPressed,
                child: Center(
                  // 「+」的明暗也跟背景走（方案 C）：主题色在底衬上够 3:1 就
                  // 保留主题色（正常背景仍是紫的），压在极端照片上就换成墨色
                  // ——见 app_glass_tone.dart 的 appGlassReadableAccent。
                  child: ValueListenableBuilder<Color?>(
                    valueListenable: AppBackdropSample.color,
                    builder: (context, backdrop, _) => Icon(
                      Icons.add,
                      size: AlbumUploadFab.iconSize,
                      color: appGlassReadableAccent(
                        AppColors.primary,
                        backdrop: backdrop,
                      ),
                    ),
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

/// 上传按钮的落点：右下角，但整枚按钮让开右侧时间轴的轨道区。
///
/// 默认的 [FloatingActionButtonLocation.endFloat] 只留 16：按钮右缘会压在
/// [kTimelineTrackWidth] 宽的那条轨道上——轨道下半段既拖不到也看不清。这里
/// 右缘固定停在「轨道左缘再往左 [AlbumUploadFab.trackGap]」，底部与 endFloat
/// 同一个口径（16 + 安全区）。
class AlbumUploadFabLocation extends FloatingActionButtonLocation {
  const AlbumUploadFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final size = geometry.floatingActionButtonSize;
    final left = geometry.scaffoldSize.width -
        kTimelineTrackWidth -
        AlbumUploadFab.trackGap -
        size.width;
    final top = geometry.contentBottom -
        size.height -
        AlbumUploadFab.bottomGap -
        geometry.minInsets.bottom;
    return Offset(left, top);
  }
}
