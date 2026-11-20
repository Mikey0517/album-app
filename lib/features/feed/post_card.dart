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

/// 大图模式的页高：宽度铺满，高度按图片自身比例，但收在 4:5 ~ 1.91:1 之间
/// （和 Instagram 同一档）。收窄下界是为了长截图不把一屏占满，收窄上界是为了
/// 全景图不把卡片撑成一条线；比例拿不到时按 1:1 处理。
double feedMediaAspectRatio(Media media) {
  final width = media.width ?? 0;
  final height = media.height ?? 0;
  if (width <= 0 || height <= 0) return 1;
  return (width / height).clamp(4 / 5, 1.91).toDouble();
}

/// 一条动态的大图轮播：一次一张、左右滑动切换，右上角是「第几张/共几张」。
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
    final cacheWidth =
        (widget.width * MediaQuery.of(context).devicePixelRatio).round();

    Widget page(int i, {required double radius}) {
      final media = medias[i];
      return AlbumThumb(
        media: media,
        radius: radius,
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
        child: page(0, radius: AppRadius.md),
      );
    }

    return SizedBox(
      width: widget.width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: PageView.builder(
              itemCount: medias.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, i) => page(i, radius: 0),
            ),
          ),
          // 切换指示放右上角：底部留给文字，左右留给手势。
          Positioned(
            top: 10,
            right: 10,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${index + 1}/${medias.length}',
                  style: AppText.caption.copyWith(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ),
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
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: _collapsed
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              // 玻璃只铺在卡片本体上：列表/页面的背景保持不变。
              // 档位固定用 [AppGlassSurface.kCardQuality]，现在是 standard：
              // 纯 BackdropFilter，**不抓 capture**。这不是性能取舍，是黑卡的
              // 修法——premium 的 capture 在列表重建/刷新那一帧还没就绪，会画
              // 出一块近黑（见 kCardQuality 的注释与
              // test/feed_refresh_glass_test.dart）。折射留给底部胶囊那种静态
              // chrome；卡片仍不自建层（useOwnLayer 默认 false），内容有
              // RepaintBoundary 兜着，滚动时不会每帧重建。
              // 降到 minimal / 玻璃不可用时就是不透明的 bgSurface，布局完全一致。
              // depth：双层阴影 + 顶部内高光 + 1px 描边，磨砂档与退化档一样有
              // 层次（只是退化档没有模糊），卡片本身不做位移动画。
              child: AppGlassSurface(
                radius: AppRadius.lg,
                padding: const EdgeInsets.all(16),
                requestedQuality: AppGlassSurface.kCardQuality,
                depth: true,
                // 大图模式（Instagram 那样）：先图、后文字。一张图占满卡片宽度，
                // 多张左右滑动切换，右上角标页码；文字挪到图下面当说明。
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    if (widget.post.medias.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _buildMedia(),
                    ],
                    if ((widget.post.content ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        widget.post.content!,
                        style: AppText.body,
                      ),
                    ],
                  ],
                ),
              ),
            ),
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

  Widget _buildMedia() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // iPad 上单条动态很宽时限制在 640 宽以内，避免一张图占满整块横屏。
        final width = constraints.maxWidth > 640 ? 640.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.centerLeft,
          child: _PostMediaCarousel(
            medias: widget.post.medias,
            onOpen: widget.onOpenMedia,
            width: width,
          ),
        );
      },
    );
  }
}
