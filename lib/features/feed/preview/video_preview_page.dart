import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../core/design/colors.dart';
import '../../../core/design/text_styles.dart';
import '../../../core/video_orientation.dart';

class VideoPreviewPage extends StatefulWidget {
  final String path;

  const VideoPreviewPage({super.key, required this.path});

  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;
  String? _error;
  bool _chromeVisible = false;
  Offset? _pointerDown;

  @override
  void initState() {
    super.initState();
    unawaited(allowVideoRotation());
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final video = VideoPlayerController.file(File(widget.path));
      _videoController = video;
      await video.initialize();
      if (!mounted) return;
      final chewie = ChewieController(
        videoPlayerController: video,
        aspectRatio: correctedVideoAspectRatio(video.value),
        autoPlay: true,
        looping: false,
        allowFullScreen: false,
        allowMuting: false,
        showControlsOnInitialize: false,
        hideControlsTimer: const Duration(seconds: 3),
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.textInverse,
          bufferedColor: AppColors.textInverse.withOpacity(0.3),
          backgroundColor: AppColors.textInverse.withOpacity(0.24),
        ),
      );
      _chewieController = chewie;
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      unawaited(lockAppPortrait());
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '视频加载失败';
      });
    }
  }

  Future<void> _retry() async {
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _initialize();
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    unawaited(lockAppPortrait());
    super.dispose();
  }

  Future<void> _toggleVideoOrientation() async {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    await SystemChrome.setPreferredOrientations(
      landscape
          ? const [DeviceOrientation.portraitUp]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _pointerDown = event.position,
      onPointerUp: (event) {
        final down = _pointerDown;
        _pointerDown = null;
        if (down == null || (event.position - down).distance >= 12) return;
        // 头部按钮区域不要触发隐藏；否则点“旋转/关闭”会误隐藏。
        if (_chromeVisible && event.position.dy < 130) return;
        setState(() => _chromeVisible = !_chromeVisible);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.textPrimary,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_loading)
                Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textTertiary,
                    ),
                  ),
                )
              else if (_error != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_disabled_outlined,
                        size: 42,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: AppText.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _retry,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              else if (_chewieController != null)
                Center(
                  child: Chewie(controller: _chewieController!),
                ),
              if (_chromeVisible)
                Positioned(
                  top: 44,
                  left: 8,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        iconSize: 24,
                        color: AppColors.textInverse,
                        tooltip: '关闭',
                      ),
                      IconButton(
                        onPressed: _toggleVideoOrientation,
                        iconSize: 24,
                        color: AppColors.textInverse,
                        tooltip: MediaQuery.orientationOf(context) ==
                                Orientation.landscape
                            ? '竖屏播放'
                            : '横屏播放',
                        icon: Icon(
                          MediaQuery.orientationOf(context) ==
                                  Orientation.landscape
                              ? Icons.stay_current_portrait
                              : Icons.screen_rotation,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
