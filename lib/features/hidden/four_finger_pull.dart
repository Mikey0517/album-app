import 'package:flutter/material.dart';

/// 四指下拉：在 App 任意界面监听裸指针事件，四根手指一起往下拉过阈值就触发。
///
/// 用 [Listener] 而不是手势竞技场：它只是旁观指针、不参与竞争，普通滚动、点按、
/// 双指缩放都不受影响；只有同时按住 4 根以上手指、且质心向下位移超过
/// [threshold] 时才回调一次（一次手势只触发一次）。
class FourFingerPullDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onTrigger;

  /// 质心要往下拉多少逻辑像素才触发。
  final double threshold;

  const FourFingerPullDetector({
    super.key,
    required this.child,
    required this.onTrigger,
    this.threshold = 80,
  });

  @override
  State<FourFingerPullDetector> createState() => _FourFingerPullDetectorState();
}

class _FourFingerPullDetectorState extends State<FourFingerPullDetector> {
  /// 当前按着的手指（pointer id → 位置）。
  final Map<int, Offset> _pointers = {};

  /// 凑够 4 根手指那一刻的质心；不足 4 根时清空。
  Offset? _start;

  /// 这次手势已经触发过（手指抬起前不再触发）。
  bool _fired = false;

  void _onDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length >= 4 && _start == null) {
      _start = _centroid();
    }
  }

  void _onMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    final start = _start;
    if (start == null || _fired || _pointers.length < 4) return;
    final delta = _centroid() - start;
    // 以向下为主（斜着拉也算；纯横划、往上划不触发）。阈值不用太大：
    // 四指一起往下带一点就够了，之前 140 在真机上常常拉不出来。
    if (delta.dy >= widget.threshold && delta.dy > delta.dx.abs() * 0.5) {
      _fired = true;
      widget.onTrigger();
    }
  }

  void _onUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 4) _start = null;
    if (_pointers.isEmpty) _fired = false;
  }

  Offset _centroid() {
    var sum = Offset.zero;
    for (final position in _pointers.values) {
      sum += position;
    }
    return sum / _pointers.length.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: widget.child,
    );
  }
}
