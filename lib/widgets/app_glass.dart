import 'dart:io';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../core/design/accent.dart';
import '../core/design/colors.dart';
import '../core/page_backdrop_controller.dart';

/// 把 [GlassQuality] 从这里再导出，用到玻璃的页面只 import 本文件就行，
/// 不必各自去 import 一次 liquid_glass_widgets。
export 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassQuality;

/// 玻璃档位的注入点。
///
/// 生产环境不需要包它：档位直接来自 [GlassAdaptiveScopeData]（main() 里
/// [LiquidGlassWidgets.wrap] 的 adaptiveQuality 给的上限）。测试里没有
/// 自适应 scope，用它注入 [GlassQuality.minimal] 来断言「退化到不透明表面」
/// 那条分支。
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

/// 这一处实际该用的玻璃档位；返回 null 表示「不要画玻璃，用不透明表面」。
///
/// 三种情况一律退回不透明：
/// 1. 拿不到任何档位 —— main() 里 initialize 失败 / 没包 wrap，此时画玻璃
///    只会画出一片空白（旧版 HomePage/FeedPage 就是这么判断的）；
/// 2. 注入或自适应上限已经降到 [GlassQuality.minimal] —— 低端机/过热降档；
/// 3. 调用点自己要求 minimal。
///
/// [requested] 是调用点想要的档位：列表里的卡片传 standard（包的轻量
/// shader，文档明确推荐滚动列表用它）；底部栏也直接要 standard，不跟随
/// 自适应上限——胶囊浮在内容上面，premium 每帧抓全屏纹理，滑动时太贵。
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

/// 玻璃自己的 tint（[appGlassSettings] 里的 glassColor）：浅色 23% 的冷白，
/// 深色 17% 的白。
///
/// 单独抽出来是为了让「玻璃底衬有多亮」只有一个数——对比度计算与 shader 用
/// 同一份取值，不再各写一遍。
Color get appGlassTintColor =>
    AppColors.isDark ? const Color(0x2BFFFFFF) : const Color(0x3BD2DCF0);

/// 玻璃表面自己的光学参数。
///
/// 为什么不用包的 classic 预设：classic 的 tint 只有 12% 白蓝、模糊 5，落在
/// 纯色页面上「模糊纯色还是纯色」，整块玻璃只剩一点透明度。这里把 tint 提到
/// 23%（深色 17%）、模糊提到 8，让表面自己撑起一点底色与质感；描边和顶部
/// 内高光再由 [AppGlassSurface] 叠一层。仍然只吃 standard 的轻量 shader。
LiquidGlassSettings appGlassSettings(BuildContext context) {
  final dark = AppColors.isDark;
  return LiquidGlassSettings(
    thickness: 12,
    blur: 8,
    glassColor: appGlassTintColor,
    lightAngle: 2.356,
    lightIntensity: dark ? 0.7 : 0.85,
    ambientStrength: dark ? 0.0 : 0.15,
    refractiveIndex: 1.2,
    saturation: 1.2,
    chromaticAberration: dark ? 0.01 : 0.02,
  );
}

/// 玻璃表面的 1px 半透明描边颜色：浅色模式收一道极淡的暗边，深色模式提亮。
Color get appGlassStrokeColor => AppColors.isDark
    ? Colors.white.withValues(alpha: 0.14)
    : Colors.black.withValues(alpha: 0.08);

/// 玻璃表面的顶部内高光：白色 12% → 0，只铺上沿一半多一点。
LinearGradient get appGlassHighlightGradient => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: 0.12),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: const [0, 0.55],
    );

/// 玻璃表面**内部**那层低透明 scrim 的不透明度：浅色 42%、深色 50%。
///
/// 只给「浮在滚动内容上、里面还有文字」的表面用（底部胶囊）。磨砂后面是
/// 照片，颜色随时会变，未选中的灰字需要一个稳定底衬：把玻璃的底色往页面
/// 底色压回一半，文字就有了一块不随内容跳的底；再往上加玻璃就看不出来了。
///
/// 和 [appBackdropMaskColor] 不是一回事：那个铺在整页背景图上，这个在玻璃
/// 表面内部。
const double appGlassScrimAlphaLight = 0.42;
const double appGlassScrimAlphaDark = 0.50;

/// 当前明暗模式下 scrim 的不透明度（页面底色 + 它 = [appGlassScrimColor]）。
double appGlassScrimAlpha() =>
    AppColors.isDark ? appGlassScrimAlphaDark : appGlassScrimAlphaLight;

/// scrim 实际用的颜色：页面底色 + 上面对应的不透明度。
Color appGlassScrimColor() =>
    AppColors.bgPage.withValues(alpha: appGlassScrimAlpha());

/// 带 scrim 的表面的「稳定底衬」：scrim 叠在「玻璃 tint 叠页面底色」上。
///
/// 这就是文字实际落上去的那块颜色（页面底色是玻璃背后最典型的底），
/// 拿它算对比度才有意义；半透明 scrim 单独算不出对比度。
Color appGlassScrimBackplate() => AppAccent.compositeOver(
      appGlassScrimColor(),
      AppAccent.compositeOver(appGlassTintColor, AppColors.bgPage),
    );

/// 一块玻璃底子：卡片、底部栏这种「背景」用它，交互控件不用。
///
/// 降级到不透明时只有一个 [AppColors.bgSurface] 圆角块，布局与玻璃分支
/// 完全一致（同样的 margin / padding / 圆角），所以切档不会跳版。
///
/// 玻璃分支比「一块包的 GlassContainer」多几层，都是布局外的静态绘制：
/// - [strokeKey]：[DecorationPosition.foreground] 的 1px 描边，让表面边界
///   看得清（用 DecoratedBox 的前景绘制，不参与布局，不会把 56 撑成 57）；
/// - [scrimKey]：可选的内部 scrim（见 [appGlassScrimColor]），垫在内容
///   **下面**，给浮在滚动内容上的文字一块稳定底衬；
/// - [highlightKey]：顶部内高光叠层，[IgnorePointer] 盖在内容上、不挡点击。
///
/// 几何约定只有一条：**外框 = 内容 + [padding]，玻璃铺满外框，内容再内缩。**
/// 所以 padding 由本控件自己加在 Stack 里，不交给 [GlassContainer]——
/// 交给它的话整棵子树（含 scrim 与高光）会一起缩进 padding，外框上就留下
/// 一条没有高光的边，看上去像「内容」和「留白」两种材质拼起来。
///
/// 性能：列表里的卡片用 useOwnLayer: false（复用外层 backdrop，没有外层时由
/// 包自己兜底），并显式要 standard 档——包的轻量单通道 shader，官方文档明确
/// 说它适合滚动列表（premium 每帧 toImageSync 抓纹理，只能用在静态布局）。
/// 内容再套一层 [RepaintBoundary]：滚动时只重绘玻璃层，卡片里的文字/图片走
/// 缓存，不会每帧重建。
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
    this.scrim = false,
    this.scrimColor,
  });

  /// 玻璃分支的前景描边层。
  static const Key strokeKey = Key('app-glass-stroke');

  /// 玻璃分支的内部 scrim 层（只有 [scrim] 为 true 时有）。
  static const Key scrimKey = Key('app-glass-scrim');

  /// 玻璃分支的顶部内高光层。
  static const Key highlightKey = Key('app-glass-highlight');

  final Widget child;

  /// 圆角半径（直角用 0）。
  final double radius;

  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// 只在退化分支画的描边（比如底部栏顶部那条 1px 分隔线）。
  /// 玻璃分支不画：玻璃自带 [strokeKey] 那圈描边与内高光，再加就成了两条线。
  /// 不传时退化分支默认给一圈 [AppColors.divider] 细边，胶囊/卡片才有边界。
  final BoxBorder? border;

  /// 调用点想要的档位；见 [glassQualityFor]。
  final GlassQuality? requestedQuality;

  /// 玻璃是否自建一层渲染上下文。默认 false = 复用外层 backdrop。
  final bool useOwnLayer;

  /// 玻璃参数；null 时用 [appGlassSettings]（和 App 里其它玻璃控件同一套）。
  final LiquidGlassSettings? settings;

  /// 是否在玻璃内部叠一层低透明 scrim（[scrimKey]）。
  ///
  /// 给「玻璃后面有内容在滚、表面里还有文字/图标」的地方用（底部胶囊）：
  /// 磨砂后面是照片，只靠玻璃自己的 tint，文字落上去的底色每帧都在变。
  /// 卡片这种底下基本是页面底色的表面不需要——多叠一层只会把玻璃压灰。
  final bool scrim;

  /// scrim 的颜色；null 时用 [appGlassScrimColor]（页面底色 + 42%/50%）。
  final Color? scrimColor;

  @override
  Widget build(BuildContext context) {
    final quality = glassQualityFor(context, requested: requestedQuality);
    final borderRadius = BorderRadius.circular(radius);
    // 卡片内容单独成层：滚动时命中缓存，不跟着列表每帧重画。
    final content = RepaintBoundary(child: child);
    // 内容内缩：padding 在表面内部、玻璃之下，**不是**把整个表面缩进一圈。
    final padded = padding == null
        ? content
        : Padding(padding: padding!, child: content);

    if (quality == null) {
      // 用 DecoratedBox 而不是 Container：Container 会把 decoration 的
      // 描边宽度算进布局，底部栏那条 1px 描边会让整条栏高变成 57。
      // 退化分支的底子已经不透明（[AppColors.bgSurface]），不需要 scrim。
      Widget opaque = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: borderRadius,
          border: border ?? Border.all(color: AppColors.divider, width: 1),
        ),
        child: padded,
      );
      if (margin == null) return opaque;
      return Padding(padding: margin!, child: opaque);
    }

    final glass = GlassContainer(
      // 圆角形状（底部栏那种胶囊）走包的 superellipse，圆角之外还有一圈
      // 玻璃自己的高光边。
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      quality: quality,
      useOwnLayer: useOwnLayer,
      settings: settings ?? appGlassSettings(context),
      // padding 不交给 GlassContainer：见类文档的几何约定。
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // scrim 垫在内容下面：把玻璃底色压回页面底色附近，文字才有稳定底衬。
          if (scrim)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: scrimKey,
                  decoration: BoxDecoration(
                    color: scrimColor ?? appGlassScrimColor(),
                    borderRadius: borderRadius,
                  ),
                ),
              ),
            ),
          padded,
          // 顶部内高光：静态一层，盖在内容上、不参与命中测试。
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: highlightKey,
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: appGlassHighlightGradient,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // 1px 半透明描边：前景绘制，布局尺寸一点不变（Container 的 border 会把
    // 56 撑成 57）。
    final Widget stroked = DecoratedBox(
      key: strokeKey,
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: appGlassStrokeColor, width: 1),
      ),
      child: glass,
    );
    if (margin == null) return stroked;
    return Padding(padding: margin!, child: stroked);
  }
}

/// 背景图上的可读性遮罩：浅色模式叠 [AppColors.bgPage] 55%，深色 65%。
///
/// 图上直接压一层页面底色，卡片/文字不用跟着换配色也读得清；两档的差别
/// 来自深色底本身更亮（#0E1118），压得轻一点就够。
const double appBackdropMaskAlphaLight = 0.55;
const double appBackdropMaskAlphaDark = 0.65;

/// 当前明暗模式下的遮罩不透明度。
double appBackdropMaskAlpha() =>
    AppColors.isDark ? appBackdropMaskAlphaDark : appBackdropMaskAlphaLight;

/// 遮罩实际用的颜色（页面底色 + 上面对应的不透明度）。
Color appBackdropMaskColor() =>
    AppColors.bgPage.withValues(alpha: appBackdropMaskAlpha());

/// 页面最底层的「流动底色」：给玻璃一点可被模糊的内容。
///
/// 根因：BackdropFilter 模糊的是它背后的像素，纯色页面上模糊纯色还是纯色，
/// 玻璃只剩一点透明度。这里在 [AppColors.bgPage] 上铺一条非常克制的对角线
/// 渐变加两团径向光斑（主题色 6~10% 透明度，深色模式换成压暗的近似色），
/// 玻璃背后就有东西在流动。
///
/// 用户在「我的 → 页面背景」选过图之后，渐变层换成那张图（[PageBackdropController]，
/// 三个页面共用同一张）：[BoxFit.cover] 铺满 + 一层可读性遮罩，渐变与光斑整体
/// 让位（图本身就是「有东西可模糊」）。图丢了自动回退渐变。
///
/// 性能：全是静态绘制，不参与每帧重绘；背景图只解码一份（[Image.file] 的
/// cacheWidth 走 [ResizeImage]，解码尺寸封顶 [PageBackdropController.maxEdge]），
/// 并单独包一层 [RepaintBoundary]。与玻璃卡片共存时不额外开模糊层——模糊由
/// 卡片自己的 glass shader 负责，这里再开一层就是白烧 GPU。
/// [GlassQuality.minimal] 下照样画——背景是普通绘制，跟玻璃档位无关。
class AppGlassBackdrop extends StatelessWidget {
  const AppGlassBackdrop({super.key, required this.child});

  /// 不透明的页面底色（[AppColors.bgPage]）。
  static const Key baseKey = Key('app-glass-backdrop-base');

  /// 对角线线性渐变层。
  static const Key gradientKey = Key('app-glass-backdrop-gradient');

  /// 径向光斑层（两团，同一个 key）。
  static const Key blobKey = Key('app-glass-backdrop-blob');

  /// 自定义背景图那一层（[Image.file]，`BoxFit.cover`）。
  static const Key imageKey = Key('app-glass-backdrop-image');

  /// 背景图上的可读性遮罩层。
  static const Key maskKey = Key('app-glass-backdrop-mask');

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            key: baseKey,
            decoration: BoxDecoration(color: AppColors.bgPage),
          ),
        ),
        // 背景图/渐变二选一：路径有值且文件还在才走图，否则（含文件被删）
        // 原样回退到渐变。
        Positioned.fill(
          child: ValueListenableBuilder<String?>(
            valueListenable: PageBackdropController.path,
            builder: (context, saved, _) {
              final file = PageBackdropController.imageFileOrNull(saved);
              return file == null
                  ? _gradientLayers()
                  : _photoLayers(file);
            },
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }

  /// 没有自定义背景图时的「流动底色」。
  Widget _gradientLayers() {
    final dark = AppColors.isDark;
    // 深色模式不用亮主色：夜里那会是一层灰雾。换成往页面底色压暗的近似色，
    // 透明度略提一点补回可见度。
    final tint = dark
        ? Color.lerp(AppColors.primary, AppColors.bgPage, 0.55)!
        : AppColors.primary;
    final lineAlpha = dark ? 0.18 : 0.07;
    final blobAlpha = dark ? 0.16 : 0.08;
    final fade = tint.withValues(alpha: 0.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          key: gradientKey,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint.withValues(alpha: lineAlpha * 0.6),
                fade,
                tint.withValues(alpha: lineAlpha),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
        // 两团光斑用同一个 key，所以各自套一层 Positioned：Stack 的直接
        // 子节点（Positioned）没有 key，就不会撞 key。
        Positioned.fill(
          child: DecoratedBox(
            key: blobKey,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.9, -0.75),
                radius: 1.1,
                colors: [tint.withValues(alpha: blobAlpha), fade],
                stops: const [0, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            key: blobKey,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.95, 0.35),
                radius: 0.85,
                colors: [tint.withValues(alpha: blobAlpha * 0.75), fade],
                stops: const [0, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 自定义背景图：`BoxFit.cover` 铺满 + 一层可读性遮罩。
  Widget _photoLayers(File file) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 单独成层 + 解码尺寸封顶：玻璃卡片滚动/重绘时不重新解码这张图。
        RepaintBoundary(
          child: Image.file(
            file,
            key: imageKey,
            fit: BoxFit.cover,
            cacheWidth: PageBackdropController.maxEdge,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        DecoratedBox(
          key: maskKey,
          decoration: BoxDecoration(color: appBackdropMaskColor()),
        ),
      ],
    );
  }
}
