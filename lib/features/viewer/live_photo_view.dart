import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/url_utils.dart';
import '../../core/video_orientation.dart';
import '../../models/media.dart';
import '../../core/media_cache.dart';
import 'zoomable_photo.dart';

/// 只有 WiFi/有线才自动播放动态照片；移动流量下保持静态图，点一下才播。
@visibleForTesting
bool shouldAutoPlayMotionPhoto(List<ConnectivityResult> results) {
  return results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet);
}

/// 动态照片：静态图 + 内嵌 MP4。点击播放/停止，播完自动回静态图。
class LivePhotoView extends StatefulWidget {
  final Media media;
  final bool active;
  final String heroTag;
  final ValueChanged<bool> onPlayingChanged;
  final ValueChanged<bool>? onZoomChanged;

  const LivePhotoView({
    super.key,
    required this.media,
    required this.active,
    required this.heroTag,
    required this.onPlayingChanged,
    this.onZoomChanged,
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

  bool get _canPlay =>
      widget.media.liveVideoUrl != null &&
      widget.media.liveVideoUrl!.trim().isNotEmpty;

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
    _initializing = true;
    try {
      final url = fullUrl(widget.media.liveVideoUrl!);
      debugPrint('动态视频 URL: $url');
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
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
      _initializing = false;
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

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final showVideo = _playing && video != null && video.value.isInitialized;
    return ZoomablePhoto(
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
              child: CachedNetworkImage(
                cacheManager: MediaCache.manager,
                imageUrl: fullUrl(_stillPath),
                fit: BoxFit.contain,
                fadeInDuration: const Duration(milliseconds: 180),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      size: 48, color: Colors.white38),
                ),
              ),
            ),
          ),
          if (showVideo)
            Center(
              child: AspectRatio(
                aspectRatio: correctedVideoAspectRatio(video.value),
                child: VideoPlayer(video),
              ),
            ),
          if (_initializing)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
