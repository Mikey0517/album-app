import 'package:flutter/material.dart';

import 'colors.dart';

class AppText {
  static const titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.3,
  );

  static const titleMedium = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.2,
  );

  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.55,
    letterSpacing: 0.1,
  );

  static const bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: Color(0xFF8A93A6),
  );

  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: Color(0xFF8A93A6),
  );

  static const button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static const sectionLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: Color(0xFF8A93A6),
  );

  /// [caption] 落在**玻璃**上的版本：同样的字号/字重，只把颜色换成
  /// [AppColors.textOnGlass]。
  ///
  /// [caption] 的 #8A93A6 对玻璃合成底色只有 ≈2.8:1（浅色），真机上版本号、
  /// 相册张数、「新建相册」这类小字就看不清了；这条给 ≥4.5:1。
  /// 因为它读运行时明暗模式，所以是 getter，不是 const。
  static TextStyle get captionOnGlass =>
      caption.copyWith(color: AppColors.textOnGlass);
}
