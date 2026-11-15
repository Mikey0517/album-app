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

class PostCard extends StatefulWidget {
  final Post post;
  final void Function(List<Media> medias, int index) onOpenMedia;
  final VoidCallback onDeleted;

  const PostCard({
    super.key,
    required this.post,
    required this.onOpenMedia,
    required this.onDeleted,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _collapsed = false;
  bool _deleting = false;

  bool get _isMine => widget.post.authorId == CurrentUser.notifier.value?.id;

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
              // 列表里每张卡片都要一块玻璃，所以显式要 standard 档（包的轻量
              // shader），并复用外层 backdrop；内容有 RepaintBoundary 兜着，
              // 滚动时不会每帧重建。降到 minimal / 玻璃不可用时就是不透明的
              // bgSurface，布局完全一致。
              child: AppGlassSurface(
                radius: AppRadius.lg,
                padding: const EdgeInsets.all(16),
                requestedQuality: GlassQuality.standard,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    if ((widget.post.content ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        widget.post.content!,
                        style: AppText.body,
                      ),
                    ],
                    if (widget.post.medias.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _buildMediaGrid(),
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
        if (_isMine) ...[
          const SizedBox(width: 2),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _confirmDelete();
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

  Widget _buildMediaGrid() {
    final medias = widget.post.medias;
    return LayoutBuilder(
      builder: (context, constraints) {
        // iPad 上单条动态很宽时，九宫格限制在 640 宽以内，避免格子过大。
        final maxWidth =
            constraints.maxWidth > 640 ? 640.0 : constraints.maxWidth;
        if (medias.length == 1) {
          final side = maxWidth < 200 ? maxWidth : 200.0;
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: side,
              height: side,
              child: AlbumThumb(
                media: medias.first,
                radius: AppRadius.md,
                cacheWidth:
                    (side * MediaQuery.of(context).devicePixelRatio).round(),
                heroTag: 'feed_${medias.first.id}',
                onTap: () => widget.onOpenMedia(medias, 0),
                onMotionLongPress: () => widget.onOpenMedia(medias, 0),
              ),
            ),
          );
        }

        final int columns;
        if (medias.length == 2 || medias.length == 4) {
          columns = 2;
        } else {
          columns = 3;
        }
        const gap = 4.0;
        final tile = (maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
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
                  cacheWidth:
                      (tile * MediaQuery.of(context).devicePixelRatio).round(),
                  heroTag: 'feed_${medias[i].id}',
                  onTap: () => widget.onOpenMedia(medias, i),
                  onMotionLongPress: () => widget.onOpenMedia(medias, i),
                ),
              ),
          ],
        );
      },
    );
  }
}
