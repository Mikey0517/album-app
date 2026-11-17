import 'package:flutter/material.dart';

import 'accent.dart';
import 'colors.dart';

/// 吸顶横条（日期分组条 / 分类筛选条）底衬的**唯一**一份定义：主题色浅渐变。
///
/// 两条横条曾经各走一条「透明 + 模糊」的路（日期条 blur 8、分类条 blur 8），
/// 用户反馈「模糊透明有点奇怪」：文字后面是一层说不清材质的雾，又没有真的
/// 挡住什么。现在统一成同一套浅渐变——底衬是主题色本身，只是很淡。
///
/// 参数（纵向，上沿 → 下沿）：
/// - 浅色：alpha 0.10 → 0.02（叠在 #F7F8FA 上约 #E6EAFA → #F4F5FA）；
/// - 深色：alpha 0.14 → 0.04（叠在 #0E1118 上约 #202638 → #131721）。
///
/// 两端都远低于 1，所以页面背景的渐变/图片照样透上来（不是色块、不是实底），
/// 只是被主题色轻轻染了一层；[maxAlpha] 是这份参数的验收上限，两条横条都不许
/// 超过它，超过就不再是「浅」渐变。
class BarTint {
  BarTint._();

  /// 渐变起点（条带上沿）的 alpha。
  static double get startAlpha => AppColors.isDark ? 0.14 : 0.10;

  /// 渐变终点（条带下沿）的 alpha。
  static double get endAlpha => AppColors.isDark ? 0.04 : 0.02;

  /// 任意明暗模式下允许的最大 alpha：验收断言的上限，改参数先过这一关。
  static const double maxAlpha = 0.16;

  /// 底衬渐变：主题色从上沿 100% 到 0% 的强度，纵向走一遍。
  ///
  /// 每一步都现读 [AppColors.primary] / [AppColors.isDark]，所以换主题色、切
  /// 明暗模式后重建即生效，调用点不用缓存。
  static LinearGradient get gradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[at(0), at(1)],
      );

  /// 渐变在 [t]（0 = 上沿，1 = 下沿）处的颜色。
  static Color at(double t) {
    final clamped = t.clamp(0.0, 1.0);
    return AppColors.primary.withValues(
      alpha: startAlpha + (endAlpha - startAlpha) * clamped,
    );
  }

  /// [t] 处的底衬压在 [over]（默认页面底色）上的合成色。
  ///
  /// 对比度断言用：半透明渐变对文字没有意义，先合成出一块不透明底衬再算。
  static Color backplateAt(double t, {Color? over}) =>
      AppAccent.compositeOver(at(t), over ?? AppColors.bgPage);
}
