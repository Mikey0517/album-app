import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/radius.dart';

/// 白底圆角卡片。默认无阴影，靠底色对比建立层次。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final BorderRadius? radius;
  final Color? color;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.radius,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = radius ?? BorderRadius.circular(AppRadius.lg);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? AppColors.bgSurface,
        borderRadius: effectiveRadius,
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: Material(
          color: Colors.transparent,
          child: onTap == null
              ? content
              : InkWell(
                  onTap: onTap,
                  child: content,
                ),
        ),
      ),
    );
  }
}
