/// 一条与底部 footer **完全相同**的悬浮玻璃条：三处吸顶条 + footer 共用这一份。
///
/// **一份材质，四个调用点**：底部 footer 胶囊（AppBottomTabBar）与三处吸顶
/// 悬浮条（朋友圈吸顶日期条、相册吸顶分类条、相册吸顶日期条）都走
/// [AppChromeGlassBar]。光学参数、scrim、档位、自建层、描边/高光全部由这里
/// 给出，调用点只决定**圆角**（按各自形态：胶囊 / 条带）和里面的内容。
///
/// 之前底部胶囊自己写了一份 AppGlassSurface 的参数，三处吸顶条则各写各的
/// （渐变 / 兜底模糊）。参数一分散就会分家——所以这一轮把它们收成一处：
/// 只要写在这里的 scrim / thickness / chroma / blur / refractiveIndex 变了，
/// footer 与三处吸顶条同时变，不可能出现「footer 是玻璃、吸顶条还是另一套」
/// 的中间态（test/pinned_chrome_bar_test.dart 逐项对比三处与 footer）。
///
/// **刷新不换材质**：玻璃层挂着一个常量 key 的 RepaintBoundary
/// （[AppChromeGlassBar.layerKey]）+ 固定位置的 AppGlassSurface
/// （[AppChromeGlassBar.surfaceKey]），所以下拉刷新（列表重建、数据替换、
/// RefreshIndicator 动画）期间这几个 Element 一直是同一个，premium 的 capture
/// 不会在重建的瞬间抓到未完成帧——「刷新时整条发黑」的根因就是那一帧
/// （复现见 test/refresh_black_bar_test.dart）。
library;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LiquidGlassSettings;

import '../core/design/colors.dart';
import '../core/design/text_styles.dart';
import 'app_glass.dart';
import 'app_glass_tone.dart';

/// footer 未激活文字/图标那一档：字号。
///
/// 三处吸顶条里的文字（未选中的段 / 数量 / 日期）与 footer 的标签用**同一个
/// 数**：改字号只改这里，不会出现「footer 10.5、条带 13」这种各写一套。
const double kAppChromeLabelFontSize = 10.5;

/// footer 未激活文字那一档：行高。
const double kAppChromeLabelHeight = 1.1;

/// footer 未激活文字那一档：字重。
const FontWeight kAppChromeLabelWeight = FontWeight.w500;

/// 同色极轻描边的不透明度（上限 12%，再高就成发光字）。
const double kAppChromeHaloAlpha = 0.10;

/// 文字/图标的极轻描边：同色、10%、0 偏移 1px 模糊，不发光、不加底色。
List<Shadow> appChromeHalo(Color color) => [
      Shadow(
        color: color.withValues(alpha: kAppChromeHaloAlpha),
        blurRadius: 1,
      ),
    ];

/// **footer 未激活那一套文字**：字号 / 行高 / 字重逐项取自上面的常量，颜色由
/// 调用点给（未选中 = 自动墨色 appGlassToneInk，选中 = 主题色）。
///
/// 基样式仍是 AppText.caption（字族与度量都在它身上），所以 footer 与三处
/// 吸顶条的字形完全一致，只有颜色和描边不同。
TextStyle appChromeLabelStyle(Color color, {List<Shadow>? shadows}) =>
    AppText.caption.copyWith(
      fontSize: kAppChromeLabelFontSize,
      height: kAppChromeLabelHeight,
      fontWeight: kAppChromeLabelWeight,
      color: color,
      shadows: shadows,
    );

/// 玻璃条的模糊半径：**2**（= appGlassChromeBlur，premium 的最低档）。
///
/// 折射优先，模糊只负责抹掉像素噪点：scrim 让到 0.55 之后，剩下那 45% 正是
/// 给折射用的内容，糊大了斜面采样到的位移就被抹平。
const double appChromeBlur = appGlassChromeBlur;

/// 玻璃条 scrim 的不透明度：**0.55**（= 折射可见度 45%），与
/// appGlassChromeScrimAlphaLight / appGlassChromeScrimAlphaDark 同一组数。
double appChromeScrimAlpha() => appGlassChromeScrimAlpha();

/// 玻璃条 scrim 的颜色：页面底色 + [appChromeScrimAlpha]。
Color appChromeScrimColor() =>
    AppColors.bgPage.withValues(alpha: appChromeScrimAlpha());

/// 玻璃条的光学参数：premium 用 appGlassChromeSettings（thickness 32 /
/// refractiveIndex 1.38 / chromaticAberration 0.14 / saturation 1.3），拿不到
/// premium 时整块回退 appGlassSettings（磨砂），只把模糊钉成
/// [appChromeBlur]。
///
/// 档位判定与 AppGlassSurface 内部那条（appGlassPremiumAvailable）完全一致，
/// 所以这里取到的就是那个表面真正会用的参数，不会出现「scrim 按 premium 算、
/// 参数却按磨砂画」的半套中间态。
LiquidGlassSettings appChromeGlassSettings(BuildContext context) {
  final base = appGlassPremiumAvailable(context)
      ? appGlassChromeSettings(context)
      : appGlassSettings(context);
  return base.copyWith(blur: appChromeBlur);
}

/// 玻璃条内容共享的**自动墨色**：[AppChromeGlassBar] 按背景采样挑好颜色后从
/// 这个 scope 传下去。
///
/// 三处吸顶条的内容（分类条的四段）不是由玻璃条自己构建的——它是调用点传进来
/// 的 child，读不到 builder 的参数，于是用这层 scope 拿墨色。footer 那种由
/// builder 直接构建内容的调用点不需要它（标签由 builder 亲手创建）。
class AppChromeInk extends InheritedWidget {
  const AppChromeInk({super.key, required this.ink, required super.child});

  /// 当前该用的墨色（见 appGlassToneInk）。
  final Color ink;

  /// 子树里的墨色；不在 [AppChromeGlassBar] 里时返回 null（调用点据此走原来
  /// 那一套颜色，比如内容流里的非吸顶渐变条）。
  static Color? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppChromeInk>()?.ink;

  @override
  bool updateShouldNotify(AppChromeInk oldWidget) => oldWidget.ink != ink;
}

/// 一条**与底部 footer 完全相同**的悬浮玻璃条。
///
/// 只暴露两样东西：圆角 [radius]（按各自形态取：footer 与分类条是胶囊
/// = 高度/2，日期条是满宽条带 = 0）与内容 [builder]。其余参数一字不差——
/// [preferredQuality]（premium）、[usesOwnLayer]、scrim、参数与 scrim 色都只
/// 在这里出现一次。
///
/// **刷新不换材质**：[layerKey] 是常量 key 的 [RepaintBoundary]，[surfaceKey]
/// 挂在 [AppGlassSurface] 上。下拉刷新期间列表会重建，但这两个 key 与位置都不
/// 变，所以 Element 一直是同一个，玻璃按缓存图层重绘，不会重新抓 capture，也
/// 就没有「重建瞬间抓到空纹理 → 一块近黑」的那一帧（断言见
/// test/refresh_black_bar_test.dart）。
class AppChromeGlassBar extends StatelessWidget {
  const AppChromeGlassBar({
    super.key,
    required this.radius,
    required this.builder,
  });

  /// 胶囊想要的玻璃档位：premium（Impeller 全管线，折射/边缘扭曲）。
  ///
  /// 所有静态 chrome 都取这一个数，改档位只改这里（footer 的
  /// AppBottomTabBar.preferredQuality 就是它的别名）。
  static const GlassQuality preferredQuality = GlassQuality.premium;

  /// 玻璃条自建渲染层：premium 的 per-widget settings 只在自建层里生效。
  static const bool usesOwnLayer = true;

  /// 玻璃层的稳定 key：刷新全程是同一个 Element（见类文档）。
  static const Key layerKey = ValueKey<String>('app-chrome-glass-layer');

  /// 玻璃表面的稳定 key：同上，测试用它取 [AppGlassSurface] 的参数。
  static const Key surfaceKey = ValueKey<String>('app-chrome-glass-surface');

  /// 圆角：按各自形态取（胶囊 = 高度/2，条带 = 0）。
  final double radius;

  /// 内容：拿到当前该用的自动墨色 [ink]（见 appGlassToneInk）。
  final Widget Function(BuildContext context, Color ink) builder;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: layerKey,
      child: appGlassToneBuilder(
        (context, ink) => AppGlassSurface(
          key: surfaceKey,
          radius: radius,
          requestedQuality: preferredQuality,
          // 静态 chrome 优先 premium（折射）；拿不到时 AppGlassSurface 自己
          // 退回磨砂档 + 重 scrim，这里不用分支。
          preferPremium: true,
          useOwnLayer: usesOwnLayer,
          // 玻璃后面是滚动的内容（照片/卡片）：内部叠一层页面底色 scrim，
          // 未选中的文字才有稳定底衬。厚度不跟档位走（见
          // [appChromeScrimAlpha] = 0.55 = 折射可见度 45%）。
          scrim: true,
          settings: appChromeGlassSettings(context),
          scrimColor: appChromeScrimColor(),
          child: builder(context, ink),
        ),
      ),
    );
  }
}
