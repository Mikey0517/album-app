import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/motion_photo.dart';
import '../../core/url_utils.dart';
import '../../models/media.dart';
import '../../core/media_cache.dart';
import 'corrected_video_layer.dart';
import 'viewer_top_bar.dart';
import 'zoomable_photo.dart';

/// 只有 WiFi/有线才自动播放动态照片；移动流量下保持静态图，点一下才播。
@visibleForTesting
bool shouldAutoPlayMotionPhoto(List<ConnectivityResult> results) {
  return results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet);
}

/// 右下角播放按钮的恒定 key：播放状态一变整棵子树会重建，挂常量 key 让它
/// 始终命中同一个 Element（和 [viewerTopBarKey] 同一个理由）。
const Key livePhotoPlayButtonKey = ValueKey<String>('live-photo-play');

/// 动图播放按钮的直径与到右/下边缘的距离。
///
/// 和浏览页顶栏那排按钮（关闭 / 保存 / 详情）同一套语言，但再收一丢丢：
/// 图标 20（顶栏动作图标是 22），圆做成 36 的（那排只有图标没有圆底，这里
/// 保留圆底是为了浅色照片上也看得清）。
const double livePhotoPlayButtonSize = 36;
const double livePhotoPlayButtonInset = 16;

/// 按钮里的图标字号：比顶栏动作图标（[viewerActionIconSize]）小一档。
const double livePhotoPlayIconSize = viewerActionIconSize - 2;

/// 动态照片：静态图 + 内嵌 MP4。点击播放/停止，播完自动回静态图。
class LivePhotoView extends StatefulWidget {
  final Media media;
  final bool active;
  final String heroTag;
  final ValueChanged<bool> onPlayingChanged;
  final ValueChanged<bool>? onZoomChanged;

  /// 浏览页的控制层是否可见（点一下屏幕会整体隐藏）：播放按钮跟着一起隐，
  /// 不然「全屏看图」时右下角永远挂着一个圈。
  final bool uiVisible;

  /// 播放按钮下面还要让开的高度：底部有缩略图条时由浏览页传 [thumbnailStripHeight]，
  /// 按钮就浮到缩略图条上方，不会压住可以点的缩略图。
  final double bottomClearance;

  /// 仅测试用：注入替身控制器，让测试不必依赖真实平台通道就能看到
  /// 「正在播放」这一帧的画面。
  @visibleForTesting
  final VideoPlayerController Function(Uri url)? controllerFactory;

  const LivePhotoView({
    super.key,
    required this.media,
    required this.active,
    required this.heroTag,
    required this.onPlayingChanged,
    this.onZoomChanged,
    this.uiVisible = true,
    this.bottomClearance = 0,
    this.controllerFactory,
  });

  @override
  State<LivePhotoView> createState() => _LivePhotoViewState();
}

class _LivePhotoViewState extends State<LivePhotoView> {
  VideoPlayerController? _video;
  bool _initializing = false;
  bool _ready = false;
  bool _playing = false;
  bool _failed = false;
  bool _autoStarted = false;
  bool _resetting = false;

  bool get _canPlay => widget.media.isLocal
      ? widget.media.localMotion
      : (widget.media.liveVideoUrl != null &&
          widget.media.liveVideoUrl!.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_maybeAutoPlay());
  }

  @override
  void didUpdateWidget(covariant LivePhotoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (!widget.active) {
      unawaited(_stop());
    } else {
      unawaited(_maybeAutoPlay());
    }
  }

  Future<void> _maybeAutoPlay() async {
    if (_autoStarted || !widget.active || !_canPlay) return;
    _autoStarted = true;
    try {
      final results = await Connectivity().checkConnectivity();
      if (!shouldAutoPlayMotionPhoto(results)) return;
      if (mounted && widget.active) await _play();
    } catch (_) {
      // 无法判断网络时保持静态图，用户点一下仍可播放。
    }
  }

  Future<void> _ensureVideo() async {
    if (_video != null || _initializing || !_canPlay) return;
    // 按钮要立刻变成 loading：这一步不 setState 的话，用户点了播放只会看到
    // 按钮还是播放箭头，直到视频初始化完才有反馈。
    setState(() => _initializing = true);
    try {
      final localPath = widget.media.localPath;
      final VideoPlayerController controller;
      if (localPath != null && localPath.isNotEmpty) {
        // 本地动态照片：相册里那份内嵌 MP4 用 XMP 信息从文件尾部抽出来。
        final info = await motionPhotoInfoFile(localPath);
        if (info == null) throw StateError('不是动态照片');
        final videoPath = await extractMotionVideoFile(localPath, info);
        if (videoPath == null || videoPath.isEmpty) {
          throw StateError('提取动态视频失败');
        }
        controller = VideoPlayerController.file(
          File(videoPath),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } else {
        final url = fullUrl(widget.media.liveVideoUrl!);
        debugPrint('动态视频 URL: $url');
        final uri = Uri.parse(url);
        controller = widget.controllerFactory?.call(uri) ??
            VideoPlayerController.networkUrl(
              uri,
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );
      }
      _video = controller;
      await controller.initialize();
      // 动态照片要带声音播放（和系统相册一致）。
      await controller.setVolume(1);
      controller.addListener(_onVideoState);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      _video?.dispose();
      _video = null;
      if (mounted) {
        setState(() {
          _failed = true;
          _ready = false;
        });
      }
      widget.onPlayingChanged(false);
    } finally {
      if (mounted) {
        setState(() => _initializing = false);
      } else {
        _initializing = false;
      }
    }
  }

  Future<void> _play() async {
    if (!_canPlay || _failed) return;
    if (!_ready) await _ensureVideo();
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    await video.seekTo(Duration.zero);
    if (!mounted) return;
    setState(() => _playing = true);
    try {
      await video.play();
      widget.onPlayingChanged(true);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
      widget.onPlayingChanged(false);
    }
  }

  Future<void> _stop() async {
    final video = _video;
    if (video != null) {
      try {
        await video.pause();
        await video.seekTo(Duration.zero);
      } catch (_) {
        // ignore
      }
    }
    if (mounted && _playing) setState(() => _playing = false);
    if (_playing) widget.onPlayingChanged(false);
    _playing = false;
  }

  Future<void> _toggle() async {
    _autoStarted = true;
    if (_playing) {
      await _stop();
    } else if (_failed) {
      // 失败后仍允许重试一次。
      _failed = false;
      await _play();
    } else {
      await _play();
    }
  }

  void _onVideoState() {
    final video = _video;
    if (!mounted || _resetting || video == null || !video.value.isInitialized) {
      return;
    }
    if (!_playing || !video.value.isCompleted) return;
    _resetting = true;
    unawaited(() async {
      try {
        await video.pause();
        await video.seekTo(Duration.zero);
      } finally {
        _resetting = false;
        if (mounted) setState(() => _playing = false);
        widget.onPlayingChanged(false);
      }
    }());
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideoState);
    _video?.dispose();
    super.dispose();
  }

  String get _stillPath => displayUrl(widget.media.url);

  /// 静态图铺出来的那块矩形的比例。视频层拿它当框：动态照片播放时画面
  /// 必须在静态图的范围内居中，不能比静态图更大、更不能占满整屏。
  double? get _stillAspectRatio {
    final width = widget.media.width;
    final height = widget.media.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
  }

  /// 右下角那枚圆形按钮：一个圈 + 一个播放箭头（播放中换成暂停）。
  ///
  /// 放在 [ZoomablePhoto] **外面**：双指放大时按钮不能跟着一起放大、也不能飘走，
  /// 它得始终钉在屏幕右下角。点「播放」和点画面走的是同一个 [_toggle]，两处
  /// 入口不会各说各话。
  Widget _buildPlayButton(BuildContext context) {
    final bottom = livePhotoPlayButtonInset +
        widget.bottomClearance +
        MediaQuery.paddingOf(context).bottom;
    return Positioned(
      right: livePhotoPlayButtonInset,
      bottom: bottom,
      child: IgnorePointer(
        ignoring: !widget.uiVisible,
        child: AnimatedOpacity(
          opacity: widget.uiVisible ? 1 : 0,
          duration: Duration(milliseconds: widget.uiVisible ? 200 : 300),
          child: IconButton(
            key: livePhotoPlayButtonKey,
            onPressed: _toggle,
            tooltip: _playing ? '暂停动图' : '播放动图',
            iconSize: livePhotoPlayIconSize,
            // 用紧约束把按钮本体定死在直径上，不受 M3 最小尺寸影响。
            constraints: const BoxConstraints.tightFor(
              width: livePhotoPlayButtonSize,
              height: livePhotoPlayButtonSize,
            ),
            style: IconButton.styleFrom(
              // 默认 8 的内边距会把 22 的图标挤出 40 的圆，这里清掉，图标自己居中。
              padding: EdgeInsets.zero,
              // 命中区和圆一样大：配 48 的隐形命中区，圆心会从右下角往里漂，
              // 位置和视觉就对不上了。整张照片本身也能点着播。
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: Colors.black.withValues(alpha: 0.42),
              foregroundColor: Colors.white,
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1,
              ),
              shape: const CircleBorder(),
            ),
            // 正在拉视频：按钮自己变成 loading（不再只在画面中间转圈），
            // 用户点的那个位置就有反馈。
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _initializing
                  ? const SizedBox(
                      key: ValueKey<String>('live-photo-loading'),
                      width: livePhotoPlayIconSize * 0.7,
                      height: livePhotoPlayIconSize * 0.7,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey<bool>(_playing),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStill() {
    final localPath = widget.media.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      // HEIC/HEIF 没有 JPEG 预览时不交给 Image.file（引擎解码会 abort）。
      if (widget.media.localImageNeedsPreview &&
          (widget.media.localPreviewPath == null ||
              widget.media.localPreviewPath!.isEmpty)) {
        return const Center(
          child: Icon(Icons.image_outlined, size: 48, color: Colors.white38),
        );
      }
      return Image.file(
        File(widget.media.localPreviewPath ?? localPath),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined,
              size: 48, color: Colors.white38),
        ),
      );
    }
    return CachedNetworkImage(
      cacheManager: MediaCache.manager,
      imageUrl: fullUrl(_stillPath),
      fit: BoxFit.contain,
      fadeInDuration: const Duration(milliseconds: 180),
      errorWidget: (_, __, ___) => const Center(
        child:
            Icon(Icons.broken_image_outlined, size: 48, color: Colors.white38),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final showVideo = _playing && video != null && video.value.isInitialized;
    final photo = ZoomablePhoto(
      onTap: _toggle,
      // 动态照片用单击播放/暂停，双指缩放，双击缩放会和单击抢等待时间。
      enableDoubleTap: false,
      onZoomChanged: widget.onZoomChanged,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          Hero(
            tag: widget.heroTag,
            child: Material(
              color: Colors.transparent,
              child: _buildStill(),
            ),
          ),
          if (showVideo)
            // 两层各按自身比例居中：图片层 BoxFit.contain 铺出静态图那块矩形，
            // 视频层在同一块矩形里 contain（frameAspectRatio），所以视频既不会
            // 被拉伸，也不会比静态图大一圈去撑满屏幕。
            CorrectedVideoLayer(
              value: video.value,
              frameAspectRatio: _stillAspectRatio,
              child: VideoPlayer(video),
            ),
        ],
      ),
    );
    // 没有内嵌动态视频的普通照片不该出现播放按钮：点了也没东西可播。
    if (!_canPlay) return photo;
    return Stack(
      fit: StackFit.expand,
      children: [
        photo,
        _buildPlayButton(context),
      ],
    );
  }
}
