import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/album_view_settings.dart';
import '../../core/design/colors.dart';
import '../../models/media.dart';

/// 每一张图在滚动内容里的起始偏移，以及它属于哪个时间分组。
typedef TimelineMetrics = ({List<double> offsets, List<String> labels});

/// 算时间轴映射：按实际行高 + 分组头高度 + 视口基准偏移推导，
/// 这样拖到「2024年8月」就真的落在 8 月那一行，不会随距离累积误差。
TimelineMetrics buildTimelineMetrics(
  List<AlbumSection> sections, {
  required double width,
  required int columns,
  required double headerHeight,
  double base = 0,
  String Function(Media media)? fallbackLabel,
}) {
  final offsets = <double>[];
  final labels = <String>[];
  const spacing = 2.0;
  final tileWidth = (width - spacing * (columns - 1)) / columns;
  final rowHeight = tileWidth + spacing;
  var y = base;
  for (final section in sections) {
    if (section.header != null) {
      y += headerHeight;
    }
    final rows = (section.items.length + columns - 1) ~/ columns;
    for (var i = 0; i < section.items.length; i++) {
      offsets.add(y + (i ~/ columns) * rowHeight);
      final header = section.header;
      labels.add(
        header != null && header.isNotEmpty
            ? header
            : (fallbackLabel?.call(section.items[i]) ?? ''),
      );
    }
    y += rows * rowHeight;
  }
  return (offsets: offsets, labels: labels);
}

/// 第一个分组头在滚动内容里的偏移。顶部还有别的 sliver 时靠它对齐，
/// 量不到就返回 0。
double timelineBaseOffset(GlobalKey key) {
  final render = key.currentContext?.findRenderObject();
  if (render is RenderBox && render.attached) {
    try {
      return RenderAbstractViewport.of(render)
          .getOffsetToReveal(render, 0.0)
          .offset;
    } catch (_) {
      return 0;
    }
  }
  return 0;
}

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
