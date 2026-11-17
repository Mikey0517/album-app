import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/album_view_settings.dart';
import '../../core/design/accent.dart';
import '../../core/design/colors.dart';
import '../../models/media.dart';

/// 每一张图在滚动内容里的起始偏移，以及它属于哪个时间分组。
typedef TimelineMetrics = ({List<double> offsets, List<String> labels});

/// 算时间轴映射：按实际行高 + 分组头高度 + 视口基准偏移推导，
/// 这样拖到「2024年8月」就真的落在 8 月那一行，不会随距离累积误差。
///
/// [topInset] 是吸顶区（折叠后的头部 + 筛选条 + 分组头）压住的高度：
/// 偏移减去它，拖到某个月份时那一行才落在吸顶区下面，而不是被盖住。
TimelineMetrics buildTimelineMetrics(
  List<AlbumSection> sections, {
  required double width,
  required int columns,
  required double headerHeight,
  double base = 0,
  double topInset = 0,
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
      offsets.add(math.max(0.0, y + (i ~/ columns) * rowHeight - topInset));
      final header = section.header;
      labels.add(
        header != null && header.isNotEmpty
            ? header
            : (fallbackLabel?.call(section.items[i]) ?? ''),
      );
    }
    // 分组高度 = 行高 * 行数 − 最后一行的格间距：网格不会在最后一行下面再
    // 留 2px，这里多算的话每过一组就累积 2px，拖到后面的月份就会差一截。
    if (rows > 0) y += rows * rowHeight - spacing;
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
///
/// [minTop] 是吸顶区（折叠头 + 筛选条 + 日期头）压住的高度：大于 0 时改成
/// 「顶边已经落到吸顶条下沿的第一项」，被吸顶条压住的那一行不再算顶部可见项；
/// 传 0 保持原来的视口口径。
int? firstVisibleSliverChildIndex(GlobalKey key, {double minTop = 0}) {
  final context = key.currentContext;
  final render = context?.findRenderObject();
  if (render is! RenderSliverMultiBoxAdaptor || !render.attached) return null;
  final vertical = render.constraints.axis == Axis.vertical;
  // 视口顶边在滚动内容里的位置：子项在内容里的位置减去它，才是「离视口顶多远」。
  // 只用 constraints.scrollOffset 算不准「还没滚到视口顶」的那条 sliver
  // （那时 scrollOffset 是 0，子项位置会被当成 0），吸顶区一扣就错行。
  final position =
      context == null ? null : Scrollable.maybeOf(context)?.position;
  final pixels = position?.pixels;
  for (var child = render.firstChild;
      child != null;
      child = render.childAfter(child)) {
    if (!child.hasSize) continue;
    final double? layoutOffset = render.childScrollOffset(child);
    if (layoutOffset == null) continue;
    final extent = vertical ? child.size.height : child.size.width;
    final double top = pixels == null
        ? layoutOffset - render.constraints.scrollOffset
        : render.constraints.precedingScrollExtent + layoutOffset - pixels;
    // 吸顶条下面压住的那一行（顶边还没露出吸顶条）不算顶部可见项。
    if (minTop > 0 ? top < minTop : top + extent <= 0) continue;
    final data = child.parentData;
    if (data is SliverMultiBoxAdaptorParentData) return data.index;
    return null;
  }
  return null;
}

/// 「2024年8月」：时间轴气泡只有这一种月份写法。
///
/// 相册网格和朋友圈动态流都从这里取文案，两边不会写出两种格式。
String timelineMonthLabel(DateTime time) {
  final local = time.toLocal();
  return '${local.year}年${local.month}月';
}

/// 「顶部现在是谁」的定位器：相册网格与朋友圈动态流共用同一份实现。
///
/// [sliverKeys] 按 sliver 顺序排列，[sliverStarts] 是每条 sliver 的第一个
/// 子项在扁平列表里的下标。网格能预先算偏移表做跳转，但「拖动中顶部露出
/// 的是哪一项」只有渲染树知道，所以两种列表都走这里。
class VisibleItemLocator {
  const VisibleItemLocator({
    required this.sliverStarts,
    required this.sliverKeys,
    this.topInset = 0,
  });

  static const VisibleItemLocator empty = VisibleItemLocator(
    sliverStarts: <int>[],
    sliverKeys: <GlobalKey>[],
  );

  final List<int> sliverStarts;
  final List<GlobalKey> sliverKeys;

  /// 吸顶区（折叠头 + 筛选条 + 日期头）压住的高度。
  ///
  /// 0 是视口口径（视口顶端那一项）；大于 0 时只认「顶边落到吸顶条下沿」的项，
  /// 被吸顶条压住的那一行不再参与文案——用户看不见它，不该用它报月份。
  /// 加载这个定位器的三处（相册详情页 / 朋友圈动态流 / 朋友圈相册）都显式传。
  final double topInset;

  /// 扁平列表里顶部可见项的下标；还没布局完、量不到时返回 null。
  int? get visibleIndex {
    final strict = _scan(topInset);
    if (strict != null || topInset <= 0) return strict;
    // 吸顶条下面已经不够露出一整行时（比如列表最后一行正好被压住），
    // 退回视口口径，免得拖动中气泡空掉。
    return _scan(0);
  }

  int? _scan(double minTop) {
    final count = math.min(sliverStarts.length, sliverKeys.length);
    for (var i = 0; i < count; i++) {
      final localIndex =
          firstVisibleSliverChildIndex(sliverKeys[i], minTop: minTop);
      if (localIndex == null || localIndex < 0) continue;
      return sliverStarts[i] + localIndex;
    }
    return null;
  }

  /// 顶部可见项对应的文案；[labelAt] 把扁平下标映射成月份。
  String visibleLabel(String Function(int index) labelAt) {
    final index = visibleIndex;
    return index == null ? '' : labelAt(index);
  }
}

/// 相册类网格的实时月份文案：顶部可见那一项是哪个月。
///
/// 相册详情页与朋友圈相册共用，取月份的规则（按当前排序字段）只写一份。
String albumVisibleMonthLabel(
  List<Media> displayItems,
  VisibleItemLocator locator, {
  required AlbumSort sort,
}) {
  return locator.visibleLabel((index) {
    if (index < 0 || index >= displayItems.length) return '';
    return timelineMonthLabel(albumSortDate(displayItems[index], sort));
  });
}

/// 拖拽时浮出的滑块与月份气泡的 key：空闲时它们不存在，
/// 测试据此断言「不按就不显示」。
const Key timelineScrubberThumbKey = ValueKey<String>('timeline-scrubber-thumb');
const Key timelineScrubberLabelKey = ValueKey<String>('timeline-scrubber-label');

// ---------------------------------------------------------------------------
// 时间轴的配色：滑块 / 月份气泡两件套从主题色里取，**没有一处是纯白**。
// 三处使用点（相册详情页、朋友圈相册、朋友圈动态流）都走
// [PhotoTimelineScrubber]，所以颜色只在这里定义一次，不存在两边不一致。
//
// **没有「轨道」这层东西**：早先那条「主色 → 透明」的常驻竖渐变在浅色照片墙
// 上一直看得见，等于给整屏右侧压了一道常亮的竖条；现在空闲时这一层不存在，
// 整条时间轴不画任何像素（见 [timelineScrubberIdleAlpha]），只有按住拖动时
// 才浮出滑块与月份气泡。
// ---------------------------------------------------------------------------

/// 空闲时时间轴的不透明度：0——整条不可见，一个像素都不画。
///
/// 素材（轨道）与它带来的对比度问题一起消失了：拖拽时才有滑块 + 气泡，
/// 那份对比度由 [timelineMonthBubbleColor] 单独保证（白字 ≥ 4.5）。
const double timelineScrubberIdleAlpha = 0.0;

/// 滑块宽度 / 圆角半径（胶囊形）。
const double timelineScrubberThumbWidth = 6;
const double timelineScrubberThumbHeight = 44;

/// 滑块离时间轴框右边的距离。
const double timelineScrubberThumbRight = 6;

/// 滑块的轻微高光：主体是 [AppColors.primary] 实色，这层白色 28% → 0 盖在
/// 上沿 55%（[BoxDecoration] 先画 color 再画 gradient，所以底仍是实色）。
LinearGradient timelineScrubberThumbGradient() => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: 0.28),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: const [0, 0.55],
    );

/// 月份气泡的文字与背景之间的最小对比度（WCAG AA 正文）。
const double timelineMonthBubbleMinContrast = 4.5;

/// 月份气泡背景：主题色的**深色版**（朝黑色压 45%，不够 4.5 就继续压）。
///
/// 气泡里是白字，浅色主色（琥珀、暖橙）压 45% 已经够；深色模式的主色被抬亮
/// 过一档，同样压 45% 落在 4.5 附近，循环再兜一步。所以这里不是写死一个
/// 十六进制数，而是保证「任意主题色 × 任意明暗」都过 4.5 的那一个。
Color timelineMonthBubbleColor() {
  final primary = AppColors.primary;
  var blend = 0.45;
  var color = Color.lerp(primary, Colors.black, blend)!;
  while (AppAccent.contrastRatio(color, Colors.white) <
          timelineMonthBubbleMinContrast &&
      blend < 0.90) {
    blend += 0.05;
    color = Color.lerp(primary, Colors.black, blend)!;
  }
  return color;
}

/// 右侧的时间轴快速拖拽条，交互对齐小米相册：
/// 按住上下滑，列表跟手跳到对应位置，同时浮出当前月份，松手后收起。
///
/// 可拖拽区域由宿主的 Positioned 给定（相册详情页与朋友圈相册都让它紧贴吸顶区
/// 下沿，位置由 `album_timeline_layout.dart` 统一算），滑块和月份气泡都不会
/// 越出这块区域的边界：拖到最上端时贴住顶边，不会浮到吸顶条上去，也不会悬在
/// 内容外面。
///
/// **空闲时这块区域完全是透明的**：不画轨道、不画底、不画占位，只有手指按住
/// 之后才出现滑块与月份气泡。所以它既不会在照片墙上留一道常亮的竖条，也不会
/// 让页面多一层需要解释的材质。
///
/// 两种跳转方式：
/// - offsets 模式（默认）：按每一项的精确偏移跳转，用于等高网格；
/// - progress 模式（传 [progressLabel]）：按「拖动比例 × maxScrollExtent」跳转，
///   用于变高卡片列表。
///
/// 气泡文案与跳转方式解耦：传了 [liveLabel] 就实时取「顶部可见项」的月份
/// （相册页与朋友圈动态流共用），否则沿用 [labels] 里预计算的那一份。
class PhotoTimelineScrubber extends StatefulWidget {
  const PhotoTimelineScrubber({
    super.key,
    required this.controller,
    this.itemCount = 0,
    this.itemOffsets = const <double>[],
    this.labels = const <String>[],
    this.progressLabel,
    this.liveLabel,
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

  /// 气泡文案现取：不用 [labels] 里预计算的那一份，而是每次都问
  /// 「现在顶部露出的是哪一项」（相册页与朋友圈动态流同一套逻辑）。
  ///
  /// 跳转方式不受影响：仍然按 [itemOffsets] 精确定位，避免越拖越偏。
  final String Function()? liveLabel;

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
    if (widget.itemCount <= 1) return false;
    if (widget.itemOffsets.length != widget.itemCount) return false;
    // 现取文案时不需要预计算的 label 表。
    return widget.liveLabel != null ||
        widget.labels.length == widget.itemCount;
  }

  /// 实时文案的来源：progress 模式问进度回调，offsets 模式问 [liveLabel]。
  String Function()? get _liveLabelSource =>
      widget.liveLabel ?? widget.progressLabel;

  void _seek(double dy, double height) {
    if (!_usable || height <= 0 || !widget.controller.hasClients) return;
    final position = widget.controller.position;
    final max = position.maxScrollExtent;
    final ratio = (dy / height).clamp(0.0, 1.0);
    if (widget.isProgressMode) {
      // 变高列表没法建偏移表，按比例直接跳，手感对齐相册页。
      final target = (ratio * max).clamp(0.0, max);
      if ((position.pixels - target).abs() > 0.5) {
        widget.controller.jumpTo(target);
      }
      // 跳转要等这一帧布局完才知道顶部是谁，下一帧再取月份，避免闪错月份。
      _scheduleLiveLabelRefresh();
    } else {
      final index = (ratio * (widget.itemCount - 1))
          .round()
          .clamp(0, widget.itemCount - 1);
      final target = widget.itemOffsets[index].clamp(0.0, max);
      if ((position.pixels - target).abs() > 0.5) {
        widget.controller.jumpTo(target);
      }
      if (widget.liveLabel != null) {
        // 跳转是按偏移算的（不会越拖越偏），文案仍取顶部可见项。
        _scheduleLiveLabelRefresh();
      } else {
        _applyLabel(widget.labels[index]);
      }
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

  void _scheduleLiveLabelRefresh() {
    final source = _liveLabelSource;
    if (source == null || _labelRefreshScheduled) return;
    _labelRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _labelRefreshScheduled = false;
      if (!mounted || _thumbY == null) return;
      final label = source();
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
        // 滑块 44 高、以手指为中线；夹在这块区域内，顶端不会压到吸顶条。
        final thumbTop = (thumbY - timelineScrubberThumbHeight / 2)
            .clamp(0.0, math.max(0.0, height - timelineScrubberThumbHeight))
            .toDouble();
        final bubbleTop = (thumbY - timelineScrubberThumbHeight / 2)
            .clamp(0.0, math.max(0.0, height - 48))
            .toDouble();
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
              // 空闲时这里**没有轨道**：整条时间轴不画任何像素（栈里只有拖拽
              // 时才加的两个孩子）。它仍然整条接管竖向拖拽——手势由外面的
              // GestureDetector 负责（translucent），跟画不画东西无关。
              if (active) ...[
                Positioned(
                  top: thumbTop,
                  right: timelineScrubberThumbRight,
                  child: Container(
                    key: timelineScrubberThumbKey,
                    width: timelineScrubberThumbWidth,
                    height: timelineScrubberThumbHeight,
                    decoration: BoxDecoration(
                      // 主题色实色 + 一道轻微高光（gradient 画在 color 之上）。
                      color: AppColors.primary,
                      borderRadius:
                          BorderRadius.circular(timelineScrubberThumbWidth / 2),
                      gradient: timelineScrubberThumbGradient(),
                    ),
                  ),
                ),
                Positioned(
                  top: bubbleTop,
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

/// 月份气泡：背景是主题色的深色版（[timelineMonthBubbleColor]），白字对它的
/// 对比度恒 ≥ [timelineMonthBubbleMinContrast]。
///
/// 不用纯黑 78%：那和「相册」这一屏的配色没关系，浮在时间轴上像另一套 UI。
/// 深色版主色既保持主题感，又不至于让白字掉到 4.5 以下（深色模式的亮主色也
/// 在内，循环会继续压暗到过线）。
class _MonthBubble extends StatelessWidget {
  const _MonthBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: timelineMonthBubbleColor(),
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
