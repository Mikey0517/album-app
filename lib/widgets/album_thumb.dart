import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/radius.dart';
import '../core/design/text_styles.dart';
import '../core/formatters.dart';
import '../core/media_cache.dart';
import '../core/url_utils.dart';
import '../models/media.dart';

/// 网格缩略图。cacheWidth 按实际显示像素解码，避免大图占满内存。
class AlbumThumb extends StatelessWidget {
  final Media media;
  final double radius;
  final int cacheWidth;
  final bool showVideoBadge;
  final String? heroTag;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMotionLongPress;
  final BoxFit fit;

  const AlbumThumb({
    super.key,
    required this.media,
    this.radius = 8,
    this.cacheWidth = 400,
    this.showVideoBadge = true,
    this.heroTag,
    this.onTap,
    this.onLongPress,
    this.onMotionLongPress,
    this.fit = BoxFit.cover,
  });

  /// 动态角标只认服务端提取出来的动态视频，避免「列表显示动态、点进去却没有」。
  bool get _isMotion => media.isLivePhoto;

  @override
  Widget build(BuildContext context) {
    Widget image = _buildImage(context);
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: image,
    );
    Widget content = clipped;
    if (heroTag != null) {
      content = Hero(
        tag: heroTag!,
        child: Material(color: Colors.transparent, child: content),
      );
    }
    final resolveLongPress =
        _isMotion ? (onMotionLongPress ?? onLongPress) : onLongPress;
    if (onTap != null || onLongPress != null || onMotionLongPress != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: resolveLongPress,
        child: content,
      );
    }
    return content;
  }

  Widget _buildImage(BuildContext context) {
    final path = media.previewPath;
    if (media.thumbFailed || path == null || path.isEmpty) {
      return _placeholder(showPlay: media.isVideo);
    }
    final url = fullUrl(path);
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.mediaPlaceholder),
        CachedNetworkImage(
          cacheManager: MediaCache.manager,
          imageUrl: url,
          fit: fit,
          memCacheWidth: cacheWidth,
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (context, url) => Container(
            color: AppColors.mediaPlaceholder,
          ),
          errorWidget: (context, url, error) => _placeholder(showPlay: false),
        ),
        if (media.isVideo && showVideoBadge)
          Positioned(
            left: 4,
            bottom: 4,
            child: _MediaBadge(
              icon: Icons.play_arrow_rounded,
              label: formatDuration(media.durationMs),
            ),
          ),
        if (!media.isVideo && _isMotion)
          const Positioned(
            left: 4,
            bottom: 4,
            child: _MediaBadge(
              icon: Icons.motion_photos_on_outlined,
              label: '动态',
            ),
          ),
      ],
    );
  }

  Widget _placeholder({required bool showPlay}) {
    return Container(
      color: AppColors.mediaPlaceholder,
      alignment: Alignment.center,
      child: Icon(
        showPlay ? Icons.play_circle_outline : Icons.photo_outlined,
        size: 28,
        color: AppColors.textTertiary,
      ),
    );
  }
}

class _MediaBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MediaBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            label,
            style: AppText.caption.copyWith(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
