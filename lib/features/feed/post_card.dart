import 'package:flutter/material.dart';

import '../../api/post_api.dart';
import '../../core/api_client.dart';
import '../../core/app_events.dart';
import '../../core/current_user.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';
import '../../models/media.dart';
import '../../models/post.dart';
import '../../widgets/album_thumb.dart';
import '../../widgets/app_glass.dart';
import 'compose_page.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final void Function(List<Media> medias, int index) onOpenMedia;
  final VoidCallback onDeleted;

  /// 文案改完回来了：列表拿更新后的这条动态就地替换，不用整页重拉。
  final ValueChanged<Post>? onEdited;

  const PostCard({
    super.key,
    required this.post,
    required this.onOpenMedia,
    required this.onDeleted,
    this.onEdited,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

/// 朋友圈一条动态的媒体区有两种看法：
///
/// - [large]：大图（Instagram 那样），一张占满屏宽、左右滑动、底部一排小圆点。
///   这一种**不套卡片**：照片直接压在页面背景上，没有圆角、没有描边；
/// - [grid]：九宫格（原来的样子），放在卡片里，信息更密。
///
/// 右上角那枚图标在两种看法之间切换。
enum PostMediaLayout { large, grid }

/// 大图那一枚「切回九宫格 / 切成大图」按钮的 key。
const Key postMediaModeToggleKey = ValueKey<String>('post-media-mode-toggle');

/// 底部页码圆点（只在多张时出现）。
class PostPageDots extends StatelessWidget {
  final int count;
  final int index;

  const PostPageDots({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: i == index ? 0.95 : 0.45),
              // 白点在浅色照片上也要看得见。
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 右上角的模式切换：大图 ↔ 九宫格。
class _MediaModeToggle extends StatelessWidget {
  final PostMediaLayout layout;
  final VoidCallback onTap;

  const _MediaModeToggle({required this.layout, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final large = layout == PostMediaLayout.large;
    return IconButton(
      key: postMediaModeToggleKey,
      onPressed: onTap,
      tooltip: large ? '切换九宫格' : '切换大图',
      iconSize: 17,
      style: IconButton.styleFrom(
        fixedSize: const Size(32, 32),
        // 命中区就按 32 算：默认会被 IconButton 撑到 48，在九宫格里正好压住
        // 右上角那一格，点照片就变成切模式了。
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.black.withValues(alpha: 0.45),
        foregroundColor: Colors.white,
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.32),
          width: 1,
        ),
        shape: const CircleBorder(),
      ),
      icon: Icon(
        large ? Icons.grid_view_rounded : Icons.fullscreen_rounded,
      ),
    );
  }
}

/// 大图模式的页高：宽度铺满，高度按图片自身比例，但收在 4:5 ~ 1.91:1 之间
/// （和 Instagram 同一档）。收窄下界是为了长截图不把一屏占满，收窄上界是为了
/// 全景图不把卡片撑成一条线；比例拿不到时按 1:1 处理。
double feedMediaAspectRatio(Media media) {
  final width = media.width ?? 0;
  final height = media.height ?? 0;
  if (width <= 0 || height <= 0) return 1;
  return (width / height).clamp(4 / 5, 1.91).toDouble();
}

int _feedCacheWidth(BuildContext context, double width) =>
    (width * MediaQuery.of(context).devicePixelRatio).round();

/// 大图轮播：一次一张、左右滑动，页码是底部那一排小圆点。
///
/// 圆角/描边一律没有（[radius] 传 0）：大图是铺满屏幕的，任何一圈边都会把
/// 它从页面背景上「切」下来。
class _PostMediaCarousel extends StatefulWidget {
  final List<Media> medias;
  final void Function(List<Media> medias, int index) onOpen;
  final double width;

  const _PostMediaCarousel({
    required this.medias,
    required this.onOpen,
    required this.width,
  });

  @override
  State<_PostMediaCarousel> createState() => _PostMediaCarouselState();
}

class _PostMediaCarouselState extends State<_PostMediaCarousel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final medias = widget.medias;
    if (medias.isEmpty) return const SizedBox.shrink();
    final index = _index.clamp(0, medias.length - 1);
    final height = widget.width / feedMediaAspectRatio(medias.first);
    final cacheWidth = _feedCacheWidth(context, widget.width);

    Widget page(int i) {
      final media = medias[i];
      return AlbumThumb(
        media: media,
        radius: 0,
        cacheWidth: cacheWidth,
        heroTag: 'feed_${media.id}',
        onTap: () => widget.onOpen(medias, i),
        onMotionLongPress: () => widget.onOpen(medias, i),
      );
    }

    // 只有一张时不套 PageView：没有可滑的东西，多一层滚动容器只会多一堆手势。
    if (medias.length == 1) {
      return SizedBox(
        width: widget.width,
        height: height,
        child: page(0),
      );
    }

    return SizedBox(
      width: widget.width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            itemCount: medias.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, i) => page(i),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: IgnorePointer(
              child: Center(
                child: PostPageDots(count: medias.length, index: index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 九宫格（原来的排法）：2/4 张两列，其余三列，格子都是正方形。
class _PostMediaGrid extends StatelessWidget {
  final List<Media> medias;
  final void Function(List<Media> medias, int index) onOpen;
  final double width;

  const _PostMediaGrid({
    required this.medias,
    required this.onOpen,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final columns = medias.length == 2 || medias.length == 4 ? 2 : 3;
    const gap = 4.0;
    final tile = (width - gap * (columns - 1)) / columns;
    final cacheWidth = _feedCacheWidth(context, tile);
    return SizedBox(
      width: width,
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < medias.length; i++)
            SizedBox(
              width: tile,
              height: tile,
              child: AlbumThumb(
                media: medias[i],
                radius: AppRadius.sm,
                cacheWidth: cacheWidth,
                heroTag: 'feed_${medias[i].id}',
                onTap: () => onOpen(medias, i),
                onMotionLongPress: () => onOpen(medias, i),
              ),
            ),
        ],
      ),
    );
  }
}

class _PostCardState extends State<PostCard> {
  bool _collapsed = false;
  bool _deleting = false;

  /// 这条动态当前怎么看：默认大图（Instagram 那套），点右上角图标切九宫格。
  /// 只记在这一条动态上：换个帖子又想密着看是另一回事。
  PostMediaLayout _layout = PostMediaLayout.large;

  bool get _isMine => widget.post.authorId == CurrentUser.notifier.value?.id;

  /// 编辑入口复用发布页的编辑器：媒体只读，只能改文案。
  Future<void> _openEdit() async {
    if (_deleting) return;
    final updated = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (context) => ComposePage(editPost: widget.post),
      ),
    );
    if (!mounted || updated is! Post) return;
    AppEvents.notifyPostChanged();
    widget.onEdited?.call(updated);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除这条动态？', style: AppText.titleMedium),
          content: const Text(
            '删除后，动态里的照片和视频也会从朋友圈相册中消失。',
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
        );
      },
    );
    if (confirmed != true || _deleting) return;

    setState(() => _deleting = true);
    try {
      await PostApi.delete(widget.post.id);
      AppEvents.notifyPostChanged();
      if (!mounted) return;
      setState(() => _collapsed = true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted) widget.onDeleted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.errorText(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final large =
        _layout == PostMediaLayout.large && widget.post.medias.isNotEmpty;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: _collapsed
          ? const SizedBox(width: double.infinity)
          : large
              ? _buildLargePost()
              : _buildCardPost(),
    );
  }

  bool get _hasCaption => (widget.post.content ?? '').trim().isNotEmpty;

  Widget _buildCaption() => Text(widget.post.content!, style: AppText.body);

  /// 大图：**不套卡片**。照片铺满屏宽、没有圆角和描边，头图上面是作者那一行，
  /// 说明文字压在照片下面——页面背景就是它的底。
  Widget _buildLargePost() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: _buildHeader(),
        ),
        LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.centerLeft,
            child: _buildMediaBlock(constraints.maxWidth),
          ),
        ),
        if (_hasCaption)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: _buildCaption(),
          ),
      ],
    );
  }

  /// 九宫格：原来的卡片。玻璃只铺在卡片本体上，列表/页面的背景保持不变。
  ///
  /// 档位固定用 [AppGlassSurface.kCardQuality]，现在是 standard：纯
  /// BackdropFilter，**不抓 capture**。这不是性能取舍，是黑卡的修法——premium
  /// 的 capture 在列表重建/刷新那一帧还没就绪，会画出一块近黑（见
  /// kCardQuality 的注释与 test/feed_refresh_glass_test.dart）。折射留给底部
  /// 胶囊那种静态 chrome；卡片仍不自建层（useOwnLayer 默认 false），内容有
  /// RepaintBoundary 兜着，滚动时不会每帧重建。
  /// 降到 minimal / 玻璃不可用时就是不透明的 bgSurface，布局完全一致。
  /// depth：双层阴影 + 顶部内高光 + 1px 描边，磨砂档与退化档一样有层次
  /// （只是退化档没有模糊），卡片本身不做位移动画。
  Widget _buildCardPost() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: AppGlassSurface(
        radius: AppRadius.lg,
        padding: const EdgeInsets.all(16),
        requestedQuality: AppGlassSurface.kCardQuality,
        depth: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (widget.post.medias.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.centerLeft,
                  child: _buildMediaBlock(constraints.maxWidth),
                ),
              ),
            ],
            if (_hasCaption) ...[
              const SizedBox(height: AppSpacing.md),
              _buildCaption(),
            ],
          ],
        ),
      ),
    );
  }

  /// 媒体区 + 右上角那枚模式切换按钮：大图时是满屏轮播，九宫格时是三列格子。
  ///
  /// iPad 上单条动态很宽时限制在 640 以内，避免一张图占满整块横屏。
  Widget _buildMediaBlock(double available) {
    final width = available > 640 ? 640.0 : available;
    final medias = widget.post.medias;
    return Stack(
      children: [
        _layout == PostMediaLayout.large
            ? _PostMediaCarousel(
                medias: medias,
                onOpen: widget.onOpenMedia,
                width: width,
              )
            : _PostMediaGrid(
                medias: medias,
                onOpen: widget.onOpenMedia,
                width: width,
              ),
        Positioned(
          top: 8,
          right: 8,
          child: _MediaModeToggle(
            layout: _layout,
            onTap: () => setState(
              () => _layout = _layout == PostMediaLayout.large
                  ? PostMediaLayout.grid
                  : PostMediaLayout.large,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final nickname = widget.post.authorNickname;
    final initial = nickname.isEmpty ? '?' : nickname.substring(0, 1);
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.primaryLight,
          child: Text(
            initial,
            style: AppText.body.copyWith(
              color: AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          nickname,
          style: AppText.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(formatPostTime(widget.post.postedAt), style: AppText.caption),
        // 改过就标一下，不解释改了什么。
        if (widget.post.editedAt != null) ...[
          const SizedBox(width: 6),
          const Text('已编辑', style: AppText.caption),
        ],
        if (_isMine) ...[
          const SizedBox(width: 2),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                _openEdit();
              } else if (value == 'delete') {
                _confirmDelete();
              }
            },
            tooltip: '更多',
            padding: EdgeInsets.zero,
            icon: _deleting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'edit',
                child: Text('编辑'),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text('删除', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        ],
      ],
    );
  }


}
