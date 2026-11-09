import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../api/album_api.dart';
import '../../core/album_view_settings.dart';
import '../../core/api_client.dart';
import '../../core/app_events.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/shadow.dart';
import '../../core/design/text_styles.dart';
import '../../core/media_picker.dart';
import '../../core/responsive.dart';
import 'photo_timeline_scrubber.dart';
import '../../core/media_store.dart';
import '../../core/upload_manager.dart';
import '../../models/album.dart';
import '../../models/media.dart';
import '../../widgets/album_thumb.dart';
import '../../widgets/date_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../../core/media_share_service.dart';
import '../../widgets/selection_footer.dart';
import '../download/batch_download.dart';
import '../viewer/media_viewer_page.dart';
import 'album_share_sheet.dart';
import 'album_title_dialog.dart';

class AlbumDetailPage extends StatefulWidget {
  final Album album;
  final bool coverPickMode;

  const AlbumDetailPage({
    super.key,
    required this.album,
    this.coverPickMode = false,
  });

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  late Album _album = widget.album;
  final List<Media> _items = [];
  bool _loading = true;
  String? _error;
  bool _selecting = false;
  bool _batchDownloading = false;
  bool _batchDeleting = false;
  bool _batchMoving = false;
  bool _deduping = false;
  final Set<int> _selected = {};
  int? _coverSelectedId;
  final ScrollController _gridScroll = ScrollController();
  // 用来量一次日期分组头的高度：分组头样式一致，量到一个就能算出整条时间轴的偏移。
  final GlobalKey _firstHeaderKey = GlobalKey();

  static const int _uploadLimit = 500;

  /// 能上传/删除照片（可写及以上）。
  bool get _canEdit => _album.canEditMedia;

  /// 能改名/改封面/删相册（管理员及以上）。
  bool get _canManage => _album.canManage;

  @override
  void initState() {
    super.initState();
    AlbumViewSettings.sort.addListener(_onViewChanged);
    AlbumViewSettings.group.addListener(_onViewChanged);
    AppEvents.albumContentRevision.addListener(_onAlbumContentChanged);
    _load();
  }

  @override
  void dispose() {
    AlbumViewSettings.sort.removeListener(_onViewChanged);
    AlbumViewSettings.group.removeListener(_onViewChanged);
    AppEvents.albumContentRevision.removeListener(_onAlbumContentChanged);
    _gridScroll.dispose();
    super.dispose();
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
      final detail = await AlbumApi.detail(widget.album.id);
      if (!mounted) return;
      setState(() {
        _album = detail.album;
        _items
          ..clear()
          ..addAll(detail.items);
        _selected.removeWhere(
          (id) => !_items.any((item) => item.id == id),
        );
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

  /// 上传成功后问用户要不要删掉手机相册里的原图（只删这一批上传成功的）。
  Future<void> _offerDeleteOriginals() async {
    // 删除系统相册原图只有 Android 实现，iOS 上不提示。
    if (!Platform.isAndroid || !mounted) return;
    final uploaded =
        UploadManager.instance.takeCompletedWithSource(albumId: _album.id);
    if (uploaded.isEmpty) return;
    final targets = uploaded
        .map((item) => (uri: item.sourceUri!, isVideo: item.isVideo))
        .toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除手机里的原图？', style: AppText.titleMedium),
        content: Text(
          '${targets.length} 项已上传到「${_album.title}」。\n'
          '删除后手机相册里就没有这些照片了，且无法恢复。',
          style: AppText.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('保留'),
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
    final result = await MediaStore.deleteSources(targets);
    if (!mounted) return;
    if (result.deleted == 0) {
      final reason = result.error;
      _snack(
        reason == null || reason.isEmpty
            ? '没能删除，请稍后在系统相册里手动删除'
            : '没能删除（$reason），请到系统相册里手动删除',
      );
    } else if (result.isPartial) {
      _snack('已删除 ${result.deleted} 张，${result.failed} 张未能删除');
    } else {
      _snack('已删除 ${result.deleted} 张原图');
    }
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

  Future<void> _cleanDuplicates() async {
    if (_deduping) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理重复照片和视频？', style: AppText.titleMedium),
        content: const Text(
          '将按文件 SHA-256 对比当前相册内的媒体，每组只保留一项。\n\n'
          '如果文件还被其他相册或朋友圈动态引用，只会清除多余的相册引用，不会误删文件。',
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
            child: const Text('开始清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deduping = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('正在对比文件 hash…')),
            ],
          ),
        ),
      ),
    );
    try {
      final result = await AlbumApi.dedupe(_album.id);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _load(silent: true);
      if (!mounted) return;
      final removed = (result['removed'] as num?)?.toInt() ?? 0;
      final groups = (result['groups'] as num?)?.toInt() ?? 0;
      final scanned = (result['scanned'] as num?)?.toInt() ?? 0;
      _snack(
        removed == 0
            ? '扫描 $scanned 项，没有发现重复'
            : '扫描 $scanned 项，清理 $groups 组，共移除 $removed 项',
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _snack(ApiClient.errorText(e));
      }
    } finally {
      if (mounted) setState(() => _deduping = false);
    }
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

  @override
  Widget build(BuildContext context) {
    if (widget.coverPickMode) return _buildCoverPicker();
    final title = '${_album.title} · ${_items.length} 张';
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selecting) _exitSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _selecting
              ? IconButton(
                  onPressed: _batchDownloading ? null : _exitSelection,
                  icon: const Icon(Icons.close),
                  tooltip: '退出选择',
                )
              : null,
          title: Text(
            _selecting ? '已选 ${_selected.length} 项' : title,
            overflow: TextOverflow.ellipsis,
          ),
          actions: _selecting
              ? [
                  TextButton(
                    onPressed:
                        _batchDownloading || _batchDeleting || _batchMoving
                            ? null
                            : _toggleSelectAll,
                    child: Text(_allSelected ? '取消全选' : '全选'),
                  ),
                ]
              : [
                  IconButton(
                    onPressed: () => showAlbumViewMenu(context),
                    tooltip: '排序与视图',
                    icon: Icon(
                      Icons.tune_rounded,
                      size: 22,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (_canEdit || _canManage)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (_deduping) return;
                        if (value == 'rename') _rename();
                        if (value == 'dedupe') _cleanDuplicates();
                        if (value == 'delete') _deleteAlbum();
                        if (value == 'share') _shareAlbum();
                      },
                      tooltip: '相册操作',
                      icon: Icon(Icons.more_horiz,
                          size: 22, color: AppColors.textPrimary),
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
                          const PopupMenuItem<String>(
                              value: 'dedupe', child: Text('清理重复照片和视频')),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('删除相册',
                                style: TextStyle(color: AppColors.danger)),
                          ),
                        ],
                      ],
                    ),
                ],
        ),
        floatingActionButton:
            _selecting || !_canEdit ? null : _DetailFab(onPressed: _upload),
        bottomNavigationBar: _selecting ? _buildSelectionBar() : null,
        body: Column(
          children: [
            if (_album.isPrivate && !_album.isOwner)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.primaryLight.withOpacity(0.5),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '来自 ${_album.ownerLabel} 的私人相册 · ${_album.roleLabel}',
                        style: AppText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildBody()),
          ],
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
      ),
      body: _buildBody(),
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
    });
  }

  void _toggleSelect(Media media) {
    setState(() {
      if (!_selected.add(media.id)) _selected.remove(media.id);
    });
  }

  bool get _allSelected =>
      _items.isNotEmpty && _selected.length == _items.length;

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_items.map((item) => item.id));
      }
    });
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
  }

  Widget _buildSelectionBar() {
    final busy = _batchDownloading || _batchDeleting || _batchMoving;
    return SelectionFooter(
      safeArea: true,
      actions: [
        SelectionFooterAction(
          icon: Icons.download_outlined,
          label: _batchDownloading ? '保存中' : '下载',
          onTap: _selected.isEmpty || busy ? null : _downloadSelected,
        ),
        if (_canEdit)
          SelectionFooterAction(
            icon: Icons.drive_file_move_outline,
            label: _batchMoving ? '移动中' : '移动',
            onTap: _selected.isEmpty || busy ? null : _moveSelected,
          ),
        if (_canEdit)
          SelectionFooterAction(
            icon: Icons.delete_outline,
            label: _batchDeleting ? '删除中' : '删除',
            onTap: _selected.isEmpty || busy ? null : _deleteSelected,
          ),
        SelectionFooterAction(
          icon: Icons.ios_share,
          label: '分享',
          onTap: _selected.isEmpty || busy ? null : _shareSelected,
        ),
      ],
    );
  }

  Future<void> _moveSelected() async {
    if (_batchDownloading || _batchDeleting || _batchMoving) {
      return;
    }
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
    if (_batchDownloading || _batchDeleting || _batchMoving) {
      return;
    }
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

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const LoadingView(message: '正在打开相册');
    }
    if (_error != null && _items.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '加载失败',
        subtitle: _error!,
        action: FilledButton(
          onPressed: () => _load(),
          child: const Text('重新加载'),
        ),
      );
    }
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.photo_outlined,
        title: '相册还是空的',
        subtitle: _canEdit ? '点右下角添加照片或视频' : '创建者还没有往里放照片',
        action: _canEdit
            ? FilledButton(
                onPressed: _upload,
                child: const Text('添加媒体'),
              )
            : null,
      );
    }

    final sections = albumSections(
      _items,
      AlbumViewSettings.sort.value,
      AlbumViewSettings.group.value,
    );
    final displayItems = [
      for (final section in sections) ...section.items,
    ];
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final tile = (MediaQuery.of(context).size.width - 6) / 4;
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
                      onPressed:
                          _batchDownloading || _batchDeleting || _batchMoving
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
            final selected = widget.coverPickMode
                ? _coverSelectedId == media.id
                : _selected.contains(media.id);
            final showSelection = _selecting || widget.coverPickMode;
            return Stack(
              fit: StackFit.expand,
              children: [
                AlbumThumb(
                  media: media,
                  radius: 0,
                  cacheWidth: (tile * dpr).round(),
                  heroTag: 'album_${_album.id}_${media.id}',
                  onTap: widget.coverPickMode
                      ? () => setState(() => _coverSelectedId = media.id)
                      : _selecting
                          ? () => _toggleSelect(media)
                          : () => _openViewer(displayItems, globalIndex),
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
                if (showSelection)
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
                            ? const Icon(Icons.check,
                                size: 14, color: Colors.white)
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
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 100)));
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = responsiveColumns(context, 4);
        final metrics = _timelineMetrics(
          sections,
          constraints.maxWidth,
          columns,
        );
        final showScrubber =
            !_selecting && !widget.coverPickMode && displayItems.length > 12;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _load(silent: true),
              child: CustomScrollView(
                controller: _gridScroll,
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
                  controller: _gridScroll,
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

  /// 算出每一张图在滚动内容里的起始偏移，以及它属于哪个月份分组。
  /// 分组头的实际滚动位置从首次渲染的 key 里量，避免顶部还有别的 sliver 时整体错位。
  ({List<double> offsets, List<String> labels}) _timelineMetrics(
    List<AlbumSection> sections,
    double width,
    int columns,
  ) {
    final offsets = <double>[];
    final labels = <String>[];
    const spacing = 2.0;
    final tileWidth = (width - spacing * (columns - 1)) / columns;
    final rowHeight = tileWidth + spacing;
    final headerHeight = _firstHeaderKey.currentContext?.size?.height ?? 48.0;

    var base = 0.0;
    final headerRender = _firstHeaderKey.currentContext?.findRenderObject();
    if (headerRender is RenderBox && headerRender.attached) {
      try {
        base = RenderAbstractViewport.of(headerRender)
            .getOffsetToReveal(headerRender, 0.0)
            .offset;
      } catch (_) {
        base = 0.0;
      }
    }

    var y = base;
    for (final section in sections) {
      if (section.header != null) {
        y += headerHeight;
      }
      final rows = (section.items.length + columns - 1) ~/ columns;
      for (var i = 0; i < section.items.length; i++) {
        offsets.add(y + (i ~/ columns) * rowHeight);
        // 平铺模式没有分组头，退回按拍摄月份显示，气泡才不会空着。
        final header = section.header;
        labels.add(
          header != null && header.isNotEmpty
              ? header
              : _monthLabel(
                  albumSortDate(
                    section.items[i],
                    AlbumViewSettings.sort.value,
                  ),
                ),
        );
      }
      y += rows * rowHeight;
    }
    return (offsets: offsets, labels: labels);
  }

  String _monthLabel(DateTime time) {
    final local = time.toLocal();
    return '${local.year}年${local.month}月';
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
