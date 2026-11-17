import 'package:flutter/material.dart';

import '../core/design/accent.dart';
import 'app_bottom_tab_bar.dart';

/// 胶囊未选中文字对底衬的最低对比度：WCAG AA 正文（4.5:1）。
const double appTabBarMinContrast = 4.5;

/// 胶囊文字实际落上去的那块底色：scrim 按 alpha-over 叠在**任意** [backdrop]
/// 上。
///
/// result = scrim * a + backdrop * (1 - a)，a = [appTabBarScrimAlpha]。
/// 这就是「照片 → 玻璃 → scrim」三层里的最后一层；玻璃自己的 tint
/// （[appGlassChromeTintColor] / [appGlassTintColor]）走的是包的 adaptive
/// 模式（亮度还给背景），所以「玻璃后面那张照片」≈ 原始背景本身——直接拿原始
/// 背景当输入，算出来的就是最坏情况，不需要再把 tint 叠一次。
Color appTabBarBackplateOver(Color backdrop) =>
    AppAccent.compositeOver(appTabBarScrimColor(), backdrop);

/// 未选中文字（默认 [appTabBarInactiveColor]）在 [backdrop] 上的对比度。
///
/// 传不传 [text] 都行：测试里用它钉住「四种极端背景都 ≥ [appTabBarMinContrast]」，
/// 也让「换成别的颜色会怎样」可以就地算。
double appTabBarContrastOver(Color backdrop, {Color? text}) =>
    AppAccent.contrastRatio(
      appTabBarBackplateOver(backdrop),
      text ?? appTabBarInactiveColor,
    );

/// 一种「极端背景」：给测试与文档共用的一份名字 + 颜色。
class AppTabBarBackdrop {
  const AppTabBarBackdrop(this.label, this.color);

  final String label;
  final Color color;
}

/// 四种极端背景：纯白、纯黑、高饱和红、高饱和蓝。
///
/// 这四种不是随手挑的：纯度 100% 的白与黑是「白墙照片 / 夜景照片」两端，
/// 高饱和红/蓝是**亮度介于两者之间、但色度极端**的那一类（夕阳、天空、
/// 衣服），单看亮度排序会漏掉它们。底衬要在这四种上都够稳，才算真的稳。
const List<AppTabBarBackdrop> appTabBarExtremeBackdrops = <AppTabBarBackdrop>[
  AppTabBarBackdrop('纯白', Color(0xFFFFFFFF)),
  AppTabBarBackdrop('纯黑', Color(0xFF000000)),
  AppTabBarBackdrop('高饱和红', Color(0xFFFF0000)),
  AppTabBarBackdrop('高饱和蓝', Color(0xFF0000FF)),
];

/// 四种极端背景里**最低**的那条对比度（当前明暗模式）。
///
/// 一个数就能说明「最坏情况下还有多少余量」，报告与断言都用它。
double appTabBarWorstContrast({Color? text}) => appTabBarExtremeBackdrops
    .map((backdrop) => appTabBarContrastOver(backdrop.color, text: text))
    .reduce((a, b) => a < b ? a : b);
