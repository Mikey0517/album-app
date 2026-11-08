import 'package:flutter/material.dart';

/// 下滑关闭图片：用 Listener 直接看原始指针事件，不参与手势竞技场。
///
/// 之前用的是 onVerticalDragUpdate，它和 InteractiveViewer 的缩放识别器抢手势，
/// 双指缩放时经常被纵向拖动先抢走，导致「放大很难触发」。
class ViewerDismissGesture extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final VoidCallback? onCancel;

  const ViewerDismissGesture({
    super.key,
    required this.child,
    required this.enabled,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onCancel,
  });

  @override
  State<ViewerDismissGesture> createState() => _ViewerDismissGestureState();
}

class _ViewerDismissGestureState extends State<ViewerDismissGesture> {
  int? _pointer;
  bool _multi = false;
  double _moved = 0;

  @override
  void didUpdateWidget(covariant ViewerDismissGesture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pointer != null) {
      // 放大后关闭手势失效，清掉当前跟踪的指针，避免下次误判成多指。
      _pointer = null;
      _multi = false;
      _moved = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_pointer == null) {
          _pointer = event.pointer;
          _moved = 0;
          _multi = false;
        } else if (!_multi) {
          // 第二根手指落下：用户是想缩放，不是下滑关闭。
          _multi = true;
          widget.onCancel?.call();
        }
      },
      onPointerMove: (event) {
        if (_multi || event.pointer != _pointer) return;
        if (event.delta.dy <= 0) return;
        _moved += event.delta.dy;
        widget.onDragUpdate(event.delta.dy);
      },
      onPointerUp: (event) {
        if (event.pointer != _pointer) return;
        _pointer = null;
        if (_multi) {
          _multi = false;
          widget.onCancel?.call();
          return;
        }
        if (_moved > 0) widget.onDragEnd(0);
        _moved = 0;
      },
      onPointerCancel: (event) {
        if (event.pointer != _pointer) return;
        _pointer = null;
        _multi = false;
        _moved = 0;
        widget.onCancel?.call();
      },
      child: widget.child,
    );
  }
}
