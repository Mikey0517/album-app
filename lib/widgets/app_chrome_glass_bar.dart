/// 一条与底部 footer **同一份材质**的悬浮玻璃条：三处吸顶条 + footer 共用这一份。
///
/// **一份材质，四个调用点**：底部 footer 胶囊（AppBottomTabBar）与三处吸顶
/// 悬浮条（朋友圈吸顶日期条、相册吸顶分类行 + 日期行）都走
/// [AppChromeGlassBar]。scrim、档位、自建层、模糊、tint、光照、边缘吸收
/// 全部由这里给出，调用点只决定**圆角**（按各自形态：胶囊 / 条带）和里面的内容。
///
/// **唯一的差别是折射数**：[AppChromeGlassBar.pinned] 的三处吸顶条比 footer
/// 深一档（thickness 44 / 折射率 1.75 / 色散 0.32，见 app_glass.dart 的
/// appGlassPinnedSettings；footer 仍是 36 / 1.55 / 0.22）。直边条没有胶囊
/// 圆角把位移挤回条内，所以能再深一档；scrim 与模糊两处仍完全相同，
/// 文字对比度与「刷新不变色」不受影响。
///
/// **相册页是「一块玻璃、两行」**：分类行与日期行不再各自带玻璃上下堆叠
/// （那会在两行之间留一条接缝），而是同时塞进同一个 [AppChromeGlassBar.pinned]
/// 的 [children] 里（见 AlbumPinnedChromeSliver）。行自己从 [AppChromeInk]
/// 取墨色，材质仍是别处那唯一一份。
///
/// 之前底部胶囊自己写了一份 AppGlassSurface 的参数，三处吸顶条则各写各的
/// （渐变 / 兜底模糊）。参数一分散就会分家——所以这里把它们收成一处：scrim /
/// 模糊 / 档位 / 光照只有一份，折射那三个数只有两组（footer 一组、吸顶条
/// 一组），逐项钉在 test/pinned_chrome_bar_test.dart（哪几项必须相等、哪几项
/// 必须不同）。
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

/// 三处**吸顶悬浮条**共用的圆角：**0**（直边条）。
///
/// 圆角按形态只有两档：footer 胶囊取 AppBottomTabBar.radius（高度/2），
/// 三处吸顶条一律取这个数。吸顶条横贯整屏，四角留圆弧会在屏幕左右两边露出
/// 后面的照片（看着像一枚飘着的胶囊），也留出侧边空隙——所以吸顶条是直边、
/// 贴住页面左右边缘。三处的半径只有这一个来源，不各写一个 0。
const double kAppChromePinnedRadius = 0;

/// 三处**吸顶悬浮条**玻璃下面那层固定底衬的不透明度：**0.9**。
///
/// 吸顶条底下是滚动的照片/卡片，玻璃的 scrim 只压 55%——剩下 45% 的背景权重
/// 会让条带的合成色跟着滚过的内容漂，下拉刷新那几帧最明显（「吸顶日期条会
/// 变色」）。这层「页面底色 + 0.9」把可漂移权重压到 (1 − 0.9) × 45% ≈ 4.5%，
/// 合成色基本钉死；玻璃本体（折射/模糊/scrim）仍原样在它上面，Element 不重建。
///
/// 取 0.9 而不是更高：再往上（≥0.97）才能把「纯黑照片 ↔ 纯白照片」这种极端
/// 背景也压到 3/255 以内，那时吸顶条已经等于一块不透明的页面底色，玻璃也就
/// 没了。0.9 在真实背景（页面底色 ↔ 卡片白）之间只剩不到 1/255 的漂移，照片
/// 那一档也从 115/255 收到 ~11/255。footer 不画这层底衬（backplateAlpha 默认
/// 0），观感一点不变。
const double kAppChromePinnedBackplateAlpha = 0.9;

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

/// 玻璃条的光学参数：premium 时按 [pinned] 二选一——
/// - footer 等多选底栏 / 上传按钮：appGlassChromeSettings（thickness 36 /
///   refractiveIndex 1.55 / chromaticAberration 0.22 / saturation 1.3）；
/// - 三处吸顶悬浮条：appGlassPinnedSettings（44 / 1.75 / 0.32），**只差这三个
///   折射数**，scrim / 模糊 / tint / 光照 / 边缘吸收仍是同一份。
///
/// 拿不到 premium 时两者都整块回退 appGlassSettings（磨砂），只把模糊钉成
/// [appChromeBlur]。档位判定与 AppGlassSurface 内部那条
/// （appGlassPremiumAvailable）完全一致，所以这里取到的就是那个表面真正会用
/// 的参数，不会出现「scrim 按 premium 算、参数却按磨砂画」的半套中间态。
LiquidGlassSettings appChromeGlassSettings(
  BuildContext context, {
  bool pinned = false,
}) {
  final base = !appGlassPremiumAvailable(context)
      ? appGlassSettings(context)
      : pinned
          ? appGlassPinnedSettings(context)
          : appGlassChromeSettings(context);
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

/// 一条**与底部 footer 共用同一份玻璃**的悬浮条。
///
/// 暴露四样东西：圆角 [radius]（footer 胶囊 = 高度/2，三处吸顶条 =
/// [kAppChromePinnedRadius] = 0）、描边 [showBorder]、内高光 [showHighlight]
/// 与固定底衬 [backplateAlpha]（footer 是 true / true / 0，三处吸顶条反过来，
/// 见 [AppChromeGlassBar.pinned]），以及内容（单行 [builder] 或**多行**
/// [children]）。其余参数一字不差——[preferredQuality]（premium）、
/// [usesOwnLayer]、scrim、模糊与 scrim 色都只在这里出现一次；折射三数只有
/// 两组（footer 一组、吸顶条一组，见 [pinned]）。
///
/// **footer 与吸顶条的差别只有「形状 + 那两层装饰 + 折射那一档」**：
/// - footer：胶囊，圆角 28，有 1px 描边与顶部内高光，折射 36 / 1.55 / 0.22；
/// - 三处吸顶条：直边条，圆角 0，**没有描边、没有内高光**，只剩玻璃本体 +
///   scrim（+ 阴影，若有），折射 44 / 1.75 / 0.32。吸顶条横贯整屏，贴在页面
///   左右边缘上：直边才不留侧边空隙，去掉上下两道线才不会把条带和页面切成
///   两块。
/// scrim（0.55）、模糊（2）、档位、tint、光照仍是同一份，不会因为这几处差异
/// 分家。
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
    this.showBorder = true,
    this.showHighlight = true,
    this.backplateAlpha = 0,
    required this.builder,
  })  : children = const <Widget>[],
        pinned = false,
        assert(backplateAlpha >= 0 && backplateAlpha <= 1);

  /// **三处吸顶悬浮条的唯一构造方式**：直边（[kAppChromePinnedRadius]）、
  /// 不要描边、不要内高光、玻璃下面加一层固定底衬、折射取更深的那一档
  /// （[pinned] = true → appGlassPinnedSettings）。
  ///
  /// 这五样由构造器写死，调用点不用（也不可能漏）逐个传——三个调用点各传
  /// 一遍 radius: 0 / showBorder: false / showHighlight: false /
  /// backplateAlpha: 0.9 / 折射那一档 迟早会漏一个，而漏掉的那一个正好是
  /// 「吸顶条看着跟另外两条不一样」。footer 用默认构造：胶囊 + 描边 + 内高光
  /// + 无底衬 + footer 的那一档折射。
  ///
  /// 内容两种给法（二选一，构造器里有断言）：
  /// - [builder]：**单行**，朋友圈吸顶日期条这一种；
  /// - [children]：**多行**，相册吸顶区（分类行 + 日期行）这一种——两行在
  ///   同一块玻璃里，中间不存在第二条底衬/描边，接缝从结构上就没有。
  const AppChromeGlassBar.pinned({
    super.key,
    this.radius = kAppChromePinnedRadius,
    this.builder,
    this.children = const <Widget>[],
  })  : pinned = true,
        showBorder = false,
        showHighlight = false,
        backplateAlpha = kAppChromePinnedBackplateAlpha,
        assert(
          (builder == null) != (children.length == 0),
          '内容只有一种给法：要么 builder（单行，自己构建），要么 children（多行）',
        );

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

  /// 圆角：按各自形态取（胶囊 = 高度/2，吸顶条 = [kAppChromePinnedRadius] = 0）。
  final double radius;

  /// 是否画那圈 1px 半透明描边（玻璃分支是前景描边，退化分支是细边）。
  ///
  /// 默认 true 给 footer 用；[AppChromeGlassBar.pinned] 把它设成 false——
  /// 直边条上下各一道线，会把玻璃和页面切成两块（见类文档）。布局尺寸完全不变。
  final bool showBorder;

  /// 是否画顶部内高光层。
  ///
  /// 默认 true 给 footer 用；[AppChromeGlassBar.pinned] 把它设成 false——
  /// 条带只留玻璃本体 + 阴影，不再叠一道白色横杠。
  final bool showHighlight;

  /// 是不是**吸顶悬浮条**那一档折射（footer 为 false）。
  ///
  /// true 由 [AppChromeGlassBar.pinned] 写死，调用点不传。唯一的差别是
  /// [appChromeGlassSettings] 取哪一组数：吸顶条走 appGlassPinnedSettings
  /// （thickness 44 / 折射率 1.75 / 色散 0.32），footer 走
  /// appGlassChromeSettings（36 / 1.55 / 0.22）。scrim、模糊、tint、光照、
  /// 固定底衬的接线与开关**一个都没分家**，所以两处的文字对比度、
  /// 刷新不变色仍由同一套机制保证（见 test/pinned_chrome_bar_test.dart）。
  final bool pinned;

  /// 玻璃下面那层固定底衬的不透明度：0 = 不画（footer 默认）。
  ///
  /// 三处吸顶条取 [kAppChromePinnedBackplateAlpha]（见那里的推算），把「背后
  /// 内容在动 → 条带变色」这件事从合成色里挤出去。
  final double backplateAlpha;

  /// 单行内容：拿到当前该用的自动墨色 [ink]（见 appGlassToneInk）。
  ///
  /// 只有 [AppChromeGlassBar.pinned] 允许不传它（改传 [children]）。
  final Widget Function(BuildContext context, Color ink)? builder;

  /// **多行内容**：一块玻璃里上下排几行，每行自己从 [AppChromeInk] 取墨色。
  ///
  /// 为什么要这个：相册页的吸顶区要同时放「分类行 + 日期行」，两行必须在
  /// **同一块玻璃**里——分成两条各自带玻璃的吸顶 sliver 上下堆叠，两行之间
  /// 就会露出一条接缝（两条玻璃的底衬/描边叠在一起）。这里把多行塞进同一个
  /// [AppGlassSurface]，接缝从结构上就不存在（见 AlbumPinnedChromeSliver）。
  ///
  /// 行自己读墨色的机制与三处单行条一致：[AppChromeInk] 由这一层放进 scope，
  /// 行里的 [AppSegmentedBarSurface] / [DateHeader] 会自己取（见各自的 build）。
  final List<Widget> children;

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
          settings: appChromeGlassSettings(context, pinned: pinned),
          scrimColor: appChromeScrimColor(),
          // 描边与内高光由调用点决定：footer 两样都要（默认），三处吸顶条
          // 两样都不要（直边条 + 玻璃本体 + 阴影）。
          showBorder: showBorder,
          showHighlight: showHighlight,
          // 固定底衬：0 = 不画。三处吸顶条传 0.9，footer 不画。
          backplate: backplateAlpha <= 0
              ? null
              : AppColors.bgPage.withValues(alpha: backplateAlpha),
          child: _content(context, ink),
        ),
      ),
    );
  }

  /// 玻璃里的内容：单行（[builder]）或**多行**（[children]，包一层
  /// [AppChromeInk] 让每行自己取墨色）。
  Widget _content(BuildContext context, Color ink) {
    final build = builder;
    if (build != null) return build(context, ink);
    return AppChromeInk(
      ink: ink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
