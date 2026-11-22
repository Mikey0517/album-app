import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/post_api.dart';
import '../../core/api_client.dart';
import '../../core/app_events.dart';
import '../../core/current_user.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';
import '../../core/feed_view_settings.dart';
import '../../core/formatters.dart';
import '../../core/url_utils.dart';
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

/// 大屏模式单张照片的高度上限：屏幕高度的这个比例。
///
/// 大屏要「最清晰」，就得按照片自己的比例铺（不再为了塞进 4:5 去裁）；竖图
/// 比例一大就会把整条动态撑满屏甚至溢出，所以在这里收一道上限：超过这个高度
/// 的照片整体缩窄、居中，整张图完整露出来，不被裁掉。
const double kFeedWideMaxHeightFactor = 0.72;

/// 大屏多图时右上角的页码：第几张 / 共几张（如 3/4）。
const Key postMediaCounterKey = ValueKey<String>('post-media-counter');

class PostMediaCounter extends StatelessWidget {
  final int index;
  final int count;

  const PostMediaCounter({
    super.key,
    required this.index,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          // 浅色照片上也要看得见。
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 0.5,
          ),
        ),
        child: Text(
          '${index + 1}/$count',
          style: AppText.caption.copyWith(
            color: Colors.white,
            fontSize: 11,
            height: 1.2,
            // 页码跳动时别整块抖：数字等宽。
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// 图片自身的宽高比；拿不到尺寸时按 1:1。
double feedMediaNaturalRatio(Media media) {
  final width = media.width ?? 0;
  final height = media.height ?? 0;
  if (width <= 0 || height <= 0) return 1;
  return width / height;
}

/// 大屏「舞台」的高度：同一组媒体里**最高**的那张按屏宽铺满时的高度，再收在
/// [maxHeight] 以内。
///
/// 同一组照片共用这一个高度，所以左右滑动时画幅不会跳、每条动态的高度也是
/// 固定的：比它矮的照片上下留黑边，超高被 [maxHeight] 截住的那张左右留黑边，
/// 媒体在舞台里水平和垂直都居中。
double feedWideStageHeight(List<Media> medias, double width, double maxHeight) {
  var tallest = 0.0;
  for (final media in medias) {
    final height = width / feedMediaNaturalRatio(media);
    if (height > tallest) tallest = height;
  }
  if (tallest <= 0) return 0;
  return math.min(tallest, maxHeight);
}

/// 大屏模式下的图片地址：图片取服务端 `/files/display` 的 2560px 原图，不再
/// 用 400px 缩略图放大；视频没有可解的原图，仍然用缩略图当封面。
String? feedWideImagePath(Media media) {
  if (media.isVideo) return media.previewPath;
  final path = media.url;
  if (path.isEmpty) return media.previewPath;
  return displayUrl(path);
}

int _feedCacheWidth(BuildContext context, double width) =>
    (width * MediaQuery.of(context).devicePixelRatio).round();

/// 大屏轮播：一次一张、左右滑动，右上角是「第几张/共几张」。
///
/// 舞台高度只由「最高的一张」决定（见 [feedWideStageHeight]），所以同一组
/// 照片滑来滑去画幅不跳、每条动态的高度也是固定的。照片按自己的比例整张
/// 居中放进舞台，空出来的地方就是黑边（[AlbumThumb.backgroundColor]）。
class _PostMediaCarousel extends StatefulWidget {
  final List<Media> medias;
  final void Function(List<Media> medias, int index) onOpen;
  final double width;
  final double maxHeight;

  const _PostMediaCarousel({
    required this.medias,
    required this.onOpen,
    required this.width,
    required this.maxHeight,
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
    // 高度只看「最高的一张」，不跟着当前页变：滑到下一张画幅不跳。
    final stageHeight = feedWideStageHeight(
      medias,
      widget.width,
      widget.maxHeight,
    );
    final cacheWidth = _feedCacheWidth(context, widget.width);

    Widget page(int i) {
      final media = medias[i];
      return AlbumThumb(
        media: media,
        radius: 0,
        cacheWidth: cacheWidth,
        imagePath: feedWideImagePath(media),
        // 原图按自己的比例整张放进来，空出来的地方就是黑边。
        fit: BoxFit.contain,
        backgroundColor: Colors.black,
        heroTag: 'feed_${media.id}',
        onTap: () => widget.onOpen(medias, i),
        onMotionLongPress: () => widget.onOpen(medias, i),
      );
    }

    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: widget.width,
        height: stageHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (medias.length == 1)
              page(0)
            else
              PageView.builder(
                itemCount: medias.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, i) => page(i),
              ),
            if (medias.length > 1)
              Positioned(
                top: 8,
                right: 8,
                child: PostMediaCounter(
                  key: postMediaCounterKey,
                  index: index,
                  count: medias.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 九宫格（默认）：2/4 张两列，其余三列，格子都是正方形。
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
    // 九宫格 ↔ 大屏是全局设置（在「我的」里），这里只跟着听：切回来立刻生效，
    // 不用重进页面。
    return ValueListenableBuilder<bool>(
      valueListenable: FeedViewSettings.widescreen,
      builder: (context, widescreen, _) {
        final wide = widescreen && widget.post.medias.isNotEmpty;
        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: _collapsed
              ? const SizedBox(width: double.infinity)
              : wide
                  ? _buildWidePost()
                  : _buildCardPost(),
        );
      },
    );
  }

  bool get _hasCaption => (widget.post.content ?? '').trim().isNotEmpty;

  Widget _buildCaption() => Text(widget.post.content!, style: AppText.body);

  /// 大屏：**不套卡片**。照片铺满屏宽、没有圆角和描边，头图上面是作者那一行，
  /// 说明文字压在照片下面——页面背景就是它的底。
  Widget _buildWidePost() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: _buildHeader(),
        ),
        LayoutBuilder(
          builder: (context, constraints) => _buildMediaBlock(
            constraints.maxWidth,
            widescreen: true,
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

  /// 九宫格：默认的卡片。玻璃只铺在卡片本体上，列表/页面的背景保持不变。
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

  /// 媒体区：大屏时是满屏轮播（原图 + 高度上限），九宫格时是三列格子。
  ///
  /// iPad 上单条动态很宽时限制在 640 以内，避免一张图占满整块横屏。
  Widget _buildMediaBlock(double available, {bool widescreen = false}) {
    final width = available > 640 ? 640.0 : available;
    final medias = widget.post.medias;
    if (!widescreen) {
      return _PostMediaGrid(
        medias: medias,
        onOpen: widget.onOpenMedia,
        width: width,
      );
    }
    return _PostMediaCarousel(
      medias: medias,
      onOpen: widget.onOpenMedia,
      width: width,
      maxHeight: MediaQuery.sizeOf(context).height * kFeedWideMaxHeightFactor,
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
