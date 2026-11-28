import 'package:flutter/material.dart';

import '../core/design/colors.dart';

/// 网格里多选态的「选中框 + 右上角勾选圆点」。
///
/// 相册页和本地（隐藏）空间共用这一份：选中是这个样子，未选中时也画一圈
/// 半透明白边，用户一眼知道现在处于多选态、还能点哪些。页面自己不再各画一套。
class TileSelectionOverlay extends StatelessWidget {
  /// 是否已选中。
  final bool selected;

  /// 与网格格子一致的圆角。
  final double radius;

  const TileSelectionOverlay({
    super.key,
    required this.selected,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.5),
              width: selected ? 2.5 : 1,
            ),
            color: selected
                ? AppColors.primary.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.04),
          ),
        ),
        Positioned(
          top: 5,
          right: 5,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary
                  : Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: selected
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : null,
          ),
        ),
      ],
    );
  }
}
