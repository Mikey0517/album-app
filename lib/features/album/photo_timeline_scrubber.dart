import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/colors.dart';

/// 相册右侧的时间轴快速拖拽条，交互对齐小米相册：
/// 按住上下滑，列表跟手跳到对应的月份，同时浮出当前月份。
class PhotoTimelineScrubber extends StatefulWidget {
  const PhotoTimelineScrubber({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemOffsets,
    required this.labels,
    this.enabled = true,
  });

  final ScrollController controller;
  final int itemCount;

  /// 每一项在滚动内容里的起始偏移，长度与 [itemCount] 一致。
  final List<double> itemOffsets;

  /// 每一项所属的月份文案，长度与 [itemCount] 一致。
  final List<String> labels;

  final bool enabled;

  @override
  State<PhotoTimelineScrubber> createState() => _PhotoTimelineScrubberState();
}

class _PhotoTimelineScrubberState extends State<PhotoTimelineScrubber> {
  double? _thumbY;
  String? _label;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  bool get _usable =>
      widget.enabled &&
      widget.itemCount > 1 &&
      widget.itemOffsets.length == widget.itemCount &&
      widget.labels.length == widget.itemCount;

  void _seek(double dy, double height) {
    if (!_usable || height <= 0 || !widget.controller.hasClients) return;
    final max = widget.controller.position.maxScrollExtent;
    final ratio = (dy / height).clamp(0.0, 1.0);
    final index =
        (ratio * (widget.itemCount - 1)).round().clamp(0, widget.itemCount - 1);
    final target = widget.itemOffsets[index].clamp(0.0, max);
    if ((widget.controller.offset - target).abs() > 0.5) {
      widget.controller.jumpTo(target);
    }
    final label = widget.labels[index];
    final changed = label != _label;
    if (changed) {
      HapticFeedback.selectionClick();
    }
    _hideTimer?.cancel();
    setState(() {
      _thumbY = dy;
      _label = label;
    });
  }

  void _endDrag() {
    _hideTimer?.cancel();
    // 松手后让月份再停留一下，方便确认跳到了哪一段。
    _hideTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _thumbY = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_usable) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final thumbY = (_thumbY ?? -1000).clamp(0.0, height);
        final active = _thumbY != null;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (details) =>
              _seek(details.localPosition.dy, height),
          onVerticalDragUpdate: (details) =>
              _seek(details.localPosition.dy, height),
          onVerticalDragEnd: (_) => _endDrag(),
          onVerticalDragCancel: _endDrag,
          onTapDown: (details) => _seek(details.localPosition.dy, height),
          onTapUp: (_) => _endDrag(),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerRight,
            children: [
              // 常驻的细条，提示这里可以拖。
              Center(
                child: Container(
                  width: 3,
                  height: height * 0.5,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withOpacity(active ? 0.0 : 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (active) ...[
                Positioned(
                  top: thumbY - 22,
                  right: 6,
                  child: Container(
                    width: 6,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  top: (thumbY - 22).clamp(4.0, height - 48),
                  right: 34,
                  child: _MonthBubble(text: _label ?? ''),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MonthBubble extends StatelessWidget {
  const _MonthBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.78),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
