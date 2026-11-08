import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/media_cache.dart';
import '../../core/url_utils.dart';
import '../../models/media.dart';
import 'zoomable_photo.dart';

/// 全屏图片：支持双指缩放、双击放大、未放大时下滑关闭。
class ImageView extends StatefulWidget {
  final Media media;
  final String heroTag;
  final VoidCallback onTap;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onPinchClose;
  final ValueChanged<bool>? onZoomChanged;
  final VoidCallback? onDragCancel;

  const ImageView({
    super.key,
    required this.media,
    required this.heroTag,
    required this.onTap,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onPinchClose,
    this.onZoomChanged,
    this.onDragCancel,
  });

  @override
  State<ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<ImageView> {
  /// 走服务端的大图预览：HEIC 会被转成 JPEG，超大原图会缩到 2560px。
  String get _stillPath => displayUrl(widget.media.url);

  @override
  Widget build(BuildContext context) {
    final url = fullUrl(_stillPath);
    return ZoomablePhoto(
      onTap: widget.onTap,
      onZoomChanged: widget.onZoomChanged,
      onDragUpdate: widget.onDragUpdate,
      onDragEnd: widget.onDragEnd,
      onDragCancel: widget.onDragCancel,
      child: SizedBox.expand(
        child: Center(
          child: Hero(
            tag: widget.heroTag,
            child: Material(
              color: Colors.transparent,
              child: CachedNetworkImage(
                cacheManager: MediaCache.manager,
                imageUrl: url,
                fit: BoxFit.contain,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (_, __) => const SizedBox.expand(
                  child: ColoredBox(color: Colors.black),
                ),
                errorWidget: (_, __, ___) {
                  final thumb = widget.media.thumbUrl;
                  if (thumb != null &&
                      thumb.isNotEmpty &&
                      thumb != _stillPath) {
                    return CachedNetworkImage(
                      cacheManager: MediaCache.manager,
                      imageUrl: fullUrl(thumb),
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            size: 48, color: Colors.white38),
                      ),
                    );
                  }
                  return const Center(
                    child: Icon(Icons.broken_image_outlined,
                        size: 48, color: Colors.white38),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
