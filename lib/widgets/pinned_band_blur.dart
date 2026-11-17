import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 吸顶横条上那层「很轻的模糊」的 sigma。取值理由见 [PinnedBandBlur]。
const double kPinnedBandBlur = 7;

/// 吸顶横条（日期分组条 / 分类筛选条）压在滚动内容上时的那层兜底模糊。
///
/// 两条横条的底衬都是主题色浅渐变（[BarTint]：浅色 alpha 0.10 → 0.02、深色
/// 0.14 → 0.04）。这层渐变很淡，实测只把条纹纹理压掉约一成（0.90×），滚过的
/// 照片会一条条从字后面透出来——用户要的是「浅」，所以不靠把底衬调厚来解决。
///
/// 分工：
/// - **非吸顶**的那一份（内容流里的日期头、封面选择页 AppBar 里的筛选条）下面
///   没有东西经过，保持纯渐变、不套这一层；
/// - **吸顶**的那一份套上它：模糊先作用于背后内容（高频纹理被揉开），渐变与
///   文字再画在模糊之上，条带里的纹理残留 < 0.02（实测见
///   test/date_header_backdrop_test.dart / test/segmented_bar_backdrop_test.dart）。
///
/// 它和「下拉刷新时整条发黑」**无关**：黑条来自 premium 玻璃的 capture 未就绪，
/// 这一层是纯 [BackdropFilter]，不抓 capture；刷新全程它也不重建（同一帧同一个
/// Element），逐帧无黑见 test/refresh_black_bar_test.dart。
class PinnedBandBlur extends StatelessWidget {
  final Widget child;

  /// 模糊半径（sigma）；<= 0 表示不模糊，直接返回 child。
  final double blur;

  const PinnedBandBlur({
    super.key,
    required this.child,
    this.blur = kPinnedBandBlur,
  });

  /// 模糊层的 key：测试用它断言「吸顶那一条带着这层兜底、非吸顶的没有」。
  static const Key blurKey = ValueKey<String>('pinned-band-blur');

  @override
  Widget build(BuildContext context) {
    if (blur <= 0) return child;
    return ClipRect(
      child: BackdropFilter(
        key: blurKey,
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: child,
      ),
    );
  }
}
