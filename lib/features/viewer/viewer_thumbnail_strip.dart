import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/media_cache.dart';
import '../../core/url_utils.dart';
import '../../models/media.dart';

/// 全屏浏览底部的缩略图条：打开或切换图片时自动把当前项滚到中间。
class ViewerThumbnailStrip extends StatefulWidget {
  final List<Media> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  const ViewerThumbnailStrip({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
  });

  @override
  State<ViewerThumbnailStrip> createState() => _ViewerThumbnailStripState();
}

const double thumbnailItemSize = 36;
const double thumbnailItemGap = 8;
const double thumbnailStripPadding = 16;

/// 缩略图条自身的上下内边距与总高度：视频控制条靠它们算「缩略图到进度条」的间距。
const double thumbnailStripVerticalPadding = 8;
const double thumbnailStripHeight = 52;

/// 计算把第 [index] 个缩略图滚到中间需要的偏移；已经完整可见时返回 null。
@visibleForTesting
double? thumbnailScrollTarget({
  required int index,
  required double currentOffset,
  required double viewportWidth,
  required double maxScrollExtent,
}) {
  final start =
      thumbnailStripPadding + index * (thumbnailItemSize + thumbnailItemGap);
  final end = start + thumbnailItemSize;
  if (start >= currentOffset && end <= currentOffset + viewportWidth) {
    return null;
  }
  final target = (start + thumbnailItemSize / 2 - viewportWidth / 2)
      .clamp(0.0, maxScrollExtent < 0 ? 0.0 : maxScrollExtent);
  if ((target - currentOffset).abs() < 0.5) return null;
  return target;
}

class _ViewerThumbnailStripState extends State<ViewerThumbnailStrip> {
  static const double _itemSize = thumbnailItemSize;
  static const double _gap = thumbnailItemGap;
  static const double _horizontalPadding = thumbnailStripPadding;

  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureCurrentVisible(animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant ViewerThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureCurrentVisible(animate: true);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 当前缩略图不在可视区域时，滚动到中间；已经完整可见就不动，
  /// 避免用户点选可见缩略图时列表来回跳。
  void _ensureCurrentVisible({required bool animate}) {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions || position.viewportDimension <= 0) {
      return;
    }
    final target = thumbnailScrollTarget(
      index: widget.currentIndex,
      currentOffset: position.pixels,
      viewportWidth: position.viewportDimension,
      maxScrollExtent: position.maxScrollExtent,
    );
    if (target == null) return;
    if (animate) {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thumbnailStripHeight,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: _horizontalPadding,
          vertical: thumbnailStripVerticalPadding,
        ),
        itemCount: widget.items.length,
        separatorBuilder: (_, __) => const SizedBox(width: _gap),
        itemBuilder: (context, index) {
          final media = widget.items[index];
          final current = index == widget.currentIndex;
          final path = media.thumbUrl ?? media.url;
          return GestureDetector(
            onTap: () => widget.onSelected(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: _itemSize,
              height: _itemSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: current ? Colors.white : Colors.white24,
                  width: current ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm - 1),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      cacheManager: MediaCache.manager,
                      imageUrl: fullUrl(path),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.mediaPlaceholder,
                        child: Icon(Icons.image_outlined,
                            size: 14, color: AppColors.textTertiary),
                      ),
                    ),
                    if (media.isVideo || media.isLivePhoto)
                      Container(
                        color: Colors.black26,
                        child: Icon(
                          media.isLivePhoto
                              ? Icons.motion_photos_on_outlined
                              : Icons.play_arrow_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
