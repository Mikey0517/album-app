import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';

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
    final duration = value.duration;
    final position = value.position > duration ? duration : value.position;
    final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final progress = position.inMilliseconds.toDouble().clamp(0.0, max);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 18, 12, 4),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              IconButton(
                onPressed: () {
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
                color: Colors.white,
                iconSize: 28,
                tooltip: value.isPlaying ? '暂停' : '播放',
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              Text(
                formatDuration(position.inMilliseconds),
                style: AppText.caption.copyWith(
                  color: Colors.white,
                  fontSize: 11,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: progress,
                    max: max,
                    onChanged: (v) {
                      onInteraction();
                      controller.seekTo(
                        Duration(milliseconds: v.round()),
                      );
                    },
                    onChangeStart: (_) => onInteraction(),
                  ),
                ),
              ),
              Text(
                formatDuration(duration.inMilliseconds),
                style: AppText.caption.copyWith(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
              if (onToggleRotation != null)
                IconButton(
                  onPressed: () {
                    onInteraction();
                    onToggleRotation!();
                  },
                  color: Colors.white,
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.only(left: 6),
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
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
