import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/radius.dart';
import 'app_glass.dart';

/// 白底圆角卡片。圆角 / 内外边距 / 立体感（[AppSurfaceDepth]）在两档之间完全
/// 一致：玻璃档只是多一层模糊，minimal / 无档位时阴影、高光、1px 描边照样在。
///
/// [glass] 为 true 时卡片底子换成玻璃（[AppGlassSurface]），档位取
/// [AppGlassSurface.kCardQuality]（现在是 standard：纯 BackdropFilter，
/// 不抓 capture，见那里的「premium 黑卡」）；玻璃不可用或自适应档位降到
/// [GlassQuality.minimal] 时，自动退回不透明 [AppColors.bgSurface]，
/// 圆角 / 内外边距 / 阴影 / 描边都不变。
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
        // 卡片材质只有一个来源：跟底部胶囊同档的 standard
        // （[AppGlassSurface.kCardQuality]，改那一行即可全量换档）。
        requestedQuality: AppGlassSurface.kCardQuality,
        // 双层阴影 + 顶部内高光 + 1px 描边；minimal 下也画（只是没有模糊）。
        depth: true,
        child: body,
      );
    }

    // 不透明卡片走同一层立体感：阴影 / 高光 / 描边和玻璃档完全一致，
    // 低端机（无玻璃）上也是同一张卡片。
    final Widget surface = AppSurfaceDepth(
      radius: effectiveRadius.topLeft.x,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? AppColors.bgSurface,
          borderRadius: effectiveRadius,
          border: borderColor == null ? null : Border.all(color: borderColor!),
        ),
        child: body,
      ),
    );
    if (margin == null) return surface;
    return Padding(padding: margin!, child: surface);
  }
}
