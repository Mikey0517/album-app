import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../core/design/colors.dart';

/// 把 [GlassQuality] 从这里再导出，用到玻璃的页面只 import 本文件就行，
/// 不必各自去 import 一次 liquid_glass_widgets。
export 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassQuality;

/// 玻璃档位的注入点。
///
/// 生产环境不需要包它：档位直接来自 [GlassAdaptiveScopeData]（main() 里
/// `LiquidGlassWidgets.wrap(adaptiveQuality: true)` 给的上限）。测试里没有
/// 自适应 scope，用它注入 `minimal` 来断言「退化到不透明表面」那条分支。
class AppGlassScope extends InheritedWidget {
  const AppGlassScope({super.key, required this.quality, required super.child});

  /// 要注入的档位；[GlassQuality.minimal] 表示只想看退化后的样子。
  final GlassQuality? quality;

  static GlassQuality? qualityOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppGlassScope>()?.quality;

  @override
  bool updateShouldNotify(AppGlassScope oldWidget) =>
      oldWidget.quality != quality;
}

/// 这一处实际该用的玻璃档位；返回 `null` 表示「不要画玻璃，用不透明表面」。
///
/// 三种情况一律退回不透明：
/// 1. 拿不到任何档位 —— main() 里 initialize 失败 / 没包 wrap，此时画玻璃
///    只会画出一片空白（旧版 HomePage/FeedPage 就是这么判断的）；
/// 2. 注入或自适应上限已经降到 [GlassQuality.minimal] —— 低端机/过热降档；
/// 3. 调用点自己要求 minimal。
///
/// [requested] 是调用点想要的档位：列表里的卡片传 `standard`（包的轻量
/// shader，文档明确推荐滚动列表用它），底部栏不传、跟随自适应上限。
GlassQuality? glassQualityFor(
  BuildContext context, {
  GlassQuality? requested,
}) {
  final injected = AppGlassScope.qualityOf(context);
  final ceiling = GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
  // 没有档位来源 = 玻璃不可用：不画。
  if (injected == null && ceiling == null) return null;
  if (injected == GlassQuality.minimal) return null;
  if (ceiling == GlassQuality.minimal) return null;
  final quality = injected ?? requested ?? ceiling;
  if (quality == null || quality == GlassQuality.minimal) return null;
  return quality;
}

/// 一块玻璃底子：卡片、底部栏这种「背景」用它，交互控件不用。
///
/// 降级到不透明时只有一个 [AppColors.bgSurface] 圆角块，布局与玻璃分支
/// 完全一致（同样的 margin / padding / 圆角），所以切档不会跳版。
///
/// 性能：列表里的卡片用 `useOwnLayer: false`（复用外层 backdrop，没有外层
/// 时由包自己兜底），并显式要 `standard` 档——包的轻量单通道 shader，官方
/// 文档明确说它适合滚动列表（premium 每帧 toImageSync 抓纹理，只能用在静态
/// 布局）。内容再套一层 [RepaintBoundary]：滚动时只重绘玻璃层，卡片里的
/// 文字/图片走缓存，不会每帧重建。
class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    super.key,
    required this.child,
    this.radius = 16,
    this.margin,
    this.padding,
    this.border,
    this.requestedQuality,
    this.useOwnLayer = false,
    this.settings,
  });

  final Widget child;

  /// 圆角半径（直角用 0）。
  final double radius;

  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// 只在退化分支画的描边（比如底部栏顶部那条 1px 分隔线）。
  /// 玻璃分支不画：玻璃自己有一圈高光边，再加描边就成了两条线。
  final BoxBorder? border;

  /// 调用点想要的档位；见 [glassQualityFor]。
  final GlassQuality? requestedQuality;

  /// 玻璃是否自建一层渲染上下文。默认 false = 复用外层 backdrop。
  final bool useOwnLayer;

  /// 玻璃参数；null 时用包主题（和 App 里其它玻璃控件同一套）。
  final LiquidGlassSettings? settings;

  @override
  Widget build(BuildContext context) {
    final quality = glassQualityFor(context, requested: requestedQuality);
    final borderRadius = BorderRadius.circular(radius);
    // 卡片内容单独成层：滚动时命中缓存，不跟着列表每帧重画。
    final content = RepaintBoundary(child: child);

    if (quality == null) {
      // 用 DecoratedBox 而不是 Container：Container 会把 decoration 的
      // 描边宽度算进布局，底部栏那条 1px 分隔线会让整条栏高变成 57。
      Widget opaque = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: borderRadius,
          border: border,
        ),
        child: padding == null
            ? content
            : Padding(padding: padding!, child: content),
      );
      if (margin == null) return opaque;
      return Padding(padding: margin!, child: opaque);
    }

    final glass = GlassContainer(
      // 直角形状（底部栏那种满宽玻璃）没有圆角可画，包会跳过边框高光。
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      quality: quality,
      useOwnLayer: useOwnLayer,
      settings: settings,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      child: content,
    );
    if (margin == null) return glass;
    return Padding(padding: margin!, child: glass);
  }
}
