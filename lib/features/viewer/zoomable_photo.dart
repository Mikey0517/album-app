import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'viewer_gestures.dart';

/// 可缩放的照片容器：双指原始指针直接算缩放，不经过手势竞技场，
/// 普通照片和动态照片共用。下滑关闭只在未放大时启用。
class ZoomablePhoto extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enableDoubleTap;
  final ValueChanged<bool>? onZoomChanged;
  final ValueChanged<double>? onDragUpdate;
  final ValueChanged<double>? onDragEnd;
  final VoidCallback? onDragCancel;

  const ZoomablePhoto({
    super.key,
    required this.child,
    this.onTap,
    this.enableDoubleTap = true,
    this.onZoomChanged,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
  });

  @override
  State<ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 1;
  static const double _maxScale = 6;
  static const double _doubleTapScale = 2.5;

  /// 缩放灵敏度：手指距离变化 1% 时，画面放大得更多一点。
  static const double _sensitivity = 1.35;

  final Map<int, Offset> _pointers = {};
  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _viewport = Size.zero;

  double _startDistance = 0;
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _lastPan = Offset.zero;

  late final AnimationController _animation;
  Animation<double>? _scaleAnim;
  Animation<Offset>? _offsetAnim;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final scale = _scaleAnim?.value;
        final offset = _offsetAnim?.value;
        if (scale == null || offset == null) return;
        setState(() {
          _scale = scale;
          _offset = offset;
        });
      });
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  bool get _zoomed => _scale > 1.01;

  void _notifyZoom(bool value) => widget.onZoomChanged?.call(value);

  Offset get _focal {
    var sum = Offset.zero;
    for (final point in _pointers.values) {
      sum += point;
    }
    return sum / _pointers.length.toDouble();
  }

  double get _distance {
    if (_pointers.length < 2) return 0;
    final points = _pointers.values.toList(growable: false);
    return (points[0] - points[1]).distance;
  }

  Offset _clampOffset(Offset value, double scale) {
    if (_viewport == Size.zero) return value;
    final maxX = _viewport.width * (scale - 1) / 2;
    final maxY = _viewport.height * (scale - 1) / 2;
    return Offset(value.dx.clamp(-maxX, maxX), value.dy.clamp(-maxY, maxY));
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _lastPan = event.localPosition;
    if (_pointers.length == 2) {
      // 双指按下立刻锁住 PageView，避免翻页手势抢走缩放。
      _notifyZoom(true);
      _startDistance = _distance;
      _startScale = _scale;
      _startOffset = _offset;
      _animation.stop();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length >= 2 && _startDistance > 0) {
      final ratio = _distance / _startDistance;
      final scale = (_startScale * math.pow(ratio, _sensitivity))
          .clamp(_minScale, _maxScale)
          .toDouble();
      final focal = _focal;
      final center = Offset(_viewport.width / 2, _viewport.height / 2);
      final next = focal -
          center -
          (focal - center - _startOffset) * (scale / _startScale);
      setState(() {
        _scale = scale;
        _offset = _clampOffset(next, scale);
      });
    } else if (_zoomed) {
      final delta = event.localPosition - _lastPan;
      setState(() {
        _offset = _clampOffset(_offset + delta, _scale);
      });
    }
    _lastPan = event.localPosition;
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _startDistance = 0;
    if (_pointers.isNotEmpty) return;
    if (_scale < 1.02) {
      _animateTo(1, Offset.zero);
      _notifyZoom(false);
    } else {
      setState(() => _offset = _clampOffset(_offset, _scale));
      _notifyZoom(true);
    }
  }

  void _animateTo(double scale, Offset offset) {
    _animation.stop();
    _scaleAnim = Tween<double>(begin: _scale, end: scale).animate(
      CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic),
    );
    _offsetAnim = Tween<Offset>(begin: _offset, end: offset).animate(
      CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic),
    );
    _animation
      ..reset()
      ..forward();
  }

  void _toggleZoom(TapDownDetails details) {
    if (_zoomed) {
      _animateTo(1, Offset.zero);
      _notifyZoom(false);
      return;
    }
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final next = (center - details.localPosition) * (_doubleTapScale - 1);
    _animateTo(_doubleTapScale, _clampOffset(next, _doubleTapScale));
    _notifyZoom(true);
  }

  @override
  Widget build(BuildContext context) {
    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onDoubleTapDown: widget.enableDoubleTap ? _toggleZoom : null,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translate(_offset.dx, _offset.dy)
                ..scale(_scale),
              child: widget.child,
            ),
          ),
        );
      },
    );
    if (widget.onDragUpdate == null) return content;
    return ViewerDismissGesture(
      enabled: !_zoomed,
      onDragUpdate: widget.onDragUpdate!,
      onDragEnd: widget.onDragEnd ?? (_) {},
      onCancel: widget.onDragCancel,
      child: content,
    );
  }
}
