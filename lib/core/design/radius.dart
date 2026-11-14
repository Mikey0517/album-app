import 'dart:ui';

class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;

  /// 紧密网格（相册缩略图）用的最小圆角：格间距只有 2px 时，
  /// 8px 会显得像 iOS 圆角卡片，4px 才是一整块马赛克。
  static const xs = 4.0;

  static const smRadius = Radius.circular(sm);
  static const mdRadius = Radius.circular(md);
  static const lgRadius = Radius.circular(lg);
  static const xlRadius = Radius.circular(xl);
  static const xsRadius = Radius.circular(xs);
  static const pillRadius = Radius.circular(pill);
}
