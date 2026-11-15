import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, ValueListenable;
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
/// 取值比早期版本（23% / 17%）低一档：卡片要「透」出来，底色由背后的渐变/
/// 背景图自己给，玻璃只负责一层极淡的冷调与高光。卡片正文用的是
/// [AppColors.textPrimary]，对这块底衬的对比度 > 15:1；tint 压低只会让底衬
/// 更接近页面底色，文字不会更难读（底部胶囊另有 scrim，见
/// [appGlassScrimBackplate]）。
Color get appGlassTintColor =>
    AppColors.isDark ? const Color(0x1AFFFFFF) : const Color(0x26D2DCF0);

/// 磨砂档的光学参数：**透**优先，不做磨砂墙。
///
/// 就是 standard 档用的那一套：卡片 / 列表项 / 新建相册按钮（
/// [AppGlassSurface.kCardQuality]）、调用点显式要 standard 的表面（强制更新
/// 弹窗），以及 premium 拿不到（[appGlassPremiumAvailable] 为假）时的整块回退。
/// premium 那一套见 [appGlassChromeSettings]。
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

/// premium 档的光学参数：**折射**优先。现在只有静态 chrome（底部胶囊，见
/// [AppGlassSurface.preferPremium]）用这一套——卡片走 standard，见
/// [AppGlassSurface.kCardQuality] 里「premium 会抓 capture，列表重建时会黑」。
///
/// 和 [appGlassSettings] 的差别都在「折射能不能看出来」这件事上：
/// - thickness 28（磨砂 12）：斜面越深，边缘的 displacement 越大，胶囊的两条
///   长边和卡片的圆角能把底下的内容推歪，这才是「玻璃」而不是「毛玻璃」；
/// - refractiveIndex 1.38（磨砂 1.2）、chromaticAberration 0.10：折射率越高
///   弯折越明显，色散让边缘出现一圈彩色描边（premium 的 dispersion）；
/// - blur 3（磨砂 8）：模糊压到最低，折射才不会被糊掉——要的是「透」；
/// - glassColor 比磨砂更淡（[appGlassChromeTintColor]）：premium 表面自己
///   已经会采背景色，再叠一层 tint 就回到磨砂；
/// - lightIntensity 1.0 + rimShade/rimLight：一圈更亮的高光边。
///
/// 只在 [appGlassPremiumAvailable] 为真时使用；不可用时整块退回
/// [appGlassSettings]（磨砂）那一套。
LiquidGlassSettings appGlassChromeSettings(BuildContext context) {
  final dark = AppColors.isDark;
  return LiquidGlassSettings(
    thickness: 28,
    blur: 3,
    glassColor: appGlassChromeTintColor,
    lightAngle: 2.356,
    lightIntensity: 1.0,
    ambientStrength: dark ? 0.10 : 0.25,
    refractiveIndex: 1.38,
    saturation: 1.3,
    chromaticAberration: 0.10,
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

/// 玻璃表面的 1px 半透明描边颜色：浅色模式收一道极淡的暗边，深色模式提亮。
Color get appGlassStrokeColor => AppColors.isDark
    ? Colors.white.withValues(alpha: 0.14)
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

/// premium 胶囊内部那层 scrim 的不透明度：浅色 20%、深色 24%。
///
/// 磨砂档要 42%/50% 才托得住灰字，是因为标准 shader 只做「模糊 + tint」，
/// 底衬随照片每帧在跳；premium 会真的把背景折射进来，压一层 42% 的页面底色
/// 就把折射糊成一块灰板了。这里只留薄薄一层（页面底色的 20%），把文字从「照片
/// 上」抬到「有一层极淡冷调的玻璃上」，对比度仍然够（见测试里的 4.5 断言）。
const double appGlassPremiumScrimAlphaLight = 0.20;
const double appGlassPremiumScrimAlphaDark = 0.24;

/// premium 胶囊当前明暗模式的 scrim 不透明度。
double appGlassPremiumScrimAlpha() => AppColors.isDark
    ? appGlassPremiumScrimAlphaDark
    : appGlassPremiumScrimAlphaLight;

/// premium 胶囊的 scrim 颜色：页面底色 + [appGlassPremiumScrimAlpha]。
Color appGlassPremiumScrimColor() =>
    AppColors.bgPage.withValues(alpha: appGlassPremiumScrimAlpha());

/// premium 胶囊的「稳定底衬」：薄 scrim 叠在「chrome tint 叠页面底色」上，
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
/// 只用在这条「磨砂回退」路径上：premium 胶囊走
/// [appGlassPremiumScrimBackplate]（薄 scrim）。tint 压低之后这条公式的值
/// 更接近页面底色，同一套未选中灰字的对比度反而更高。
Color appGlassScrimBackplate() => AppAccent.compositeOver(
      appGlassScrimColor(),
      AppAccent.compositeOver(appGlassTintColor, AppColors.bgPage),
    );

/// **卡片**上文字实际落上去的底色（没有 scrim 那一层）。
///
/// 卡片不带 scrim（[AppGlassSurface.scrim] 默认 false），所以底衬只有「玻璃
/// tint 叠页面底色」这一层：standard（卡片现在的档位，见
/// [AppGlassSurface.kCardQuality]）用 [appGlassTintColor]（15%/10%），
/// premium（静态 chrome 才用）用 [appGlassChromeTintColor]（10%/7%）。
/// 两者都是半透明色，单独算对比度没有意义——先按 [AppAccent.compositeOver]
/// 合成成不透明色再算。
///
/// 页面底图/渐变会让真实底衬在这个值上下浮动，所以对比度断言取这条「最典型」
/// 的底（页面底色），和 [appGlassPremiumScrimBackplate] 是同一个约定。
Color appGlassCardBackplate({bool premium = true}) => AppAccent.compositeOver(
      premium ? appGlassChromeTintColor : appGlassTintColor,
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
///   静态 chrome 走）：[appGlassChromeSettings] 的深斜面参数 + 薄 scrim
///   （[appGlassPremiumScrimAlpha]）；
/// - standard（卡片 / 显式要 standard 的表面）：[appGlassSettings] 的磨砂参数，
///   纯 BackdropFilter，**不抓 capture**；
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
  });

  /// 玻璃分支的前景描边层。
  static const Key strokeKey = Key('app-glass-stroke');

  /// 玻璃分支的内部 scrim 层（只有 [scrim] 为 true 时有）。
  static const Key scrimKey = Key('app-glass-scrim');

  /// 玻璃分支的顶部内高光层。
  static const Key highlightKey = Key('app-glass-highlight');

  /// 卡片 / 列表项 / 新建相册按钮的材质档位：**一处开关**。
  ///
  /// 现在是 [GlassQuality.standard]：[appGlassSettings] 的磨砂参数
  /// （thickness 12 / refractiveIndex 1.2 / chromaticAberration 0.03 / blur 8），
  /// 纯 BackdropFilter + 包的轻量 shader。
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
  /// 胶囊同一套）或 [appGlassSettings]（磨砂回退）。
  final LiquidGlassSettings? settings;

  /// 是否在玻璃内部叠一层低透明 scrim（[scrimKey]）。
  ///
  /// 给「玻璃后面有内容在滚、表面里还有文字/图标」的地方用（底部胶囊）：
  /// 磨砂后面是照片，只靠玻璃自己的 tint，文字落上去的底色每帧都在变。
  /// 卡片这种底下基本是页面底色的表面不需要——多叠一层只会把玻璃压灰。
  ///
  /// 不透明度跟着档位走：磨砂回退 42%/50%（[appGlassScrimAlpha]），premium
  /// 20%/24%（[appGlassPremiumScrimAlpha]）——折射要被看见，只留薄薄一层。
  final bool scrim;

  /// scrim 的颜色；null 时按档位取 [appGlassScrimColor]（42%/50%）或
  /// [appGlassPremiumScrimColor]（20%/24%）。
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
      // 不自建层：只有底部胶囊显式要 useOwnLayer，卡片保持 false（见字段注释）。
      useOwnLayer: useOwnLayer,
      settings: settings ??
          (premiumActive
              ? appGlassChromeSettings(context)
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
          padded,
          // 顶部内高光：静态一层，盖在内容上、不参与命中测试。
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
