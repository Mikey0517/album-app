import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/album_api.dart';
import '../../core/api_client.dart';
import '../../core/design/colors.dart';
import '../../core/responsive.dart';
import '../../core/design/radius.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';
import '../../core/url_utils.dart';
import '../../models/album.dart';
import '../../widgets/app_bottom_tab_bar.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import 'album_detail_page.dart';
import 'album_share_sheet.dart';
import 'album_title_dialog.dart';
import '../../core/media_cache.dart';

/// 相册页的两个列表：家庭相册 / 私人相册（含别人分享给我的）。
enum AlbumScope { family, private }

/// 网格水平内边距（16）与列间距（12）：封面边长按它们算，别处不要再写死。
const double _gridHPadding = 16;
const double _gridColumnSpacing = 12;
const double _gridRowSpacing = 16;

/// 相册封面所在格子的 key：封面必须是「一格宽的正方形」。
/// 「新建相册」按钮用同一个 key 前缀的尺寸，测试据此断言两者一样大。
const Key albumCoverKey = Key('album-tile-cover');

/// 「新建相册」按钮的 key。
const Key newAlbumCardKey = Key('new-album-card');

/// 封面下方那两行文字（标题 + 「N 张照片」）的实际高度。
///
/// 封面要做成正方形，格子高度就得显式等于「封面边长 + 这段文字高度」；
/// 继续用 childAspectRatio 的话，网格会反过来把封面压成长方形。这里用
/// TextPainter 按真实字体度量取高度，文字放大时格子跟着长高，不会溢出。
double _tileTextBlockHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  double lineHeight(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: '相册名', style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return painter.height;
  }

  // 间距：标题前 8、张数前 2；多留 0.5 兜住亚像素取整。
  return AppSpacing.sm +
      lineHeight(AppText.body) +
      2 +
      lineHeight(AppText.caption) +
      0.5;
}

class CustomAlbumsPage extends StatefulWidget {
  final AlbumScope scope;

  /// 列表数量回报给父级 tab 条上的数字；只在加载成功后报，失败时保留旧值。
  final ValueChanged<int>? onCountChanged;

  const CustomAlbumsPage({
    super.key,
    this.scope = AlbumScope.family,
    this.onCountChanged,
  });

  @override
  State<CustomAlbumsPage> createState() => _CustomAlbumsPageState();
}

class _CustomAlbumsPageState extends State<CustomAlbumsPage> {
  final List<Album> _albums = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final albums = await AlbumApi.list();
      if (!mounted) return;
      final wantPrivate = widget.scope == AlbumScope.private;
      setState(() {
        _albums
          ..clear()
          ..addAll(albums.where((album) => album.isPrivate == wantPrivate));
        _loading = false;
      });
      widget.onCountChanged?.call(_albums.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiClient.errorText(e);
      });
    }
  }

  Future<void> _create() async {
    final isPrivate = widget.scope == AlbumScope.private;
    final title = await showAlbumTitleDialog(
      context,
      heading: isPrivate ? '新建私人相册' : '新建相册',
    );
    if (title == null || !mounted) return;
    try {
      await AlbumApi.create(title, isPrivate: isPrivate);
      await _load();
      if (mounted && isPrivate) {
        _snack('私人相册已创建，长按可以分享给家人');
      }
    } catch (e) {
      if (!mounted) return;
      _snack(ApiClient.errorText(e));
    }
  }

  Future<void> _rename(Album album) async {
    final title = await showAlbumTitleDialog(
      context,
      heading: '重命名相册',
      actionLabel: '保存',
      initialTitle: album.title,
    );
    if (title == null || !mounted || title == album.title) return;
    try {
      await AlbumApi.rename(album.id, title);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(ApiClient.errorText(e));
    }
  }

  Future<void> _delete(Album album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${album.title}」？', style: AppText.titleMedium),
        content: const Text(
          '相册里的独立照片会被一并删除；来自朋友圈的照片仍保留在朋友圈。',
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
      await AlbumApi.delete(album.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(ApiClient.errorText(e));
    }
  }

  Future<void> _openMenu(Album album) async {
    if (!album.canManage) {
      _snack('这是 ${album.ownerLabel} 分享给你的私人相册，只有创建者可以管理');
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _handle(),
                if (album.isPrivate && album.isOwner)
                  ListTile(
                    leading: Icon(Icons.people_alt_outlined,
                        size: 20, color: AppColors.textPrimary),
                    title: const Text('分享给家人'),
                    subtitle: Text(
                      album.shareCount > 0
                          ? '已分享给 ${album.shareCount} 人'
                          : '目前只有你自己能看到',
                      style: AppText.caption,
                    ),
                    onTap: () => Navigator.pop(context, 'share'),
                  ),
                ListTile(
                  leading: Icon(Icons.wallpaper_outlined,
                      size: 20, color: AppColors.textPrimary),
                  title: const Text('修改封面'),
                  onTap: () => Navigator.pop(context, 'cover'),
                ),
                ListTile(
                  leading: Icon(Icons.edit_outlined,
                      size: 20, color: AppColors.textPrimary),
                  title: const Text('重命名'),
                  onTap: () => Navigator.pop(context, 'rename'),
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline,
                      size: 20, color: AppColors.danger),
                  title:
                      Text('删除相册', style: TextStyle(color: AppColors.danger)),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (action == 'cover') await _pickCover(album);
    if (action == 'rename') await _rename(album);
    if (action == 'delete') await _delete(album);
    if (action == 'share') {
      if (!mounted) return;
      await showAlbumShareSheet(context, album);
      if (mounted) await _load();
    }
  }

  Future<void> _pickCover(Album album) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => AlbumDetailPage(
          album: album,
          coverPickMode: true,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _load();
      if (mounted) _snack('封面已更新');
    }
  }

  Widget _handle() {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }

  Future<void> _open(Album album) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => AlbumDetailPage(album: album),
      ),
    );
    if (mounted) await _load();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _albums.isEmpty) {
      return const LoadingView(message: '正在加载相册');
    }
    if (_error != null && _albums.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '加载失败',
        subtitle: _error!,
        action: FilledButton(
          onPressed: _load,
          child: const Text('重新加载'),
        ),
      );
    }
    if (_albums.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            EmptyState(
              icon: widget.scope == AlbumScope.private
                  ? Icons.lock_outline
                  : Icons.photo_library_outlined,
              title: widget.scope == AlbumScope.private ? '还没有私人相册' : '还没有相册',
              subtitle: widget.scope == AlbumScope.private
                  ? '私人相册只有你自己能看到，创建后可以分享给家人'
                  : '创建一个相册，把家人的照片收在一起',
              action: FilledButton(
                onPressed: _create,
                child: const Text('新建相册'),
              ),
            ),
          ],
        ),
      );
    }

    final dpr = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 封面边长 = 一列的宽度，跟着列数和间距走；封面是正方形，
        // 「新建相册」按钮用同一个边长，两者才能逐像素对齐。
        final columns = responsiveColumns(context, 2);
        final gridWidth = constraints.maxWidth - _gridHPadding * 2;
        final coverSize =
            (gridWidth - _gridColumnSpacing * (columns - 1)) / columns;
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: GridView.builder(
            // 末尾余量只留半个胶囊高：相册封面一直铺到悬浮胶囊底下，滚到底时
            // 最后一行能滑出胶囊下沿。
            padding: const EdgeInsets.fromLTRB(
              _gridHPadding,
              8,
              _gridHPadding,
              24 + AppBottomTabBar.contentBottomInset,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _albums.length + 1,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: _gridRowSpacing,
              crossAxisSpacing: _gridColumnSpacing,
              // 格子高度 = 正方形封面 + 两行文字。这里不能用 childAspectRatio：
              // 那个比例只认格子高宽，会把封面重新压成长方形。
              mainAxisExtent: coverSize + _tileTextBlockHeight(context),
            ),
            itemBuilder: (context, index) {
              if (index == _albums.length) {
                return _NewAlbumCard(onTap: _create, size: coverSize);
              }
              final album = _albums[index];
              return _AlbumTile(
                album: album,
                coverSize: coverSize,
                cacheWidth: (coverSize * dpr).round(),
                onTap: () => _open(album),
                onLongPress: () => _openMenu(album),
              );
            },
          ),
        );
      },
    );
  }
}

class _AlbumTile extends StatefulWidget {
  final Album album;

  /// 封面边长（正方形），由网格列数与间距算出。
  final double coverSize;
  final int cacheWidth;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AlbumTile({
    required this.album,
    required this.coverSize,
    required this.cacheWidth,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面：一格宽的正方形，和「新建相册」按钮同尺寸。
              SizedBox(
                key: albumCoverKey,
                width: double.infinity,
                height: widget.coverSize,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.mediaPlaceholder,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _cover(),
                      if (widget.album.isPrivate && !widget.album.isOwner)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people_alt_outlined,
                                    size: 11, color: Colors.white),
                                const SizedBox(width: 3),
                                Text(
                                  '来自 ${widget.album.ownerLabel}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.album.mediaCount} 张照片',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover() {
    final path = widget.album.coverThumb;
    if (path == null || path.isEmpty) {
      return Container(
        color: AppColors.mediaPlaceholder,
        alignment: Alignment.center,
        child: Icon(
          Icons.photo_outlined,
          size: 32,
          color: AppColors.textTertiary,
        ),
      );
    }
    final url = fullUrl(path);
    return CachedNetworkImage(
      cacheManager: MediaCache.manager,
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: widget.cacheWidth,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => Container(
        color: AppColors.mediaPlaceholder,
      ),
      errorWidget: (context, url, error) => Container(
        color: AppColors.mediaPlaceholder,
        alignment: Alignment.center,
        child: Icon(
          Icons.photo_outlined,
          size: 32,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _NewAlbumCard extends StatelessWidget {
  final VoidCallback onTap;

  /// 正方形边长：和同排相册封面的边长是同一个值（网格列宽）。
  final double size;

  const _NewAlbumCard({required this.onTap, required this.size});

  @override
  Widget build(BuildContext context) {
    // 相册页唯一的卡片：和朋友圈的 PostCard、我的页的卡片组走同一条材质
    // 路径（[AppCard]：外框 = 内容 + padding，玻璃/不透明两档同一个外框），
    // 档位也同一处（[AppGlassSurface.kCardQuality]：与底部胶囊同档的 premium）。
    // 圆角跟相册格子对齐，避免这一格比旁边「凸出来」。
    //
    // 形状是正方形，边长 = 封面边长：从上沿对齐，和同排封面逐像素重合；
    // 图标 + 文字在正方形里水平垂直居中。
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        key: newAlbumCardKey,
        width: size,
        height: size,
        child: AppCard(
          glass: true,
          onTap: onTap,
          radius: BorderRadius.circular(AppRadius.md),
          padding: EdgeInsets.zero,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 32, color: AppColors.textTertiary),
                const SizedBox(height: 6),
                const Text('新建相册', style: AppText.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
