import 'package:album_app/core/design/accent.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 玻璃上的文字对比度断言：文字色对「玻璃合成底色」必须 ≥ 4.5:1（WCAG AA）。
///
/// 底衬一次算三条，都是文字真的会落上去的那块颜色：
/// - premium 卡片：chrome tint（10%/7%）叠页面底色，卡片没有 scrim；
/// - 磨砂卡片：tint（15%/10%）叠页面底色（premium 不可用时的回退）；
/// - 不透明表面：[AppColors.bgSurface]（下拉刷新保持 / 平台不支持 shader）。
///
/// 浅色与深色各算一遍：浅色是最容易出事的那一档（原来的 caption #8A93A6 只有
/// ≈2.8:1），深色也不能因为「本来就是暗底」就跳过。
///
/// 传 getter 而不是值：token 的颜色取决于当前明暗模式，必须在 setDark 之后取。
void expectGlassTextReadable(
  TextStyle Function() style, {
  required String label,
}) {
  for (final dark in <bool>[false, true]) {
    AppColors.setDark(dark);
    final text = style();
    final color = text.color;
    expect(color, isNotNull, reason: '$label 必须显式带颜色（dark=$dark）');
    final backplates = <String, Color>{
      'premium 卡片': appGlassCardBackplate(),
      '磨砂卡片': appGlassCardBackplate(premium: false),
      '不透明表面': AppColors.bgSurface,
    };
    for (final entry in backplates.entries) {
      final ratio = AppAccent.contrastRatio(entry.value, color!);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$label 对「${entry.key}」的对比度（dark=$dark）：'
            '${ratio.toStringAsFixed(2)} < 4.5',
      );
    }
  }
  AppColors.setDark(false);
}
