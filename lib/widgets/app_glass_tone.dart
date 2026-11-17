import 'package:flutter/material.dart';

import '../core/design/accent.dart';
import '../core/design/colors.dart';
import 'app_glass.dart';

// 玻璃 chrome 的「墨色」（未选中文字 / 图标）按**背景亮度**自动换一套。
//
// 为什么需要它：45% 折射可见度下 scrim 只压 0.55，文字底衬跟着背景在
// 「浅色模式 + 纯黑照片 ≈ #88888A（亮度 0.248）」到「深色模式 + 纯白照片
// ≈ #7A7C80（0.202）」之间跳。固定一套中性灰在同一块底衬上不可能两端都够看
// ——上一轮的 76%/82% scrim 就是靠把底衬压死换来的（折射也就没了）。
// 方案 C：折射保持 45%，文字色改成**按采样到的背景亮度挑**，两套墨色各自
// 覆盖底衬亮度的一半区间。
//
// 账（test/glass_tone_test.dart 逐条钉住）：深墨 #05070A 能压住底衬亮度
// ≥0.183 的所有背景，纯白能压住 ≤0.183 的所有背景；四种极端背景 × 明暗
// 实测最坏 4.83:1（浅色/纯黑照片用深墨 5.72，深色/纯白照片用深墨 4.83）。

/// 墨色阈值：**合成底衬亮度** ≥ 它用深色一套，< 它用浅色一套。
///
/// 0.179 不是直觉的 0.5，而是这两套墨色的**交叉点**：底衬亮度 0.179 时，
/// 纯黑给 4.58:1、纯白给 4.58:1，两边相等；再往上纯黑更好，再往下纯白更好。
/// 选 0.179 而不是别的数，是因为它让两套墨色的可行区间**刚好接上**：纯黑
/// 覆盖 ≥0.175、纯白覆盖 ≤0.183，整个 [0,1] 上最坏也有 4.58:1。
/// 0.5 会在「浅色模式 + 纯黑照片」（底衬亮度 0.248）上选浅色那一套，只剩
/// 3.53:1——这正是这一轮要消灭的那类格子，所以阈值必须落在交叉点上。
/// 想试 0.5 只改这一个常量，但 test/glass_tone_test.dart 里那条「四种极端
/// 背景 ≥4.5」会立刻红。
const double appGlassToneThreshold = 0.179;

/// 深色一套：底衬偏亮时用。**纯黑**——这是能盖住「深色 + 纯白照片」那一格的
/// 唯一一档。
///
/// 为什么不能直接用 textPrimary（#1A1D26，亮度 0.013）：那张底衬是 #7A7C80
/// （亮度 0.202），textPrimary 只有 4.01:1、压到 #05070A 也只有 4.47:1（差
/// 0.03 就是过不了），纯黑才有 4.83:1，并且把整个 [0,1] 亮度区间的最坏值
/// 托到 4.58:1。浅色模式里它就是「未选中的黑字」，与选中态（主题色）一眼分得开。
const Color appGlassToneInkDark = Color(0xFF000000);

/// 浅色一套：底衬偏暗时用。纯白——只有它能在阈值上边缘仍拿到 4.5。
const Color appGlassToneInkLight = Color(0xFFFFFFFF);

/// 采样不可用时按主题亮度回退：浅色主题用深墨（页面底色亮），深色主题用白。
///
/// 这是「保守」的那一档：没有采样就按最常见的情形（背后就是页面底色）选，
/// 而不是去赌某张照片。实测页面底色底衬上的对比度：浅色 19.5:1、深色
/// 19.9:1（test/glass_tone_test.dart）。
const Color appGlassToneFallbackLightTheme = appGlassToneInkDark;
const Color appGlassToneFallbackDarkTheme = appGlassToneInkLight;

/// 采样到的背景色 → 文字实际落上去的那块**不透明**底衬（scrim 叠在背景上）。
Color appGlassToneBackplate(Color backdrop) =>
    AppAccent.compositeOver(appGlassPremiumScrimColor(), backdrop);

/// 采样到的背景色 → 合成底衬的 WCAG 相对亮度（阈值比的就是这个数）。
double appGlassToneBackplateLuminance(Color backdrop) =>
    AppAccent.relativeLuminance(appGlassToneBackplate(backdrop));

/// 按底衬亮度选墨色：≥ [appGlassToneThreshold] 深色一套，否则浅色一套。
Color appGlassToneInkForLuminance(double backplateLuminance) =>
    backplateLuminance >= appGlassToneThreshold
        ? appGlassToneInkDark
        : appGlassToneInkLight;

/// 按背景代表色选墨色；[backdrop] 为 null（还没采到 / 采样失败）时按主题回退。
Color appGlassToneInkForBackdrop(Color? backdrop) => backdrop == null
    ? (AppColors.isDark
        ? appGlassToneFallbackDarkTheme
        : appGlassToneFallbackLightTheme)
    : appGlassToneInkForLuminance(appGlassToneBackplateLuminance(backdrop));

/// 这一帧该用的墨色：读 [AppBackdropSample] 最近一次采样。
Color appGlassToneInk() => appGlassToneInkForBackdrop(AppBackdropSample.color.value);

/// **没有底衬**的表面（透明日期条）上的墨色：底衬就是采样到的背景本身。
///
/// [appGlassToneInk] 的底衬是「scrim 叠背景」——玻璃条里面那层 55% 的页面底色
/// （[appGlassToneBackplate]）。内容流里的日期条完全透明，文字直接压在背景图
/// 上，没有那层 scrim，所以这里直接比背景亮度：阈值仍是
/// [appGlassToneThreshold]（它本来就是黑/白两套墨色的交叉点，而不是 0.5）。
///
/// 四种极端背景（纯白/纯黑/纯红/纯蓝）× 明暗实测最坏 4.58:1，见
/// test/pinned_chrome_bar_test.dart 与 test/date_header_backdrop_test.dart。
Color appGlassToneInkBare(Color? backdrop) => backdrop == null
    ? (AppColors.isDark
        ? appGlassToneFallbackDarkTheme
        : appGlassToneFallbackLightTheme)
    : appGlassToneInkForLuminance(AppAccent.relativeLuminance(backdrop));

/// 同 [appGlassToneBuilder]，但走**没有底衬**那一档（[appGlassToneInkBare]）。
Widget appGlassBareToneBuilder(
  Widget Function(BuildContext context, Color ink) builder,
) =>
    ValueListenableBuilder<Color?>(
      valueListenable: AppBackdropSample.color,
      builder: (context, backdrop, _) =>
          builder(context, appGlassToneInkBare(backdrop)),
    );

/// 随采样结果重建：[builder] 拿到的就是当前该用的墨色。
///
/// 采样一变（换背景图 / 换主题）胶囊里的文字与图标跟着换，切完就不再重建。
Widget appGlassToneBuilder(
  Widget Function(BuildContext context, Color ink) builder,
) =>
    ValueListenableBuilder<Color?>(
      valueListenable: AppBackdropSample.color,
      builder: (context, backdrop, _) =>
          builder(context, appGlassToneInkForBackdrop(backdrop)),
    );

/// 非文字控件（图标）的最低对比度：WCAG 1.4.11 的非文字对比 3:1。
const double appGlassToneAccentMinContrast = 3.0;

/// 图标色：主题色在底衬上够 3:1 就保留主题色（品牌色别乱换），不够就换墨色。
///
/// 上传按钮的「+」是主色图标：底衬正常时它是紫的（浅色 4.13:1，够非文字对比），
/// 压在纯黑/纯红照片上只剩 1.25/1.88，那时换成墨色才是可读的。
Color appGlassReadableAccent(Color preferred, {Color? backdrop}) {
  final backplate = appGlassToneBackplate(backdrop ?? AppColors.bgPage);
  return AppAccent.contrastRatio(backplate, preferred) >=
          appGlassToneAccentMinContrast
      ? preferred
      : appGlassToneInkForBackdrop(backdrop);
}
