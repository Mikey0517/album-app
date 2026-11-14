import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';
import 'viewer_thumbnail_strip.dart';

// ---------------------------------------------------------------------------
// 控制条的版式常量与几何：缩略图条靠同一份数字定位，改版式时不会只改一半。
// ---------------------------------------------------------------------------

/// 竖屏（原版式）：一行 54 高，上方留 18 给渐变过渡，下方 4 贴安全区。
const double viewerControlsHeightPortrait = 54;
const double viewerControlsTopPaddingPortrait = 18;
const double viewerControlsBottomPaddingPortrait = 4;

/// 横屏：屏幕矮、左右还有刘海/圆角，竖向留白收到 8，横向交给 SafeArea。
/// 行高 44 而不是 54——横屏竖向预算是全屏高度的零头，控制条不该占掉一成。
const double viewerControlsHeightLandscape = 44;
const double viewerControlsPaddingLandscape = 8;
const double viewerControlsHorizontalPaddingLandscape = 16;

/// 播放/进度那一行：缩略图条靠它定位，测试也直接量它。
const Key viewerControlsRowKey = ValueKey<String>('viewer-controls-row');

/// 缩略图条与进度条之间的视觉间距。
/// 横屏竖向紧，贴到 8；竖屏留 10，分得开又不显得被拆散。
const double viewerThumbnailGapLandscape = 8;
const double viewerThumbnailGapPortrait = 10;

/// 控制条占的高度（不含屏幕底部安全区）。
double viewerControlsExtent({required bool landscape}) => landscape
    ? viewerControlsHeightLandscape + viewerControlsPaddingLandscape * 2
    : viewerControlsHeightPortrait +
        viewerControlsTopPaddingPortrait +
        viewerControlsBottomPaddingPortrait;

/// 播放/进度那一行的顶边到屏幕底边的距离（含底部安全区）。
double viewerControlsRowTop({
  required bool landscape,
  required double bottomInset,
}) {
  return bottomInset +
      (landscape
          ? viewerControlsPaddingLandscape + viewerControlsHeightLandscape
          : viewerControlsBottomPaddingPortrait +
              viewerControlsHeightPortrait);
}

/// 缩略图条 `Positioned.bottom` 的取值。
///
/// 减去缩略图条自身的上下内边距，让图片下沿（而不是整条盒子的下沿）
/// 与进度条保持 [viewerThumbnailGapLandscape] / [viewerThumbnailGapPortrait]。
double viewerThumbnailStripBottom({
  required bool landscape,
  required double bottomInset,
}) {
  final gap = landscape
      ? viewerThumbnailGapLandscape
      : viewerThumbnailGapPortrait;
  return viewerControlsRowTop(landscape: landscape, bottomInset: bottomInset) +
      gap -
      thumbnailStripVerticalPadding;
}

/// 视频播放控制条：播放/暂停、进度、时间、全屏旋转。
///
/// 横屏与竖屏是两套版式：竖屏沿用窄布局，横屏进度条横向铺满、
/// 左右留白吃 SafeArea（刘海不切按钮）、上下只留 8。
class ViewerVideoControls extends StatelessWidget {
  final VideoPlayerController controller;
  final VoidCallback onInteraction;
  final VoidCallback? onToggleRotation;

  const ViewerVideoControls({
    super.key,
    required this.controller,
    required this.onInteraction,
    this.onToggleRotation,
  });

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    return ViewerVideoControlsLayout(
      position: value.position,
      duration: value.duration,
      isPlaying: value.isPlaying,
      onPlayPause: () {
        onInteraction();
        if (value.isPlaying) {
          controller.pause();
        } else {
          if (value.isCompleted) {
            controller.seekTo(Duration.zero);
          }
          controller.play();
        }
      },
      onSeek: (position) {
        onInteraction();
        controller.seekTo(position);
      },
      onSeekStart: onInteraction,
      onToggleRotation: onToggleRotation == null
          ? null
          : () {
              onInteraction();
              onToggleRotation!();
            },
    );
  }
}

/// 控制条的版式本身：只吃数值和回调，不依赖 video_player，
/// 这样横屏/竖屏两套版式可以直接按屏幕尺寸测。
class ViewerVideoControlsLayout extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onSeekStart;
  final VoidCallback? onToggleRotation;

  const ViewerVideoControlsLayout({
    super.key,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSeek,
    this.onSeekStart,
    this.onToggleRotation,
  });

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final total = duration.isNegative ? Duration.zero : duration;
    final shown = position > total ? total : position;
    final max = total.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final progress = shown.inMilliseconds.toDouble().clamp(0.0, max);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      padding: landscape
          ? const EdgeInsets.symmetric(
              horizontal: viewerControlsHorizontalPaddingLandscape,
              vertical: viewerControlsPaddingLandscape,
            )
          : const EdgeInsets.fromLTRB(
              8,
              viewerControlsTopPaddingPortrait,
              12,
              viewerControlsBottomPaddingPortrait,
            ),
      child: SafeArea(
        top: false,
        // 横屏左右可能被刘海/圆角压住，竖屏不需要横向内缩。
        left: landscape,
        right: landscape,
        child: SizedBox(
          key: viewerControlsRowKey,
          height: landscape
              ? viewerControlsHeightLandscape
              : viewerControlsHeightPortrait,
          child: Row(
            children: [
              IconButton(
                onPressed: onPlayPause,
                color: Colors.white,
                iconSize: landscape ? 24 : 28,
                padding: landscape ? EdgeInsets.zero : null,
                constraints: landscape
                    ? const BoxConstraints(minWidth: 40, minHeight: 40)
                    : null,
                visualDensity: landscape ? VisualDensity.compact : null,
                tooltip: isPlaying ? '暂停' : '播放',
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              if (landscape) const SizedBox(width: 4),
              Text(
                formatDuration(shown.inMilliseconds),
                style: AppText.caption.copyWith(
                  color: Colors.white,
                  fontSize: landscape ? 12 : 11,
                ),
              ),
              if (landscape) const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: landscape ? 4 : 3,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: landscape ? 7 : 6,
                    ),
                    overlayShape: RoundSliderOverlayShape(
                      overlayRadius: landscape ? 16 : 14,
                    ),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: progress,
                    max: max,
                    onChanged: (v) =>
                        onSeek(Duration(milliseconds: v.round())),
                    onChangeStart: (_) => onSeekStart?.call(),
                  ),
                ),
              ),
              if (landscape) const SizedBox(width: 8),
              Text(
                formatDuration(total.inMilliseconds),
                style: AppText.caption.copyWith(
                  color: Colors.white70,
                  fontSize: landscape ? 12 : 11,
                ),
              ),
              if (onToggleRotation != null)
                IconButton(
                  onPressed: onToggleRotation,
                  color: Colors.white,
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.only(left: landscape ? 0 : 6),
                  constraints: BoxConstraints(
                    minWidth: landscape ? 40 : 32,
                    minHeight: landscape ? 40 : 32,
                  ),
                  tooltip: '旋转屏幕',
                  icon: const Icon(Icons.screen_rotation_alt),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
