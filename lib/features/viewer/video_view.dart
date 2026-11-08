import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/design/text_styles.dart';
import '../../core/url_utils.dart';
import '../../models/media.dart';
import '../../core/video_orientation.dart';
import 'viewer_bottom_controls.dart';
import '../../core/media_cache.dart';

class VideoView extends StatefulWidget {
  final Media media;
  final bool active;
  final bool uiVisible;
  final String heroTag;
  final VoidCallback onToggleUi;
  final VoidCallback onUserInteraction;
  final ValueChanged<bool> onPlayingChanged;
  final VoidCallback? onToggleRotation;

  const VideoView({
    super.key,
    required this.media,
    required this.active,
    required this.uiVisible,
    required this.heroTag,
    required this.onToggleUi,
    required this.onUserInteraction,
    required this.onPlayingChanged,
    this.onToggleRotation,
  });

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  VideoPlayerController? _controller;
  Timer? _ticker;
  bool _loading = true;
  bool _error = false;
  bool _ended = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _controller != null) setState(() {});
    });
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(fullUrl(widget.media.url)),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = controller;
      await controller.initialize();
      controller.addListener(_onValueChanged);
      if (!mounted) return;
      setState(() => _loading = false);
      if (widget.active) {
        await controller.play();
        _notifyPlaying(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
      _notifyPlaying(false);
    }
  }

  void _onValueChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    final completed = value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying;
    if (completed && !_ended) {
      setState(() => _ended = true);
      _notifyPlaying(false);
    } else if (!completed && _ended) {
      setState(() => _ended = false);
    }
    if (value.isPlaying != _playing) {
      setState(() => _playing = value.isPlaying);
      _notifyPlaying(value.isPlaying);
    }
  }

  void _notifyPlaying(bool value) {
    if (_playing == value) return;
    _playing = value;
    widget.onPlayingChanged(value);
  }

  Future<void> _replay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.seekTo(Duration.zero);
    await controller.play();
    if (mounted) setState(() => _ended = false);
    _notifyPlaying(true);
  }

  @override
  void didUpdateWidget(covariant VideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!widget.active) {
      controller.pause();
      _notifyPlaying(false);
    } else if (!_ended) {
      controller.play();
      _notifyPlaying(true);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.removeListener(_onValueChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller != null && controller.value.isInitialized;
    final thumb = widget.media.thumbUrl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onToggleUi,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (thumb != null && thumb.isNotEmpty)
            IgnorePointer(
              child: Opacity(
                opacity: initialized ? 0 : 1,
                child: Hero(
                  tag: widget.heroTag,
                  child: CachedNetworkImage(
                    cacheManager: MediaCache.manager,
                    imageUrl: fullUrl(thumb),
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          if (initialized)
            Center(
              child: AspectRatio(
                aspectRatio: correctedVideoAspectRatio(controller.value),
                child: VideoPlayer(controller),
              ),
            ),
          if (_loading)
            const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            ),
          if (_error)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_disabled_outlined,
                      size: 44, color: Colors.white38),
                  const SizedBox(height: 10),
                  Text('视频加载失败',
                      style: AppText.bodySmall.copyWith(
                        color: Colors.white70,
                      )),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = false;
                      });
                      _controller?.dispose();
                      _controller = null;
                      _initialize();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (initialized && controller.value.isBuffering && !_error)
            const Positioned(
              top: 84,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          if (_ended && initialized)
            Center(
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    widget.onToggleUi();
                    _replay();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(18),
                    child: Icon(Icons.replay_rounded,
                        size: 32, color: Colors.white),
                  ),
                ),
              ),
            ),
          if (initialized && widget.uiVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: false,
                child: ViewerVideoControls(
                  controller: controller,
                  onInteraction: widget.onUserInteraction,
                  onToggleRotation: widget.onToggleRotation,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
