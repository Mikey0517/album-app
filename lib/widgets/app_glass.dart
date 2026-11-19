import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, ValueListenable;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../core/design/accent.dart';
import '../core/design/colors.dart';
import '../core/design/shadow.dart';
import '../core/page_backdrop_controller.dart';
import '../core/page_backdrop_spec.dart';

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
/// 2. 上限是 [GlassQuality.minimal] —— 只有平台压根不支持 shader 时才会
///    出现（见 [appGlassStaticQuality]），不再有运行时降档；
/// 3. 调用点自己要求 minimal。
///
/// [requested] 是调用点想要的档位：现在**只有静态 chrome（底部胶囊）**要
/// premium；卡片 / 列表项 / 新建相册按钮固定在 standard（见
/// [AppGlassSurface.kCardQuality]）。
///
/// 卡片为什么不许要 premium：premium 是「全管线」路径，形状遮罩与背景都靠
/// capture（toImageSync / BackdropGroup）。滚动列表某次重建（下拉刷新、数据
/// 替换、滚出缓存区）会换掉玻璃层，新层在 capture 还没就绪的那一帧照样画一遍，
/// 采到空纹理就是一块近黑——真机上的「下拉刷新黑卡」。standard 只做
/// BackdropFilter，不抓 capture，没有这一帧。
///
/// [requested] 只是「想要」：[AppGlassScope] 注入的档位才是「上限」，取两者
/// 更低的那个。所以注入 premium 也不会把要 standard 的卡片顶成 premium；
/// 但上限本身是**静态**的（[appGlassRoot]），不会因为掉帧/刷新被按下去
/// （包里 GlassThemeHelpers.resolveQuality 对显式 quality 同样按上限封顶，
/// 这里先算一遍是为了让本文件的参数/scrim 分支与真正的档位始终一致）。
GlassQuality? glassQualityFor(
  BuildContext context, {
  GlassQuality? requested,
}) {
  final injected = AppGlassScope.qualityOf(context);
  // 只认注入的静态档位。就算树里还有别处塞进来的 [GlassAdaptiveScope]（旧版
  // wrap / 第三方页面），也不再拿它的 effectiveQuality 当上限——档位不许随
  // 帧耗时变化。测试里那条「注入 minimal」的钩子仍然走 [AppGlassScope]。
  final cap = injected;
  // 没有档位来源 = 玻璃不可用：不画。
  if (cap == null) return null;
  if (cap == GlassQuality.minimal) return null;
  final quality = _lowerQuality(requested, cap);
  if (quality == null || quality == GlassQuality.minimal) return null;
  return quality;
}

/// 两档里更低的那一个（null 表示「没意见」）。
///
/// 不能比 enum 下标：GlassQuality 的顺序是 standard / premium / minimal，
/// 质量高低不是 index 单调的，所以这里显式排一次。
GlassQuality? _lowerQuality(GlassQuality? a, GlassQuality? b) {
  int rank(GlassQuality quality) => switch (quality) {
        GlassQuality.premium => 2,
        GlassQuality.standard => 1,
        GlassQuality.minimal => 0,
      };
  if (a == null) return b;
  if (b == null) return a;
  return rank(a) <= rank(b) ? a : b;
}

/// premium 档在**平台层面**的前置条件。
///
/// premium 走的是 Impeller 的全管线 shader（每帧 toImageSync 抓纹理再做视差
/// 折射），要靠 shader filter 才成立：Web 与「引擎不支持 shader filter」的
/// 软件光栅器上它没有意义。包的 GlassAdaptiveScope 在冷启动探测阶段也会把这类
/// 设备直接压到 minimal，两条路指向同一个结论。
bool get appGlassPremiumPlatformSupported =>
    !kIsWeb && ui.ImageFilter.isShaderFilterSupported;

/// 这台机器的**静态**玻璃档位：启动时按平台能力判一次，之后再也不变。
///
/// 用户要求「不要让材质回退」，所以档位不再来自随帧率升降的
/// [GlassAdaptiveScope]（见 [appGlassRoot]），只剩这一条静态判定：
/// - shader filter 都不支持（软件光栅器 / 坏驱动）→ [GlassQuality.minimal]：
///   连磨砂 shader 都跑不起来，只能画不透明表面；
/// - 平台把 premium 封顶（Web / Windows / Linux）→ [GlassQuality.standard]：
///   退回磨砂档，玻璃还在；
/// - 其余（Impeller + shader）→ [GlassQuality.premium]。
///
/// 结论：只有「平台根本不支持」才退，和掉帧/刷新/过热无关。
GlassQuality appGlassStaticQuality() => appGlassStaticQualityFor(
      shaderFilterSupported: ui.ImageFilter.isShaderFilterSupported,
      premiumCappedPlatform: kIsWeb ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux,
    );

/// [appGlassStaticQuality] 的纯函数内核，便于逐条断言。
///
/// 判定顺序固定：**先看 shader 有没有，再看平台封不封 premium**。
/// 两者都是静态事实，没有任何时间/性能输入——这正是「不会自动降档」的保证。
GlassQuality appGlassStaticQualityFor({
  required bool shaderFilterSupported,
  required bool premiumCappedPlatform,
}) {
  if (!shaderFilterSupported) return GlassQuality.minimal;
  if (premiumCappedPlatform) return GlassQuality.standard;
  return GlassQuality.premium;
}

/// App 根节点：注入**静态**档位，并初始化过的玻璃运行时。
///
/// 与旧版 `LiquidGlassWidgets.wrap(adaptiveQuality: true)` 的差别只有一条，
/// 但正是问题 A 的根因：旧版会插入一个根 [GlassAdaptiveScope]，它在 P95 光栅
/// 耗时超过帧预算 1.5 倍（16ms → 24ms）、连续 2 个窗口（每窗 120 帧 ≈ 2 秒）后
/// 把 premium 按到 standard/minimal，而回升要 10 个连续达标窗口（P95 < 9.6ms）
/// 加 8 秒冷却——下拉刷新掉几帧就够跨过降档门槛，且降下去几十秒回不来，
/// 真机表现就是「刷一下就退回磨砂」。
///
/// 现在：
/// - `adaptiveQuality: false`：不再插入任何会自己升降档的 scope；
/// - [appGlassStaticQuality] 把档位钉死（premium / standard / minimal 三选一），
///   通过 [AppGlassScope] 注入整棵树，[glassQualityFor] 拿它当上限；
/// - 包内 Per-widget 的显式 quality 在没有 [GlassAdaptiveScope] 时原样生效
///   （`GlassThemeHelpers.resolveQuality`：没有 adaptive 数据就直接返回显式值）。
/// [quality] 是给测试用的：默认走静态判定，测试里可以钉成 premium 来断言
/// 「跑多少慢帧都不降档」，不受跑测试那台机器的 shader 能力影响。
Widget appGlassRoot(Widget child, {GlassQuality? quality}) => AppGlassScope(
      quality: quality ?? appGlassStaticQuality(),
      child: LiquidGlassWidgets.wrap(
        child: child,
        // 关掉自适应降档：档位不许随帧耗时变化。
        adaptiveQuality: false,
        // 玻璃控件零 material 依赖，深色模式要靠这个回调感知 ThemeMode。
        brightnessResolver: Theme.maybeBrightnessOf,
      ),
    );

/// 下拉刷新期间的「玻璃暂停」开关。
///
/// 刷新这几百毫秒里列表整体重建、RefreshIndicator 还会在列表上方叠一层动画，
/// 玻璃采样的 backdrop 在这几帧里不稳定。与其猜哪一帧是坏的，不如在这段时间
/// 把卡片换成**同色不透明表面**：颜色 / 圆角 / 内外边距都不变，只是不画玻璃。
/// 刷新一结束立刻回到玻璃——档位本身从未改变，变的只是这几帧画什么。
///
/// 这是**第二层保险**：黑卡的根因（premium 的 capture 未就绪帧）已经由
/// [AppGlassSurface.kCardQuality] = standard 拆掉了，刷新保持只是让这几帧连
/// BackdropFilter 都不做，理论上更稳。
///
/// 影响所有非静态 chrome 的玻璃表面（[AppGlassSurface.pauseDuringRefresh]）；
/// 底部胶囊这类静态 chrome 不受影响。开关由 [appGlassWhileRefreshing] 包住
/// 一次刷新任务来驱动（feed / 相册页的 RefreshIndicator.onRefresh 都走它）。
class AppGlassRefreshHold {
  AppGlassRefreshHold._();

  static final ValueNotifier<bool> _active = ValueNotifier<bool>(false);

  /// 当前是否处于刷新保持中（[AppGlassSurface] 监听它重建）。
  static ValueListenable<bool> get active => _active;

  static bool get isActive => _active.value;

  /// 进入刷新保持：卡片换成不透明表面。
  static void begin() => _active.value = true;

  /// 退出刷新保持：卡片回到 premium。
  static void end() => _active.value = false;

  /// 测试用：把开关恢复成「不在刷新」，避免用例之间串味。
  @visibleForTesting
  static void reset() => _active.value = false;
}

/// 跑一次刷新任务，期间 [AppGlassRefreshHold] 全程生效。
///
/// 用法：`onRefresh: () => appGlassWhileRefreshing(() => _load(refresh: true))`。
/// `finally` 里释放：请求抛异常、页面提前 dispose 都不会把卡片钉在不透明面上。
///
/// 为什么不用 RefreshIndicator.onStatusChange：Flutter 3.41 里那个回调只挂在
/// `RefreshIndicator.noSpinner` 构造上，默认构造没有。而真正会抖的窗口就是
/// onRefresh 这一段时间（列表重建 + 数据回来那一帧），从这里掐住刚好。
Future<T> appGlassWhileRefreshing<T>(Future<T> Function() task) async {
  AppGlassRefreshHold.begin();
  try {
    return await task();
  } finally {
    AppGlassRefreshHold.end();
  }
}

/// 这一处玻璃能不能真的用 premium 档（折射/边缘扭曲）。
///
/// 两个输入按优先级：
/// 1. [AppGlassScope] 注入的静态档位（[appGlassRoot] 装的那个 / 测试钩子）
///    ——注入什么就是什么上限；
/// 2. [platformSupported]（默认 [appGlassPremiumPlatformSupported]）。
///
/// 不再读 [GlassAdaptiveScopeData]：运行期降档那条路已经关掉了，档位只由
/// [appGlassStaticQuality] 决定。返回 false 时调用点必须走原来的磨砂实现
/// （[appGlassSettings] + 42%/50% scrim），不允许留下「半套 premium 参数」的
/// 白板：见 [AppGlassSurface]。
bool appGlassPremiumAvailable(
  BuildContext context, {
  bool? platformSupported,
}) =>
    appGlassPremiumDecision(
      injected: AppGlassScope.qualityOf(context),
      ceiling: null,
      platformSupported: platformSupported ?? appGlassPremiumPlatformSupported,
    );

/// [appGlassPremiumAvailable] 的纯函数内核：把三个输入摊平，便于逐条断言。
///
/// 顺序固定：注入 > 自适应上限 > 平台能力。
/// - 注入非 null 就是「模拟这台机器的上限」，不再看平台（测试钩子）；
/// - 没有注入时，自适应上限必须是 premium（降到 standard/minimal 就是降档）；
/// - 上限到了 premium 还要平台真的支持（Web / 软件光栅器上没有 premium）。
bool appGlassPremiumDecision({
  required GlassQuality? injected,
  required GlassQuality? ceiling,
  required bool platformSupported,
}) {
  if (injected != null) return injected == GlassQuality.premium;
  if (ceiling != GlassQuality.premium) return false;
  return platformSupported;
}

/// 玻璃自己的 tint（[appGlassSettings] 里的 glassColor）：浅色 15% 的冷白，
/// 深色 10% 的白。
///
/// 单独抽出来是为了让「玻璃底衬有多亮」只有一个数——对比度计算与 shader 用
/// 同一份取值，不再各写一遍。
///
/// 取值比早期版本（23% / 17%）低一档：这一档只给「透」的表面用（浮层与
/// chrome 回退），底色由背后的渐变/背景图自己给，玻璃只负责一层极淡的冷调
/// 与高光。**卡片不用它**：卡片的磨砂 tint 是 [appCardFrostTintColor]
/// （84%/86% 的白雾）。卡片正文用的是 [AppColors.textPrimary]，对这块底衬的
/// 对比度 > 15:1；tint 压低只会让底衬更接近页面底色，文字不会更难读
/// （底部胶囊另有 scrim，见 [appGlassScrimBackplate]）。
Color get appGlassTintColor =>
    AppColors.isDark ? const Color(0x1AFFFFFF) : const Color(0x26D2DCF0);

/// **非卡片** standard 表面的光学参数：轻磨砂、仍偏「透」。
///
/// 只用在两处：显式要 standard 的浮层（强制更新弹窗），以及 premium 拿不到
/// （[appGlassPremiumAvailable] 为假）时静态 chrome 的整块回退。
///
/// **卡片 / 列表不走这一套**：它们要的是「白雾磨砂、不要玻璃透亮感」，见
/// [appCardFrostSettings]（blur 8 / tint 84%~86% / 折射归零）。
///
/// 为什么不用包的 classic 预设：classic 的 tint 只有 12% 白蓝、模糊 5，落在
/// 纯色页面上「模糊纯色还是纯色」，整块玻璃只剩一点透明度。这里模糊提到 8
/// 让表面有一点点磨砂质地，但 tint 压到 15%（深色 10%）、saturation 提到
/// 1.35、lightIntensity 提到 1.0（深色 0.9），把「透亮」交给高光与饱和度，
/// 而不是靠一层白雾。描边和顶部内高光再由 [AppGlassSurface] 叠一层。
LiquidGlassSettings appGlassSettings(BuildContext context) {
  final dark = AppColors.isDark;
  return LiquidGlassSettings(
    thickness: 12,
    blur: 8,
    glassColor: appGlassTintColor,
    lightAngle: 2.356,
    lightIntensity: dark ? 0.9 : 1.0,
    ambientStrength: dark ? 0.0 : 0.15,
    refractiveIndex: 1.2,
    saturation: 1.35,
    chromaticAberration: dark ? 0.02 : 0.03,
  );
}

/// 卡片的磨砂 tint：**接近实色的白雾**，颜色不随背后的内容漂。
///
/// 浅色 84% 的 [AppColors.bgSurface]（浅色就是纯白）、深色 86% 的
/// [AppColors.bgSurface]（#171B24，比页面底色亮一点）。
///
/// **为什么从 37%/48% 提到 84%/86%（下拉刷新时卡片变色）**：磨砂卡片的合成
/// 是「模糊后的 backdrop × (1 − tintAlpha) + tint」。tint 37% 时背后内容占
/// 63%，卡片颜色就等于背景的 0.63 倍振幅。下拉刷新那几帧列表被拉伸/位移
/// （BouncingScrollPhysics 下卡片整体下移 50~60 逻辑像素），玻璃采到的背景
/// 跟着换了一段，卡片亮度就跟着跳——用户看到的就是「刷新时卡片明显变色」。
/// 逐帧像素采样（见 test/feed_refresh_color_test.dart）在强对比背景上量到
/// 37% 时最大通道差 8/255，84% 时降到 2/255，与 (1 − alpha) 的比例对得上
/// （0.16 / 0.63 ≈ 1/4）。
///
/// 为什么不选「冻结 backdrop」（方案 a）：标准档的模糊是 BackdropFilter 现采
/// 现糊，冻结要另存一张快照图层，滚动列表里每张卡片都得维护自己的快照与失效
/// 时机，代价远高于把一层雾加厚；而「白雾」本来就是产品要的样子，加厚不影响
/// 观感。方案 c（刷新期间叠同色蒙版）只在刷新那几秒生效，滚动时该漂还是漂。
///
/// 为什么按 alpha 直接合成而不是包的 adaptive（luminance-preserving）：
/// adaptive 只取 tint 的色相、把亮度还给背景，白 tint 根本不「加白」，卡片
/// 还是透的；磨砂要的正是「提亮/压暗背景」这件事本身，所以
/// [appCardFrostSettings] 里把 [LiquidGlassSettings.bodyMode] 设成
/// [GlassBodyMode.clear]（按 alpha 精确合成，跨档位一致）。
const double appCardFrostTintAlphaLight = 0.84;
const double appCardFrostTintAlphaDark = 0.86;

/// 当前明暗模式下卡片的磨砂 tint。
Color get appCardFrostTintColor => AppColors.bgSurface.withValues(
      alpha: AppColors.isDark
          ? appCardFrostTintAlphaDark
          : appCardFrostTintAlphaLight,
    );

/// 卡片磨砂的模糊半径：**极轻**（8）。
///
/// tint 提到 84%/86% 之后，backdrop 只剩 14%~16% 的权重，模糊再大也只能在
/// 这 14% 里揉——实测把 20 降到 8，卡片像素差 ≤ 1/255（见
/// test/feed_refresh_color_test.dart 的「模糊半径不影响成品颜色」用例）。
/// 模糊半径只影响成本，不影响观感，所以取小的那一档。
const double appCardFrostBlur = 8;

/// 卡片 / 列表项的磨砂参数：**白雾**优先，不做玻璃。
///
/// 与 [appGlassSettings]（轻磨砂、透）的差别就是用户说的「不要玻璃透亮感」：
/// - blur 8 → [appCardFrostBlur]（8）：模糊只作用在剩下那 14%/16% 上；
/// - tint 15%/10% → [appCardFrostTintColor]（84%/86%）：一层接近实色的白雾，
///   卡片的底色不再随背后的内容跳（下拉刷新那几帧也不跳）；
/// - [LiquidGlassSettings.bodyMode] = [GlassBodyMode.clear]：按 alpha 精确
///   合成这层雾（adaptive 会把亮度还给背景，白雾等于没加）；
/// - lightIntensity 压到 0.65/0.55、ambientStrength 0：表面不再反光，立体感
///   交给双层阴影（[AppShadow.card]）与 1px 描边；
/// - refractiveIndex 1.0 + chromaticAberration 0：卡片本来就不走 premium，
///   边缘不做位移/色散，只留一层平面的雾。
///
/// 描边与高光仍由 [AppGlassSurface.depth]（[AppSurfaceDepth]）叠：高光压到
/// [appCardHighlightAlpha]（6%）这一档，几乎只是一条极淡的过渡。
LiquidGlassSettings appCardFrostSettings(BuildContext context) {
  final dark = AppColors.isDark;
  return LiquidGlassSettings(
    thickness: 12,
    blur: appCardFrostBlur,
    glassColor: appCardFrostTintColor,
    bodyMode: GlassBodyMode.clear,
    lightAngle: 2.356,
    lightIntensity: dark ? 0.55 : 0.65,
    ambientStrength: 0.0,
    refractiveIndex: 1.0,
    saturation: 1.15,
    chromaticAberration: 0.0,
  );
}

/// chrome 的斜面厚度：**36**（磨砂档是 12）。
///
/// 斜面越深，边缘的 displacement 越大——胶囊的两条长边和圆角能把底下的内容
/// 推歪，这才是「玻璃」而不是「毛玻璃」。上一轮是 32：scrim 0.55 之后背后有
/// 45% 的内容可弯，斜面还能再深一档，边缘的位移才真的看得出来。再往上加之前
/// 先看 footer 的对比度断言（test/footer_contrast_test.dart）：斜面只影响边缘，
/// 不参与底衬亮度，但边缘越深，文字落点附近的折射越活跃。
///
/// **三处吸顶条不取这个数**：它们用更深的一档 [appGlassPinnedThickness]=44
/// （直边条，没有胶囊圆角那一圈顾虑）。
const double appGlassChromeThickness = 36;

/// chrome 的模糊半径：**2**（磨砂档是 8）。
///
/// 折射优先，模糊只负责抹掉像素噪点。上一轮是 3，配合的是「背后只剩 24%」的
/// 重 scrim；scrim 让到 0.55 之后那 45% 正是给折射用的，模糊压到最低档。
const double appGlassChromeBlur = 2;

/// chrome 的折射率：**1.55**（磨砂档是 1.2）。
///
/// 折射率越高，斜面处的弯折越明显。上一轮 1.38 只是「比磨砂高一点」；这一轮
/// 与 36 的斜面、0.22 的色散一起再上一档，边缘的扭曲/彩色分离才是用户要求的
/// 「看得出是玻璃」。
///
/// 吸顶条另有更深的一档 [appGlassPinnedRefractiveIndex]=1.75。
const double appGlassChromeRefractiveIndex = 1.55;

/// chrome 的色散强度：**0.22**（上一轮 0.14）。
///
/// premium 的 dispersion，边缘那一圈彩色分离。折射可见度只有 45% 时，色散是
/// 「这块是玻璃」最容易被眼睛抓住的那条线索，所以再往上加一档：0.22 是在
/// 1.55 的折射率上刚好不糊成彩虹边的强度（再高边缘会开始发脏）。
///
/// 吸顶条另有 [appGlassPinnedChromaticAberration]=0.32。
const double appGlassChromeChromaticAberration = 0.22;

/// chrome 的饱和度：**1.3**。把折射采进来的背景色稍微提纯，玻璃才「亮」。
const double appGlassChromeSaturation = 1.3;

/// premium 档的光学参数：**折射**优先。底部胶囊 / 多选底栏 / 圆形上传按钮
/// 用它（见 [AppGlassSurface.preferPremium]；chrome 的具体接线见
/// app_chrome_glass_bar.dart 的 AppChromeGlassBar）——卡片走 standard，见
/// [AppGlassSurface.kCardQuality] 里「premium 会抓 capture，列表重建时会黑」。
/// 非吸顶的页内筛选条与内容流日期条不包玻璃（渐变 / 透明，见 BarTint）。
///
/// **三处吸顶悬浮条不取这一组**：它们另有一档更深的折射数
/// （[appGlassPinnedSettings]，44 / 1.75 / 0.32）；这里这一组仍是 footer 的
/// 那一组（36 / 1.55 / 0.22），除了折射三数之外两者完全共用。
///
/// 和 [appGlassSettings] 的差别都在「折射能不能看出来」这件事上：
/// - thickness [appGlassChromeThickness]：斜面越深，边缘的 displacement 越大；
/// - refractiveIndex [appGlassChromeRefractiveIndex]、
///   chromaticAberration [appGlassChromeChromaticAberration]：折射率越高弯折
///   越明显，色散让边缘出现一圈彩色描边（premium 的 dispersion）；
/// - blur [appGlassChromeBlur]：模糊压到最低，折射才不会被糊掉；
/// - glassColor 比磨砂更淡（[appGlassChromeTintColor]）：premium 表面自己
///   已经会采背景色，再叠一层 tint 就回到磨砂；
/// - lightIntensity 1.0 + rimShade/rimLight：一圈更亮的高光边。
///
/// **这一组数与 [appGlassChromeScrimAlphaLight] = 0.55 是一对**：scrim 让到
/// 55% 之后，背后只剩 45% 的权重给折射，斜面/色散不加大、模糊不压低，那 45%
/// 就是一块「更亮的灰板」而不是折射。这一轮的组合是 36 / 1.55 / 0.22 / blur 2
/// （上一轮 32 / 1.38 / 0.14，再上一轮 28 / 0.10 / blur 3 + scrim 0.76~0.82）：
/// 回退时三个数要一起改，scrim 与 blur 不动——折射可见度 45% 是这一组的基准，
/// 改了它 footer 的文字对比度就跟着回退（见 [appGlassChromeScrimAlphaLight]）。
///
/// 只在 [appGlassPremiumAvailable] 为真时使用；不可用时整块退回
/// [appGlassSettings]（磨砂）那一套。
LiquidGlassSettings appGlassChromeSettings(BuildContext context) =>
    _appGlassPremiumChrome(
      context,
      thickness: appGlassChromeThickness,
      refractiveIndex: appGlassChromeRefractiveIndex,
      chromaticAberration: appGlassChromeChromaticAberration,
    );

/// **吸顶悬浮条**的斜面厚度：**44**（footer / 多选底栏 / 上传按钮仍是 36）。
///
/// 斜面越深，边缘的 displacement 越大。吸顶条可以比 footer 再深一档，是因为
/// 它横贯整屏、直边（[kAppChromePinnedRadius] = 0）：斜面只落在上下两条长边
/// 上，不会像胶囊那样在半径 28 的圆角上把位移、描边、内高光挤成一圈。
///
/// **直边下 44 会不会出现上下暗边**：不会。
/// - 包内的斜面宽度按物理像素计、再按 dpr/3 折算，所以**逻辑宽度 =
///   thickness / 3**（与 dpr 无关）：36 → 12 lp，44 → 14.7 lp。最矮的一条是
///   朋友圈吸顶日期条（36 lp 高），上下各 14.7 lp 之后中间仍留 6.7 lp 的平台
///   面——两条斜面不会在中间相遇，也就没有「上下暗边叠成一条」。
/// - 真正会发暗的是边缘吸收（[LiquidGlassSettings.edgeAbsorption] 0.12，最深处
///   对背景压 ~17%），它的剖面只在斜面**外侧 18%** 上（44 → ~2.7 lp，36 →
///   ~2.2 lp），是两条细边而不是两条带；而且吸顶条在玻璃之上还铺了一层 0.9 的
///   页面底色底衬（[kAppChromePinnedBackplateAlpha]），这层暗边到屏幕只剩
///   ≤1.7% 的亮度差。
/// 所以厚度加到 44 不需要在 [LiquidGlassSettings.edgeAbsorption] /
/// [LiquidGlassSettings.lightIntensity] 上做补偿，光照那一组仍与 footer 相同。
const double appGlassPinnedThickness = 44;

/// **吸顶悬浮条**的折射率：**1.75**（footer 1.55）。
///
/// 折射率越高，斜面处的弯折越明显。footer 停在 1.55 是因为胶囊的两端圆角上
/// 弯折会先糊成彩边；吸顶条是直边，同样的折射率在上下两条长边上只表现为
/// 「底下的照片被推开一点」，所以可以再上一档。
const double appGlassPinnedRefractiveIndex = 1.75;

/// **吸顶悬浮条**的色散强度：**0.32**（footer 0.22）。
///
/// 色散是「这块是玻璃」最容易被眼睛抓住的线索。吸顶条比 footer 深一档的斜面
/// 与折射率配 0.32：再高（≥0.4）边缘开始发脏成彩虹边；0.32 与 1.75 是一对，
/// 改一个另一个要跟着看。
const double appGlassPinnedChromaticAberration = 0.32;

/// **吸顶悬浮条**的 premium 参数：与 [appGlassChromeSettings] **只差三个折射
/// 数**（[appGlassPinnedThickness] / [appGlassPinnedRefractiveIndex] /
/// [appGlassPinnedChromaticAberration]）。
///
/// scrim（0.55）、blur（2）、tint、光照（lightIntensity 1.0 / rimShade /
/// rimLight）、饱和度、边缘吸收全部与 footer 相同——所以「吸顶条更玻璃」不会
/// 顺带改掉文字对比度赖以成立的那几条（底衬亮度、描边高光）。
///
/// 只在 [appGlassPremiumAvailable] 为真时使用（见 app_chrome_glass_bar.dart 的
/// appChromeGlassSettings）；不可用时与 footer 一样整块退回
/// [appGlassSettings]（磨砂）那一套。
LiquidGlassSettings appGlassPinnedSettings(BuildContext context) =>
    _appGlassPremiumChrome(
      context,
      thickness: appGlassPinnedThickness,
      refractiveIndex: appGlassPinnedRefractiveIndex,
      chromaticAberration: appGlassPinnedChromaticAberration,
    );

/// premium chrome 的唯一一份参数表：footer 与三处吸顶条只在三个折射数上分家，
/// 其余（tint / 光照 / 饱和度 / 边缘吸收 / 模糊）**只能是同一份**。
LiquidGlassSettings _appGlassPremiumChrome(
  BuildContext context, {
  required double thickness,
  required double refractiveIndex,
  required double chromaticAberration,
}) {
  final dark = AppColors.isDark;
  return LiquidGlassSettings(
    thickness: thickness,
    blur: appGlassChromeBlur,
    glassColor: appGlassChromeTintColor,
    lightAngle: 2.356,
    lightIntensity: 1.0,
    ambientStrength: dark ? 0.10 : 0.25,
    refractiveIndex: refractiveIndex,
    saturation: appGlassChromeSaturation,
    chromaticAberration: chromaticAberration,
    frost: 0.0,
    rimShade: dark ? 0.28 : 0.34,
    rimLight: dark ? 0.34 : 0.42,
    edgeAbsorption: 0.12,
  );
}

/// premium 胶囊的 tint：浅色 10% 的冷白、深色 7% 的白。
///
/// 比 [appGlassTintColor] 再淡一档——折射把背景色采进来了，tint 只用来把
/// 明暗拉平一点，不参与「撑底色」。
Color get appGlassChromeTintColor =>
    AppColors.isDark ? const Color(0x12FFFFFF) : const Color(0x1AD2DCF0);

/// 表面的 1px 半透明描边颜色：浅色模式收一道极淡的暗边（黑 8%），
/// 深色模式提亮（白 12%）。
///
/// 玻璃与卡片（[AppGlassSurface.depth]）共用这一档：卡片的描边不是另一套
/// 颜色，否则玻璃档 / minimal 档切换时卡片边上会换色。
Color get appGlassStrokeColor => AppColors.isDark
    ? Colors.white.withValues(alpha: 0.12)
    : Colors.black.withValues(alpha: 0.08);

/// 顶部内高光的不透明度：浅色 18%、深色 22%。
///
/// 比早期版本（12%）亮一档——tint 压下去之后，「玻璃还在」这件事要靠高光
/// 与饱和度一起说，而不是靠一层白雾。上限守住 22%：再高就成一条白色横杠。
double appGlassHighlightAlpha() => AppColors.isDark ? 0.22 : 0.18;

/// 玻璃表面的顶部内高光：白色 [appGlassHighlightAlpha] → 0，只铺上沿一半多一点。
LinearGradient appGlassHighlightGradient() {
  final alpha = appGlassHighlightAlpha();
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.white.withValues(alpha: alpha),
      Colors.white.withValues(alpha: 0.0),
    ],
    stops: const [0, 0.55],
  );
}

/// 卡片 / 列表的顶部内高光：白色 6% → 0。
///
/// 比玻璃 chrome 的 [appGlassHighlightAlpha]（18%/22%）低得多：卡片改成白雾
/// 磨砂之后，立体感来自双层阴影（[AppShadow.card]）与 1px 描边，表面高光再
/// 亮就成了压在正文上的一条白杠，也把「雾」重新照成「玻璃」。6% 只留一条
/// 极淡的过渡，明暗两档同一个值——深色模式本来就不该靠反光提层次。
double appCardHighlightAlpha() => 0.06;

/// 卡片顶部的内高光：白色 [appCardHighlightAlpha] → 0 的细渐变。
///
/// 只铺上沿一半多一点（0 → 0.55 停住），再往下就是卡片本体；和玻璃 chrome
/// 用的是同一个形状约定，只是 alpha 低一档。
LinearGradient appCardHighlightGradient() {
  final alpha = appCardHighlightAlpha();
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.white.withValues(alpha: alpha),
      Colors.white.withValues(alpha: 0.0),
    ],
    stops: const [0, 0.55],
  );
}

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

/// **chrome 的 scrim 只有一个来源**：底部胶囊、多选底栏、圆形上传按钮，以及
/// 三处吸顶悬浮条全部取这一组数（[appTabBarScrimAlphaLight] /
/// [appTabBarScrimAlphaDark] 与 [appGlassPremiumScrimAlpha] 都是它的别名，
/// 吸顶条经 app_chrome_glass_bar.dart 的 appChromeScrimAlpha 取同一份；
/// 非吸顶的页内筛选条与内容流日期条不包玻璃，不走这一套）。
///
/// 0.55 = 折射可见度 45%：scrim 是压在玻璃**里面**的那层页面底色，它挡住多少
/// 背景，折射就少多少可弯的内容（[appGlassChromeRefractionVisibility]）。上一轮
/// 胶囊用 0.76/0.82（可见度 24%/18%），折射在真机上几乎看不出来；这一轮按需求
/// 把可见度提到 45%，镜面参数同步加大（[appGlassChromeThickness] 36 /
/// [appGlassChromeChromaticAberration] 0.22 / [appGlassChromeBlur] 2）。
///
/// **回退**：整组数只在这两个常量里。改回 0.76/0.82 就是上一轮的胶囊观感；
/// 多选底栏 / 上传按钮上一轮是 0.20/0.24。
///
/// **代价（实测，见 test/footer_contrast_test.dart）**：未选中文字对四种极端
/// 背景的最坏对比度从 4.89:1 / 5.82:1（浅/深）掉到 **2.62:1 / 2.19:1**，低于
/// WCAG AA 的 4.5:1；底衬亮度也重新跟着照片跳（白/黑照片的底衬亮度差
/// 0.17 → 0.72）。甲（同色 halo）/ 乙（压深未选中色）两个补偿方案的预估数值在
/// 那份测试里钉着，等产品定，这里只负责把数摆出来。
const double appGlassChromeScrimAlphaLight = 0.55;
const double appGlassChromeScrimAlphaDark = 0.55;

/// chrome 当前明暗模式的 scrim 不透明度。
double appGlassChromeScrimAlpha() => AppColors.isDark
    ? appGlassChromeScrimAlphaDark
    : appGlassChromeScrimAlphaLight;

/// chrome 的**折射可见度** = 1 − scrim（目标 0.45）。
///
/// scrim 挡住多少背景，premium 的斜面就有多少内容可弯。0.45 是这一轮的需求值：
/// 再高一点（scrim 0.5）底衬更稳但折射更淡，再低一点文字就更难读——两个方向
/// 都有代价，取舍见 [appGlassChromeScrimAlphaLight] 的代价说明。
double appGlassChromeRefractionVisibility() => 1 - appGlassChromeScrimAlpha();

/// premium 表面（= 三处 chrome）的 scrim 不透明度：与
/// [appGlassChromeScrimAlphaLight] / [appGlassChromeScrimAlphaDark] 同一组数。
const double appGlassPremiumScrimAlphaLight = appGlassChromeScrimAlphaLight;
const double appGlassPremiumScrimAlphaDark = appGlassChromeScrimAlphaDark;

/// premium 表面当前明暗模式的 scrim 不透明度。
double appGlassPremiumScrimAlpha() => AppColors.isDark
    ? appGlassPremiumScrimAlphaDark
    : appGlassPremiumScrimAlphaLight;

/// premium 表面的 scrim 颜色：页面底色 + [appGlassPremiumScrimAlpha]。
Color appGlassPremiumScrimColor() =>
    AppColors.bgPage.withValues(alpha: appGlassPremiumScrimAlpha());

/// premium 表面的「稳定底衬」：scrim 叠在「chrome tint 叠页面底色」上，
/// 给文字对比度一个可算的底。公式与 [appGlassScrimBackplate] 同一条。
Color appGlassPremiumScrimBackplate() => AppAccent.compositeOver(
      appGlassPremiumScrimColor(),
      AppAccent.compositeOver(appGlassChromeTintColor, AppColors.bgPage),
    );

/// scrim 实际用的颜色：页面底色 + 上面对应的不透明度。
Color appGlassScrimColor() =>
    AppColors.bgPage.withValues(alpha: appGlassScrimAlpha());

/// 带 scrim 的表面的「稳定底衬」：scrim 叠在「玻璃 tint 叠页面底色」上。
///
/// 这就是文字实际落上去的那块颜色（页面底色是玻璃背后最典型的底），
/// 拿它算对比度才有意义；半透明 scrim 单独算不出对比度。
///
/// 只用在这条「磨砂回退」路径上：premium 表面走
/// [appGlassPremiumScrimBackplate]（55% scrim）。tint 压低之后这条公式的值
/// 更接近页面底色，同一套未选中灰字的对比度反而更高。
Color appGlassScrimBackplate() => AppAccent.compositeOver(
      appGlassScrimColor(),
      AppAccent.compositeOver(appGlassTintColor, AppColors.bgPage),
    );

/// **卡片**上文字实际落上去的底色（没有 scrim 那一层）。
///
/// 卡片不带 scrim（[AppGlassSurface.scrim] 默认 false），所以底衬只有「玻璃
/// tint 叠页面底色」这一层：磨砂卡片（卡片现在的档位，见
/// [AppGlassSurface.kCardQuality]）用 [appCardFrostTintColor]（84%/86%），
/// premium（静态 chrome 才用）用 [appGlassChromeTintColor]（10%/7%）。
/// 两者都是半透明色，单独算对比度没有意义——先按 [AppAccent.compositeOver]
/// 合成成不透明色再算。
///
/// 页面底图/渐变会让真实底衬在这个值上下浮动，所以对比度断言取这条「最典型」
/// 的底（页面底色），和 [appGlassPremiumScrimBackplate] 是同一个约定。
/// 磨砂 tint 提到 84%/86% 之后底衬就是 [AppColors.bgSurface]，卡片小字的
/// 对比度只会更高。
Color appGlassCardBackplate({bool premium = true}) => AppAccent.compositeOver(
      premium ? appGlassChromeTintColor : appCardFrostTintColor,
      AppColors.bgPage,
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
/// 材质档位只有一个开关：[kCardQuality]。卡片 / 列表项 / 新建相册按钮不传
/// [requestedQuality] 时就用它，现在是 [GlassQuality.standard]——**故意不是
/// premium**：premium 要抓 capture，列表重建那一帧会黑，见 [kCardQuality]。
///
/// 性能：列表里的卡片保持 useOwnLayer: false（不自建层，交给包的路径处理），
/// 内容再套一层 [RepaintBoundary]——滚动时只重绘玻璃层，卡片里的文字/图片走
/// 缓存，不会每帧重建。standard 只有一层 BackdropFilter，滚动列表里是包自己
/// 推荐的档位；档位是静态的，掉帧**不会**让它降档（见 [appGlassRoot]）。
///
/// **三档的实现差别**：
/// - premium（[preferPremium] 为真且 [appGlassPremiumAvailable] 为真，只有
///   静态 chrome 走）：[appGlassChromeSettings] 的深斜面参数 + 55% scrim
///   （[appGlassPremiumScrimAlpha] = 折射可见度 45%）；
/// - standard（卡片 / 显式要 standard 的表面）：**不抓 capture**；卡片 /
///   列表（[depth] 为真）走 [appCardFrostSettings]（白雾磨砂：blur 8、
///   tint 84%/86%、折射归零），其余走 [appGlassSettings]（轻磨砂）；
/// - 不透明（平台不支持 shader / 注入 minimal / 下拉刷新保持）：不透明
///   [AppColors.bgSurface] 圆角块，见 [pauseDuringRefresh]。
/// 三条路布局完全一致（同样的 margin / padding / 圆角），切档不跳版、不白屏。
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
    this.preferPremium = false,
    this.settings,
    this.scrim = false,
    this.scrimColor,
    this.pauseDuringRefresh = true,
    this.depth = false,
    this.showBorder = true,
    this.showHighlight = true,
    this.backplate,
  });

  /// 卡片 / 列表的外层阴影（[depth] 为 true 时才有）。
  static const Key shadowKey = Key('app-glass-shadow');

  /// 前景描边层：玻璃分支一直是前景绘制，[depth] 的不透明分支也走它。
  static const Key strokeKey = Key('app-glass-stroke');

  /// 玻璃分支的内部 scrim 层（只有 [scrim] 为 true 时有）。
  static const Key scrimKey = Key('app-glass-scrim');

  /// 顶部内高光层（玻璃分支与 [depth] 的卡片都有）。
  static const Key highlightKey = Key('app-glass-highlight');

  /// 表面内部的固定底衬层（只有 [backplate] 非 null 时有）。
  static const Key backplateKey = Key('app-glass-backplate');

  /// 卡片 / 列表项 / 新建相册按钮的材质档位：**一处开关**。
  ///
  /// 现在是 [GlassQuality.standard]：卡片 / 列表走
  /// [appCardFrostSettings] 的白雾磨砂参数（thickness 12 / blur 8 /
  /// tint 84%~86% / lightIntensity 0.65~0.55 / refractiveIndex 1 /
  /// chromaticAberration 0），包的轻量 shader，纯 BackdropFilter。
  ///
  /// **为什么不是 premium（这是「下拉刷新黑卡」的根因）**：premium 在包里是
  /// GlassContainer → AdaptiveGlass → LiquidGlass.withOwnLayer →
  /// LiquidGlassLayer 的「全管线」路径，形状遮罩与背景都要 capture
  /// （几何遮罩的 Picture.toImageSync、背景的 BackdropGroup/RepaintBoundary）。
  /// 滚动列表在下拉刷新 / 数据替换 / 滚出缓存区时会换掉玻璃层，而新层在
  /// capture 还没就绪的那一帧照样会画一遍：采到空纹理，叠上 tint 就是一块近黑。
  /// 真机现象正是「下拉刷新时出现黑色卡片」，且发生在刷新回调**之外**（数据
  /// 替换后那几帧）——所以上一轮「刷新期间暂停玻璃」挡不住它。
  /// 卡片不抓 capture，这一帧就不存在。
  ///
  /// premium 只留给静态 chrome：底部胶囊（[AppBottomTabBar.preferredQuality]）
  /// 位置固定、不随列表重建，capture 稳定，折射才有意义。
  ///
  /// 改回 premium 只需改这一行（所有 [AppCard] / 未显式传 [requestedQuality] 的
  /// [AppGlassSurface] 一起变），但黑卡会一起回来：见
  /// test/feed_refresh_glass_test.dart。
  static const GlassQuality kCardQuality = GlassQuality.standard;

  final Widget child;

  /// 圆角半径（直角用 0）。
  final double radius;

  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// 只在退化分支画的描边（比如底部栏顶部那条 1px 分隔线）。
  /// 玻璃分支不画：玻璃自带 [strokeKey] 那圈描边与内高光，再加就成了两条线。
  /// 不传时退化分支默认给一圈 [AppColors.divider] 细边，胶囊/卡片才有边界。
  final BoxBorder? border;

  /// 调用点想要的档位；见 [glassQualityFor]。不传时用 [kCardQuality]
  /// （卡片 / 列表项 / 新建相册按钮的开关）。
  final GlassQuality? requestedQuality;

  /// 这一处实际想要的那一档：显式传的 [requestedQuality] 优先，否则
  /// [kCardQuality]。拿不到 premium 之前不会「降」它的值，降档发生在 build
  /// 里（[glassQualityFor] 与 [appGlassPremiumAvailable]）。
  GlassQuality get wantedQuality => requestedQuality ?? kCardQuality;

  /// 玻璃是否自建一层渲染上下文。默认 false。
  ///
  /// **只有底部胶囊传 true**。卡片 / 列表项保持 false：本 App 没有祖先
  /// LiquidGlassLayer（main() 只注入静态档位，不建层），包在没有外层时会自己兜底
  /// 建层，per-widget settings 照样按本控件的传参生效。调用点保持 false 是为了
  /// 留住「不自建层」的意图（将来接全局层时卡片不用改），列表滚动时也只重绘
  /// 内容那层 [RepaintBoundary]。
  ///
  /// 注：真有祖先 LiquidGlassLayer 时，grouped 模式会忽略 per-widget settings
  /// ——那时才需要打开这里。
  final bool useOwnLayer;

  /// 是否优先要 premium 档（折射/边缘扭曲）。
  ///
  /// **只有静态 chrome 传 true**（底部胶囊：位置固定、不随列表重建，capture
  /// 稳定）。卡片不用传、也不该传：[kCardQuality] 是 standard，卡片走 premium
  /// 的 capture 路径就是黑卡的来源（见 [kCardQuality]）。传 true 不代表一定用
  /// 上：拿不到 premium 时由 [appGlassPremiumAvailable] 判定并整块退回磨砂实现
  /// （[appGlassSettings] + 重 scrim），不留半套参数。
  final bool preferPremium;

  /// 玻璃参数；null 时按档位取 [appGlassChromeSettings]（premium，和底部
  /// 胶囊同一套）、[appCardFrostSettings]（卡片 / 列表，[depth] 为真）或
  /// [appGlassSettings]（其余 standard 表面）。
  final LiquidGlassSettings? settings;

  /// 是否在玻璃内部叠一层低透明 scrim（[scrimKey]）。
  ///
  /// 给「玻璃后面有内容在滚、表面里还有文字/图标」的地方用（底部胶囊）：
  /// 磨砂后面是照片，只靠玻璃自己的 tint，文字落上去的底色每帧都在变。
  /// 卡片这种底下基本是页面底色的表面不需要——多叠一层只会把玻璃压灰。
  ///
  /// 不透明度跟着档位走：磨砂回退 42%/50%（[appGlassScrimAlpha]），premium
  /// 55%（[appGlassPremiumScrimAlpha]，= 折射可见度 45%）——三处 chrome 同一档。
  final bool scrim;

  /// scrim 的颜色；null 时按档位取 [appGlassScrimColor]（42%/50%）或
  /// [appGlassPremiumScrimColor]（55%）。
  final Color? scrimColor;

  /// 下拉刷新期间是否临时换成**同色不透明表面**（见 [AppGlassRefreshHold]）。
  ///
  /// 默认 true，对所有非静态 chrome 的玻璃表面生效（卡片现在虽然是 standard，
  /// 也在其中）；[preferPremium] 为 true 的底部胶囊不受影响（它背后是页面底图，
  /// 刷新时也不跟着变）。刷新那几帧卡片本来就要整体重建、backdrop 采样不稳，
  /// 换成 bgSurface 圆角块最稳——布局、圆角、内外边距一模一样，刷新一结束立刻
  /// 回到玻璃。
  ///
  /// 这是黑卡修好之后的**第二层保险**：根因在 [kCardQuality]（premium 的
  /// capture 未就绪帧），暂停只负责让刷新这几帧更钝一点。
  final bool pauseDuringRefresh;

  /// 卡片 / 列表的立体感：双层阴影 + 顶部内高光 + 1px 半透明描边。
  ///
  /// 默认 false：底部胶囊 / 筛选条 / 底栏 / 弹窗这些 chrome 保持原样。卡片
  /// （[AppCard]、朋友圈 PostCard、我的页头像卡）传 true。
  ///
  /// 玻璃分支本来就有高光与描边，打开 depth 后只是把高光换成卡片那一档
  /// （[appCardHighlightAlpha]，6%→0）并补一层外层阴影；**不透明分支**
  /// （minimal / 无档位 / 刷新保持）照样画同样的阴影与描边，只是没有模糊——
  /// 低端机上的卡片同样有层次，切档也不会从「有阴影」跳成「贴着底」。
  ///
  /// 全是静态绘制：阴影画在卡片外面（不吃布局）、描边用前景 DecoratedBox
  /// （不会像 Container.border 那样把 56 撑成 58）、高光是 IgnorePointer
  /// 叠层（不挡点击）。不做任何按下/悬浮位移动画，列表滚动不会抖。
  final bool depth;

  /// 是否画表面那圈 1px 半透明描边（[strokeKey]）。
  ///
  /// 默认 true：footer 胶囊、底栏、弹窗、卡片都要这一圈边，表面才有边界。
  /// **三处吸顶悬浮条显式传 false**（见 AppChromeGlassBar）：吸顶条是横贯
  /// 整屏的直边条，描边会在上下沿各留一条看得见的线，把玻璃和页面切开。
  ///
  /// false 时玻璃分支不挂 [strokeKey]，不透明分支也不再补 [border] 那圈
  /// 默认细边（[depth] 卡片由 [AppSurfaceDepth] 自己画，不受影响）。描边本来
  /// 就是前景绘制，去掉它布局尺寸一点不变。
  final bool showBorder;

  /// 是否画顶部内高光层（[highlightKey]）。
  ///
  /// 默认 true（footer 胶囊、卡片、弹窗）。三处吸顶条传 false：去掉之后条带
  /// 只剩玻璃本体 + scrim（+ 阴影，若有），斜面与折射自己就是「玻璃」那条边，
  /// 不再叠一道白色横杠。false 时这一层整个不建（连 DecoratedBox 都没有）。
  final bool showHighlight;

  /// 表面**内部**的一层固定底衬色：画在玻璃/scrim 之上、内容之下。
  ///
  /// null = 不画（footer 胶囊与其余表面保持原样）。**三处吸顶悬浮条**显式传
  /// 「页面底色 + AppChromeGlassBar 的 kAppChromePinnedBackplateAlpha」：吸顶条底下是
  /// 滚动的照片/卡片，玻璃的 scrim 只压 55%，剩下 45% 的背景权重会让合成色
  /// 跟着滚过的内容漂——下拉刷新那几帧最明显（条带会「变色」）。这层固定
  /// 底衬把可漂移的权重压到 (1 − alpha) × 45%，合成色基本钉死；折射/模糊
  /// 仍然由它上面那层玻璃提供，Element 与材质都不换。
  final Color? backplate;

  @override
  Widget build(BuildContext context) {
    // 刷新开关一变就重建：开关只在真刷新期间变，平时没有额外开销。
    return ValueListenableBuilder<bool>(
      valueListenable: AppGlassRefreshHold.active,
      builder: (context, refreshHeld, _) =>
          _buildSurface(context, refreshHeld: refreshHeld),
    );
  }

  /// 真正画表面的地方；[refreshHeld] 来自 [AppGlassRefreshHold]。
  Widget _buildSurface(BuildContext context, {required bool refreshHeld}) {
    // 想要的那一档：调用点显式传的档位优先，否则就是卡片开关 [kCardQuality]
    // （standard，见那里的「premium 抓 capture → 黑卡」）。
    final wanted = wantedQuality;
    // premium 只在「想要（显式 preferPremium 或档位本身是 premium）且这一段
    // 真的支持」时才生效；否则一律走 standard（磨砂参数，不抓 capture）。
    final premium = (preferPremium || wanted == GlassQuality.premium) &&
        appGlassPremiumAvailable(context);
    // 刷新保持（第二层保险）：非静态 chrome 的玻璃这几帧一律先不画玻璃，
    // 换成同色不透明表面；档位本身不动，刷新一结束就回来。
    final refreshPaused = refreshHeld && pauseDuringRefresh && !preferPremium;
    final quality = refreshPaused
        ? null
        : glassQualityFor(
            context,
            // 拿不到 premium 时明确要 standard：包的轻量 shader 只有在显式
            // standard 时才跳过「premium 参数 → standard」的归一化，参数才是
            // 我们调的那一套。卡片想要的本来就是 standard（[kCardQuality]）。
            requested: premium
                ? GlassQuality.premium
                : (wanted == GlassQuality.premium
                    ? GlassQuality.standard
                    : wanted),
          );
    // 只有真的解析成 premium 才切换参数/scrim：降档时连 settings 一起换回来，
    // 不会留下「深斜面 + 薄 scrim」这种既不透也读不清的中间态。
    final premiumActive = premium && quality == GlassQuality.premium;
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
      // 刷新保持（[refreshPaused]）走的就是这条分支：同色不透明表面、布局
      // 一模一样，刷新一结束立刻回到玻璃（档位从未被改过）。
      // depth 卡片的描边由 [AppSurfaceDepth] 统一画（和玻璃分支同一档的
      // 半透明 1px 边），这里不再叠一圈 divider，免得两条边叠成深色。
      Widget opaque = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: borderRadius,
          border: depth || !showBorder
              ? null
              : border ?? Border.all(color: AppColors.divider, width: 1),
        ),
        child: padded,
      );
      if (depth) {
        // 没有模糊，但阴影、高光、描边一样不少：低端机上卡片也有层次。
        opaque = AppSurfaceDepth(radius: radius, child: opaque);
      }
      if (margin == null) return opaque;
      return Padding(padding: margin!, child: opaque);
    }

    final glass = GlassContainer(
      // 圆角形状（底部栏那种胶囊）走包的 superellipse，圆角之外还有一圈
      // 玻璃自己的高光边。
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      quality: quality,
      // 不自建层：只有底部胶囊显式要 useOwnLayer，卡片保持 false（见字段注释）。
      useOwnLayer: useOwnLayer,
      settings: settings ??
          (premiumActive
              // 静态 chrome（底部胶囊 / 多选底栏 / 上传按钮）：折射。
              ? appGlassChromeSettings(context)
              // 卡片 / 列表项：白雾磨砂（[AppGlassSurface.depth] 为真）。
              : depth
                  ? appCardFrostSettings(context)
                  // 其余显式要 standard 的表面（强制更新弹窗）：轻磨砂。
                  : appGlassSettings(context)),
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
                    color: scrimColor ??
                        (premiumActive
                            ? appGlassPremiumScrimColor()
                            : appGlassScrimColor()),
                    borderRadius: borderRadius,
                  ),
                ),
              ),
            ),
          // 固定底衬：画在玻璃之上、内容之下，把「背后内容在动」这件事从
          // 合成色里挤出去（见 [backplate]）。
          if (backplate != null)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: backplateKey,
                  decoration: BoxDecoration(
                    color: backplate,
                    borderRadius: borderRadius,
                  ),
                ),
              ),
            ),
          padded,
          // 顶部内高光：静态一层，盖在内容上、不参与命中测试。
          // depth 卡片的高光由外层 [AppSurfaceDepth] 画（和 minimal 同一层），
          // 这里不再叠第二层。
          if (!depth && showHighlight)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: highlightKey,
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    gradient: appGlassHighlightGradient(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (depth) {
      // 卡片的立体感：双层阴影 + 卡片档内高光 + 1px 描边。玻璃仍是 standard
      // （不抓 capture），只是外面多一层阴影、里面换成低一档的高光。
      final Widget layered = AppSurfaceDepth(radius: radius, child: glass);
      if (margin == null) return layered;
      return Padding(padding: margin!, child: layered);
    }

    // 不要描边（三处吸顶条）：整块只剩玻璃本体 + scrim，布局尺寸照旧。
    if (!showBorder) {
      if (margin == null) return glass;
      return Padding(padding: margin!, child: glass);
    }

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

/// 卡片 / 列表的立体感外层：双层阴影（[AppShadow.card]）+ 顶部内高光
/// （[appCardHighlightGradient]）+ 1px 半透明描边（[appGlassStrokeColor]）。
///
/// [AppGlassSurface.depth] 与 [AppCard] 的不透明分支共用这一层，所以玻璃档 /
/// minimal 档看起来是同一张卡片：玻璃档只是多一层模糊，阴影、高光、描边完全
/// 一致。圆角取调用点现有的 token（[AppRadius]），这里不自己定。
///
/// 三层都不吃布局：
/// - 阴影画在圆角矩形外面，不撑尺寸；
/// - 高光是 Positioned.fill + IgnorePointer，盖在内容上但不挡点击；
/// - 描边是 DecorationPosition.foreground 的 1px 边，不会像
///   Container.border 那样把高度撑大 1px。
///
/// 没有任何按下/悬浮位移动画：列表滚动时卡片不会抖。
class AppSurfaceDepth extends StatelessWidget {
  const AppSurfaceDepth({super.key, required this.radius, required this.child});

  /// 与表面一致的圆角半径（[AppRadius] 里的 token）。
  final double radius;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      key: AppGlassSurface.shadowKey,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: AppShadow.card,
      ),
      // passthrough：约束原样透传，卡片宽高与没有这一层时完全一致。
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: AppGlassSurface.highlightKey,
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: appCardHighlightGradient(),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: AppGlassSurface.strokeKey,
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(color: appGlassStrokeColor, width: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 背景图上的可读性遮罩：浅色模式叠 [AppColors.bgPage] 35%，深色 45%。
///
/// 图上直接压一层页面底色，卡片/文字不用跟着换配色也读得清；两档的差别来自
/// 深色底本身更亮（#0E1118），压得轻一点就够。
///
/// 取值从 55%/65% 降到 35%/45%：用户选的那张图才是「页面背景」，压到 55%
/// 之后图的对比度、细节全被抹平，看起来就是「糊」。文字可读性不再靠这层
/// 遮罩硬撑——卡片自己是 84%/86% 的白雾磨砂（[appCardFrostTintColor]），
/// 正文落在卡片上，不落在图上。
const double appBackdropMaskAlphaLight = 0.35;
const double appBackdropMaskAlphaDark = 0.45;

/// 当前明暗模式下的遮罩不透明度。
double appBackdropMaskAlpha() =>
    AppColors.isDark ? appBackdropMaskAlphaDark : appBackdropMaskAlphaLight;

/// 遮罩实际用的颜色（页面底色 + 上面对应的不透明度）。
Color appBackdropMaskColor() =>
    AppColors.bgPage.withValues(alpha: appBackdropMaskAlpha());

/// 背景图解码宽度的上限（像素）：与 [PageBackdropController.maxEdge] 同一个数。
///
/// 再大就只是白占内存：2K 屏的物理宽是 1440 左右，2560 宽的手机也要靠
/// 屏幕尺寸现算，而不是这里硬顶。
const int appBackdropDecodeMaxWidth = 2048;

/// 背景图按「屏幕宽 × devicePixelRatio」解码，上限
/// [appBackdropDecodeMaxWidth]。
///
/// 为什么不是写死的 1080：1080 只够 1080p 屏（逻辑宽 360 × 3x）。2K 屏（物理
/// 宽 1440 起）上这张图会被放大 1.3 倍以上，放大就是糊；屏幕更窄时按 2048
/// 解码又白占内存。取「屏幕物理宽」正好是一像素对一像素。
///
/// 拿不到 MediaQuery（极少数没有 MediaQuery 的宿主）时退回上限：宁可用满
/// 分辨率，也不要因为算不出宽度就退到一张小图。
int appBackdropDecodeWidth(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  if (media == null) return appBackdropDecodeMaxWidth;
  final pixels = (media.size.width * media.devicePixelRatio).round();
  if (pixels < 1) return appBackdropDecodeMaxWidth;
  if (pixels > appBackdropDecodeMaxWidth) return appBackdropDecodeMaxWidth;
  return pixels;
}

/// 页面最底层的「流动底色」：给玻璃一点可被模糊的内容。
///
/// 根因：BackdropFilter 模糊的是它背后的像素，纯色页面上模糊纯色还是纯色，
/// 玻璃只剩一点透明度。这里在 [AppColors.bgPage] 上铺一条非常克制的对角线
/// 渐变加两团径向光斑（主题色 6~10% 透明度，深色模式换成压暗的近似色），
/// 玻璃背后就有东西在流动。
///
/// 用户在哪一种形态由 [PageBackdropSpec] 决定（[PageBackdropController.spec]，
/// 三个页面共用同一份）：
/// - 默认渐变：上面这套品牌渐变 + 光斑，原样保留；
/// - 纯色：一块 [BoxDecoration.color]，**不套遮罩**——遮罩是为了让图上的文字
///   读得清，套到用户挑的颜色上只会把它改成另一块灰；
/// - 双色渐变：左上 → 右下的 [LinearGradient]，同样不套遮罩；
/// - 图片：[BoxFit.cover] 铺满 + 一层可读性遮罩，渐变与光斑整体让位（图本身
///   就是「有东西可模糊」）。图丢了自动回退默认渐变。
///
/// **这张图本身必须是清晰的**：背景图那一层不加任何
/// [ImageFilter.blur]/[BackdropFilter]，也不做低质量过滤（[BoxFit.cover] +
/// [FilterQuality.medium]）。模糊只有一处来源——卡片自己的 glass shader
/// 模糊它**后面**的内容；在背景图上再开一层模糊，就是「整页都糊」。
///
/// 性能：全是静态绘制，不参与每帧重绘；背景图只解码一份（[Image.file] 的
/// cacheWidth 走 [ResizeImage]，尺寸按 [appBackdropDecodeWidth] =「屏幕宽 ×
/// devicePixelRatio」、上限 [appBackdropDecodeMaxWidth]），并单独包一层
/// [RepaintBoundary]。与玻璃卡片共存时不额外开模糊层——模糊由卡片自己的
/// shader 负责，这里再开一层就是白烧 GPU。
/// [GlassQuality.minimal] 下照样画——背景是普通绘制，跟玻璃档位无关。
/// 背景代表色：最近一次「这一页背景长什么样」的采样结果。
///
/// **谁写**：[AppGlassBackdrop] 里的采样器（背景变更 / 切明暗时各更新一次）。
/// **谁读**：玻璃 chrome 的墨色选择（app_glass_tone.dart 的
/// [appGlassToneInkForBackdrop]）——底衬亮就用深墨，暗就用白。
/// **为什么是 ValueNotifier**：换背景只该重建 chrome 上那几段文字/图标，
/// 不该重建整页；null 表示还没采到（此时按主题亮度回退）。
class AppBackdropSample {
  AppBackdropSample._();

  /// 背景代表色；null = 还没采到 / 采样失败。
  static final ValueNotifier<Color?> color = ValueNotifier<Color?>(null);

  /// 测试用：直接注入一次采样结果（不跑解码、不依赖真机渲染）。
  @visibleForTesting
  static void report(Color? value) => color.value = value;

  /// 测试用：恢复成「没有采样」。
  @visibleForTesting
  static void reset() => color.value = null;
}

/// 采样 [AppGlassBackdrop] 真正画出来的那层底子，把「代表色」写进
/// [AppBackdropSample]。
///
/// **不每帧截屏，也不 toImageSync**：
/// - 纯色 → 就是那个颜色；
/// - 双色渐变 → 两个色标的平均；
/// - 默认渐变 → 页面底色（主题色只占 6%~10% 的透明度，代表色基本就是底）；
/// - 图片 → **背景变更时**解码一张 24px 宽的缩略图求均值，再叠上那层可读性
///   遮罩（instantiateImageCodec(targetWidth: 24)，一次一两毫秒）。
///
/// 加起来的开销只落在「用户换背景」「切明暗」这两个瞬间，滚动/翻页/掉帧都
/// 碰不到它。采样失败（文件被删、不是图片）就当没有采样，调用点按主题回退。
class _BackdropSampleScope extends StatefulWidget {
  const _BackdropSampleScope({required this.child});

  final Widget child;

  @override
  State<_BackdropSampleScope> createState() => _BackdropSampleScopeState();
}

class _BackdropSampleScopeState extends State<_BackdropSampleScope> {
  /// 上一次采样的签名（spec + 明暗）：同一个签名不重复解码。
  String? _signature;

  /// 异步采样的序号：解码回来时已经不是最新一次就丢掉。
  int _token = 0;

  @override
  void initState() {
    super.initState();
    PageBackdropController.spec.addListener(_onSpecChanged);
    _scheduleSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 切明暗会走到这里：遮罩色与默认渐变的代表色都跟着变。
    _scheduleSync();
  }

  @override
  void dispose() {
    PageBackdropController.spec.removeListener(_onSpecChanged);
    super.dispose();
  }

  // 换背景也在下一帧再采：不在 pickAndSave 的通知链里跑任何 I/O，
  // 选图那条路（复制文件 + 落盘）就不会被采样拖到。
  void _onSpecChanged() => _scheduleSync();

  /// 首帧之后再采：build 期间改 notifier 会撞上「build 中标记重建」。
  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  void _sync() {
    final spec = PageBackdropController.spec.value;
    final signature = spec.encode() + (AppColors.isDark ? '|dark' : '|light');
    if (signature == _signature) return;
    _signature = signature;
    final token = ++_token;

    if (!spec.isImage) {
      AppBackdropSample.report(_specColor(spec));
      return;
    }
    final file = PageBackdropController.imageFileOf(spec);
    if (file == null) {
      AppBackdropSample.report(
          _specColor(const PageBackdropSpec.defaultGradient()));
      return;
    }
    unawaited(_averageOf(file).then((average) {
      if (!mounted || token != _token) return;
      AppBackdropSample.report(average == null
          ? _specColor(const PageBackdropSpec.defaultGradient())
          : AppAccent.compositeOver(appBackdropMaskColor(), average));
    }));
  }

  /// spec 的代表色（非图片形态）。
  Color _specColor(PageBackdropSpec spec) => switch (spec.type) {
        PageBackdropType.color => spec.color ?? AppColors.bgPage,
        PageBackdropType.gradient => Color.lerp(
            spec.gradientStart ?? AppColors.bgPage,
            spec.gradientEnd ?? AppColors.bgPage,
            0.5,
          )!,
        _ => AppColors.bgPage,
      };

  /// 图片的平均色：解码成 24px 宽的缩略图求均值。
  Future<Color?> _averageOf(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();
      if (data == null) return null;
      final pixels = data.buffer.asUint8List();
      var r = 0, g = 0, b = 0, count = 0;
      for (var i = 0; i + 3 < pixels.length; i += 4) {
        r += pixels[i];
        g += pixels[i + 1];
        b += pixels[i + 2];
        count++;
      }
      if (count == 0) return null;
      return Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
    } catch (_) {
      // 文件被删 / 不是图片：当采样失败，调用点回退主题。
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

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
  ///
  /// **只有图片形态才有这一层**：纯色 / 双色渐变是用户自己挑的底，不压遮罩。
  static const Key maskKey = Key('app-glass-backdrop-mask');

  /// 纯色那一层（[BoxDecoration.color] = spec 里的颜色）。
  static const Key colorKey = Key('app-glass-backdrop-color');

  /// 双色渐变那一层（左上 → 右下的 [LinearGradient]，正好两个色标）。
  static const Key customGradientKey =
      Key('app-glass-backdrop-gradient-colors');

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 背景两层交给采样器包着：它只读不画，采到的是**背景本身**（不含页面
        // 内容），供玻璃 chrome 决定文字/图标的明暗（见 [AppBackdropSample]）。
        Positioned.fill(
          child: _BackdropSampleScope(
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    key: baseKey,
                    decoration: BoxDecoration(color: AppColors.bgPage),
                  ),
                ),
                // 四选一：默认渐变 / 纯色 / 双色渐变 / 图片。图片副本丢了（含
                // 文件被删）原样回退到默认渐变。
                Positioned.fill(
                  child: ValueListenableBuilder<PageBackdropSpec>(
                    valueListenable: PageBackdropController.spec,
                    builder: (context, spec, _) => _specLayers(context, spec),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }

  /// 按 spec 画对应的那一层。
  ///
  /// 遮罩只在图片分支出现（[_photoLayers]）：纯色 / 双色渐变是用户自己挑的
  /// 底，压一层页面底色的半透明遮罩等于把他选的颜色改掉。
  Widget _specLayers(BuildContext context, PageBackdropSpec spec) {
    switch (spec.type) {
      case PageBackdropType.defaultGradient:
        return _gradientLayers();
      case PageBackdropType.color:
        return DecoratedBox(
          key: colorKey,
          decoration: BoxDecoration(color: spec.color ?? AppColors.bgPage),
        );
      case PageBackdropType.gradient:
        return DecoratedBox(
          key: customGradientKey,
          decoration: BoxDecoration(
            // 方向固定左上 → 右下（和默认渐变同一条对角线），不另做方向设置。
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                spec.gradientStart ?? AppColors.bgPage,
                spec.gradientEnd ?? AppColors.bgPage,
              ],
            ),
          ),
        );
      case PageBackdropType.image:
        final file = PageBackdropController.imageFileOf(spec);
        return file == null ? _gradientLayers() : _photoLayers(context, file);
    }
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
  Widget _photoLayers(BuildContext context, File file) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 单独成层 + 按屏幕解码：玻璃卡片滚动/重绘时不重新解码这张图。
        // 解码宽度跟着屏幕走（[appBackdropDecodeWidth]），2K 屏上不会拿一张
        // 1080 的图去放大；[FilterQuality.medium] 是默认档，显式写出来是为了
        // 不给「被谁改低成 low」留口子。
        RepaintBoundary(
          child: Image.file(
            file,
            key: imageKey,
            fit: BoxFit.cover,
            cacheWidth: appBackdropDecodeWidth(context),
            filterQuality: FilterQuality.medium,
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
