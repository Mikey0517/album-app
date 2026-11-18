import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/design/text_styles.dart';
import '../../core/url_utils.dart';
import '../../models/media.dart';
import 'corrected_video_layer.dart';
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

  /// 仅测试用：注入替身控制器，让测试不必依赖真实平台通道就能摆出
  /// 缓冲中 / 播完 / 重播这几个状态。
  @visibleForTesting
  final VideoPlayerController Function(Uri url)? controllerFactory;

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
    this.controllerFactory,
  });

  @override
  State<VideoView> createState() => _VideoViewState();
}

/// 结束 → 重播之间的 seek 必然触发平台层的一次 bufferingStart→bufferingEnd
/// （见 video_player 的 completed 事件处理器：`pause().then(seekTo(duration))`）。
/// 那是本地跳转，不是等网络数据，窗口内一律不画转圈。
const Duration videoBufferingSuppressWindow = Duration(milliseconds: 400);

/// 顶部缓冲转圈该不该出现：只有「真的在等数据」时才出现。
///
/// - 播完（[VideoPlayerValue.isCompleted] 或本控件记下的 ended）停在最后一帧，
///   平台自己那次 seek 到 duration 的 buffering 不算等待；
/// - 重播 seek 的 [suppressed] 窗口内同样不算等待。
bool shouldShowVideoBuffering(
  VideoPlayerValue value, {
  required bool error,
  required bool ended,
  required bool suppressed,
}) {
  if (error || !value.isInitialized) return false;
  if (ended || value.isCompleted) return false;
  return value.isBuffering && !suppressed;
}

class _VideoViewState extends State<VideoView> {
  VideoPlayerController? _controller;
  Timer? _ticker;
  Timer? _bufferingSuppressTimer;
  bool _loading = true;
  bool _error = false;
  bool _ended = false;
  bool _playing = false;
  bool _buffering = false;
  bool _suppressBuffering = false;

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
      final uri = Uri.parse(fullUrl(widget.media.url));
      final controller = widget.controllerFactory?.call(uri) ??
          VideoPlayerController.networkUrl(
            uri,
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
    // 缓冲起止要立刻重画，不能等 250ms 的 ticker：那是"窗口内不许出现转圈"
    // 之所以会闪一下的另一半原因。
    if (value.isBuffering != _buffering) {
      setState(() => _buffering = value.isBuffering);
    }
  }

  void _notifyPlaying(bool value) {
    if (_playing == value) return;
    _playing = value;
    widget.onPlayingChanged(value);
  }

  /// 重播 / 从末尾拉起播放都要先 seek 回 0：窗口内屏蔽缓冲转圈。
  void _suppressBufferingForSeek() {
    _bufferingSuppressTimer?.cancel();
    if (!_suppressBuffering && mounted) {
      setState(() => _suppressBuffering = true);
    }
    _bufferingSuppressTimer = Timer(videoBufferingSuppressWindow, () {
      if (!mounted) return;
      setState(() => _suppressBuffering = false);
    });
  }

  Future<void> _replay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _suppressBufferingForSeek();
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
    _bufferingSuppressTimer?.cancel();
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
            CorrectedVideoLayer(
              value: controller.value,
              child: VideoPlayer(controller),
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
          if (initialized)
            Positioned(
              top: 84,
              left: 0,
              right: 0,
              child: VideoBufferingIndicator(
                value: controller.value,
                ended: _ended,
                suppressed: _suppressBuffering,
                error: _error,
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
                  onRestart: _suppressBufferingForSeek,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 顶部那枚缓冲转圈：真的在等数据时才出现，其余时候是零尺寸的占位。
///
/// 播完停在最后一帧、结束→重播的 seek 窗口里都不画（见
/// [shouldShowVideoBuffering]）。
class VideoBufferingIndicator extends StatelessWidget {
  const VideoBufferingIndicator({
    super.key,
    required this.value,
    required this.ended,
    required this.suppressed,
    this.error = false,
  });

  final VideoPlayerValue value;
  final bool ended;
  final bool suppressed;
  final bool error;

  @override
  Widget build(BuildContext context) {
    if (!shouldShowVideoBuffering(
      value,
      error: error,
      ended: ended,
      suppressed: suppressed,
    )) {
      return const SizedBox.shrink();
    }
    return const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white70,
        ),
      ),
    );
  }
}
