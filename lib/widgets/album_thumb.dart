import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
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

  /// 指定要显示的图片地址，覆盖默认的 [Media.previewPath]。
  ///
  /// 朋友圈大屏模式用它直接指到 `/files/display/<文件名>` 的原图：默认走的是
  /// 服务端 400px 缩略图，放大到屏宽就是糊的。为 null 时仍按缩略图那条老路。
  final String? imagePath;

  /// 指了 [imagePath] 时，即便服务端缩略图生成失败也照样显示这张图。
  bool get _usesOwnPath => imagePath != null;

  /// 图片没铺满时露出来的底色。默认是统一的占位灰；朋友圈大屏要黑边，
  /// 就传黑色。
  final Color? backgroundColor;

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
    this.imagePath,
    this.backgroundColor,
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
    final background = backgroundColor ?? AppColors.mediaPlaceholder;
    // 本地文件（隐藏空间）：直接读文件，不经过服务器；角标照旧。
    final localPath = media.localPath;
    final Widget image;
    if (localPath != null && localPath.isNotEmpty) {
      // 本地媒体绝不能把「原文件」交给 Image.file：
      // - 图片原图可能是数十 MP/HEIC，引擎全尺寸解码会 OOM 后 abort；
      // - 视频原文件根本不是图片，ImageDecoder 按容器尺寸申请巨型 Bitmap 同样 abort。
      // 所以：图片只认 JPEG 预览，视频只认抽帧封面；没有就先显示占位。
      final displayPath =
          media.isVideo ? media.localThumbPath : media.localPreviewPath;
      if (displayPath == null || displayPath.isEmpty) {
        return _placeholder(showPlay: media.isVideo);
      }
      image = Image.file(
        File(displayPath),
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (_, __, ___) => _placeholder(showPlay: media.isVideo),
      );
    } else {
      final path = imagePath ?? media.previewPath;
      if ((!_usesOwnPath && media.thumbFailed) ||
          path == null ||
          path.isEmpty) {
        return _placeholder(showPlay: media.isVideo);
      }
      image = CachedNetworkImage(
        cacheManager: MediaCache.manager,
        imageUrl: fullUrl(path),
        fit: fit,
        memCacheWidth: cacheWidth,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (context, url) => Container(color: background),
        errorWidget: (context, url, error) => _placeholder(showPlay: false),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: background),
        image,
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
      color: backgroundColor ?? AppColors.mediaPlaceholder,
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
        color: Colors.black.withValues(alpha: 0.45),
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

// ---------------------------------------------------------------------------
// 网格拖拽连选
// ---------------------------------------------------------------------------

/// 网格里「按住一格横向划过一串格子」的连选手势，相册详情页与朋友圈相册共用。
///
/// 为什么用 [Listener] 而不是 GestureDetector：长按进入多选的那一下，手势竞技场
/// 已经判给长按（滚动和单击都出局了），这时再补一个 onHorizontalDrag 识别器根本
/// 接不到这根手指。Listener 只是旁观指针事件、不参与竞技场，于是「长按之后不
/// 松手继续拖」这条路径才成立；单击、长按、竖向滚动的判定一点不改。
///
/// 用法：把 Listener 常挂在列表外面（多选态和非多选态都挂着——按下那一刻不在
/// 命中路径里的 Listener 收不到后续的 move），长按进入多选时再调一次
/// [startFromLongPress]，把「还按着的这根手指」接到同一轮拖拽上。
class AlbumGridDragSelect {
  AlbumGridDragSelect({
    required this.isEnabled,
    required this.hitTest,
    required this.isSelected,
    required this.onChanged,
  });

  /// 只在多选态生效。
  final bool Function() isEnabled;

  /// 屏幕坐标 → 格子里的媒体 id；落在行距、吸顶条、页面留白上时给 null。
  final int? Function(Offset globalPosition) hitTest;

  final bool Function(int mediaId) isSelected;

  /// 一次移动覆盖到的格子；select 为 false 表示反向的「取消选择」。
  final void Function(Set<int> mediaIds, bool select) onChanged;

  /// 起手要横向离开按下点这么远才算出拖拽（= kTouchSlop）：小于它的是单击，
  /// 交给格子自己的 onTap。阈值取 kTouchSlop 而不是更小的数，是为了让「已经
  /// 变成拖拽」和「onTap 已经被取消」这两件事同时发生，一次点按不会被翻两次。
  static const double startSlop = kTouchSlop;

  /// 竖向位移超过这个值就认定用户在滚列表：本次手势整体放弃，滚动照常。
  ///
  /// 长按起手的那一轮例外，见 [_armedByLongPress]。
  static const double verticalSlop = 24;

  /// 两次 move 之间按这个步长补采样：手快时一帧能横跨两三格。
  static const double _sampleStep = 12;

  int? _pointer;
  Offset? _down;
  Offset? _last;
  bool? _value;
  bool _abandoned = false;

  /// 这一轮是长按接过来的：长按已经赢了手势竞技场，列表这一轮根本不会滚，
  /// 所以竖向阈值对它没有意义。反而必须放行——多选态页头会收成一条工具栏，
  /// 格子整体往上挪一截，手指底下可能换了行甚至落在日期头上；这时用户斜着
  /// 挪回一行继续拖是正常的，按阈值掐掉就成了「长按之后拖不动」。
  bool _armedByLongPress = false;
  final Set<int> _applied = {};

  void onPointerDown(PointerDownEvent event) {
    // 只跟第一根手指：拖拽中途再来一根，起点不该被挪走。
    if (_pointer != null) return;
    _pointer = event.pointer;
    _down = event.position;
    _last = event.position;
    _value = null;
    _abandoned = false;
    _armedByLongPress = false;
    _applied.clear();
  }

  /// 长按之后手指还按着：把这次手势接到同一轮拖拽上，方向就此定死。
  ///
  /// 方向 = 长按这一下把这一格变成了什么状态。进入多选时它刚被选上，接着拖
  /// 就是「连续选中」；多选态长按把一格取消掉，接着拖就是「连续取消」。
  /// 不能留到第一次 move 再按「从已选中项起手」反推：长按刚选上的那一格会被
  /// 反推成「取消」，正好和用户的意思相反。
  void startFromLongPress(int mediaId) {
    if (_pointer == null) return;
    _value = isSelected(mediaId);
    _abandoned = false;
    _armedByLongPress = true;
    _applied
      ..clear()
      ..add(mediaId);
  }

  void onPointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer || _abandoned) return;
    final down = _down;
    if (down == null) return;
    final position = event.position;
    // 竖向先动起来 = 用户在滚列表（或者是想滚，只是手抖）：本次不再选任何东西。
    // 长按接过来的这一轮不算：那一轮列表不会滚，见 [_armedByLongPress]。
    if (!_armedByLongPress && (position.dy - down.dy).abs() > verticalSlop) {
      _abandoned = true;
      _value = null;
      return;
    }
    if (_value == null) {
      // 还没激活：先要横着离开按下点，才可能是「划过一串格子」而不是点击，
      // 更不能是竖向滚动（斜着的头几像素先一步翻掉一格最气人）。
      final delta = position - down;
      if (delta.dx.abs() < startSlop || delta.dx.abs() <= delta.dy.abs()) {
        return;
      }
      if (!isEnabled()) {
        _abandoned = true;
        return;
      }
      final startId = hitTest(down);
      if (startId == null) {
        _abandoned = true;
        return;
      }
      // 从没选中的格子起手 = 连续选中；从已选中的格子起手 = 连续取消。
      _value = !isSelected(startId);
      _applied.clear();
      _applyAlong(down, position);
      _last = position;
      return;
    }
    _applyAlong(_last ?? position, position);
    _last = position;
  }

  void onPointerUp(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    reset();
  }

  void onPointerCancel(PointerCancelEvent event) {
    if (_pointer != event.pointer) return;
    reset();
  }

  /// 松手（或手势被抢）：这一轮结束，下一次按下重新判断方向。
  void reset() {
    _pointer = null;
    _down = null;
    _last = null;
    _value = null;
    _abandoned = false;
    _armedByLongPress = false;
    _applied.clear();
  }

  /// 沿 from → to 补采样命中，把还没翻过的格子交出去。
  ///
  /// 手指一次 move 可能跨过两三格，只测终点会漏掉中间那些——「划过的格子都被
  /// 选中」正是这个功能本身，所以中间点一个个测。
  void _applyAlong(Offset from, Offset to) {
    final value = _value;
    if (value == null) return;
    final steps = math.max(1, ((to - from).distance / _sampleStep).ceil());
    final fresh = <int>{};
    for (var i = 0; i <= steps; i++) {
      final id = hitTest(Offset.lerp(from, to, i / steps)!);
      if (id != null && _applied.add(id)) fresh.add(id);
    }
    if (fresh.isNotEmpty) onChanged(fresh, value);
  }
}
