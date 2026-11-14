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

/// 取一个 [SliverList]（变高卡片列表）里第一条可见子项的 index。
///
/// 网格能用偏移表定位，变高列表不行，只能问渲染树「现在顶部是谁」：
/// 子项在 sliver 里的位置是 `childScrollOffset - constraints.scrollOffset`
/// （注意不能用 paintBounds，它是子项自己的局部坐标，永远是 0 起点），
/// 加上自身高度还为正的那条就是露出视口的第一项。
int? firstVisibleSliverChildIndex(GlobalKey key) {
  final render = key.currentContext?.findRenderObject();
  if (render is! RenderSliverMultiBoxAdaptor || !render.attached) return null;
  final vertical = render.constraints.axis == Axis.vertical;
  for (var child = render.firstChild;
      child != null;
      child = render.childAfter(child)) {
    if (!child.hasSize) continue;
    final double? layoutOffset = render.childScrollOffset(child);
    if (layoutOffset == null) continue;
    final extent = vertical ? child.size.height : child.size.width;
    final double top = layoutOffset - render.constraints.scrollOffset;
    if (top + extent <= 0) continue;
    final data = child.parentData;
    if (data is SliverMultiBoxAdaptorParentData) return data.index;
    return null;
  }
  return null;
}

/// 拖拽时浮出的滑块与月份气泡的 key：空闲时它们不存在，
/// 测试据此断言「不按就不显示」。
const Key timelineScrubberThumbKey = ValueKey<String>('timeline-scrubber-thumb');
const Key timelineScrubberLabelKey = ValueKey<String>('timeline-scrubber-label');

/// 右侧的时间轴快速拖拽条，交互对齐小米相册：
/// 按住上下滑，列表跟手跳到对应位置，同时浮出当前月份，松手后收起。
///
/// 两种定位模式：
/// - offsets 模式（默认）：按每一项的精确偏移跳转，用于等高网格；
/// - progress 模式（传 [progressLabel]）：按「拖动比例 × maxScrollExtent」跳转，
///   用于变高卡片列表；月份文案由外部回调给出（动态流给的是顶部可见那条动态）。
class PhotoTimelineScrubber extends StatefulWidget {
  const PhotoTimelineScrubber({
    super.key,
    required this.controller,
    this.itemCount = 0,
    this.itemOffsets = const <double>[],
    this.labels = const <String>[],
    this.progressLabel,
    this.enabled = true,
    this.hideDelay = const Duration(milliseconds: 700),
  });

  final ScrollController controller;

  /// offsets 模式的项数、每一项的起始偏移、每一项的月份文案。
  final int itemCount;
  final List<double> itemOffsets;
  final List<String> labels;

  /// 非空即进入 progress 模式：拖动比例直接映射到滚动位置，
  /// 月份文案每次由这个回调现取。
  final String Function()? progressLabel;

  final bool enabled;

  /// 松手后月份气泡再停留多久。
  final Duration hideDelay;

  bool get isProgressMode => progressLabel != null;

  @override
  State<PhotoTimelineScrubber> createState() => _PhotoTimelineScrubberState();
}

class _PhotoTimelineScrubberState extends State<PhotoTimelineScrubber> {
  double? _thumbY;
  String? _label;
  Timer? _hideTimer;
  bool _labelRefreshScheduled = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  bool get _usable {
    if (!widget.enabled) return false;
    if (widget.isProgressMode) return true;
    return widget.itemCount > 1 &&
        widget.itemOffsets.length == widget.itemCount &&
        widget.labels.length == widget.itemCount;
  }

  void _seek(double dy, double height) {
    if (!_usable || height <= 0 || !widget.controller.hasClients) return;
    final position = widget.controller.position;
    final max = position.maxScrollExtent;
    final ratio = (dy / height).clamp(0.0, 1.0);
    final external = widget.progressLabel;
    if (external != null) {
      // 变高列表没法建偏移表，按比例直接跳，手感对齐相册页。
      final target = (ratio * max).clamp(0.0, max);
      if ((position.pixels - target).abs() > 0.5) {
        widget.controller.jumpTo(target);
      }
      // 跳转要等这一帧布局完才知道顶部是谁，下一帧再取月份，避免闪错月份。
      _scheduleProgressLabelRefresh();
    } else {
      final index = (ratio * (widget.itemCount - 1))
          .round()
          .clamp(0, widget.itemCount - 1);
      final target = widget.itemOffsets[index].clamp(0.0, max);
      if ((position.pixels - target).abs() > 0.5) {
        widget.controller.jumpTo(target);
      }
      _applyLabel(widget.labels[index]);
    }
    _hideTimer?.cancel();
    setState(() => _thumbY = dy);
  }

  /// 换月震动只在文案真的变了时发一次。
  void _applyLabel(String label) {
    if (label == _label) return;
    _label = label;
    HapticFeedback.selectionClick();
  }

  void _scheduleProgressLabelRefresh() {
    final external = widget.progressLabel;
    if (external == null || _labelRefreshScheduled) return;
    _labelRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _labelRefreshScheduled = false;
      if (!mounted || _thumbY == null) return;
      final label = external();
      if (label == _label) return;
      setState(() => _applyLabel(label));
    });
  }

  void _endDrag() {
    _hideTimer?.cancel();
    // 松手后让月份再停留一下，方便确认跳到了哪一段。
    _hideTimer = Timer(widget.hideDelay, () {
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
                    key: timelineScrubberThumbKey,
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
                  child: _MonthBubble(
                    key: timelineScrubberLabelKey,
                    text: _label ?? '',
                  ),
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
  const _MonthBubble({super.key, required this.text});

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
