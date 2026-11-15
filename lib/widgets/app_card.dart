import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/radius.dart';
import 'app_glass.dart';

/// 白底圆角卡片。默认无阴影，靠底色对比建立层次。
///
/// [glass] 为 true 时卡片底子换成玻璃（[AppGlassSurface]）：玻璃不可用或
/// 自适应档位降到 [GlassQuality.minimal] 时，自动退回不透明
/// [AppColors.bgSurface]，圆角 / 内外边距都不变。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final BorderRadius? radius;
  final Color? color;
  final Color? borderColor;

  /// 卡片底子是否用玻璃。玻璃分支只支持等宽圆角，且忽略 [color] /
  /// [borderColor]（玻璃自己的 tint 和高光边代替它们）。
  final bool glass;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.radius,
    this.color,
    this.borderColor,
    this.glass = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = radius ?? BorderRadius.circular(AppRadius.lg);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
    final body = ClipRRect(
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
    );

    if (glass) {
      assert(
        color == null && borderColor == null,
        '玻璃卡片不吃自定义 color/borderColor，请用不透明卡片。',
      );
      return AppGlassSurface(
        radius: effectiveRadius.topLeft.x,
        margin: margin,
        // 设置页/列表里的卡片：轻量 shader + 复用外层 backdrop。
        requestedQuality: GlassQuality.standard,
        child: body,
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? AppColors.bgSurface,
        borderRadius: effectiveRadius,
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: body,
    );
  }
}
