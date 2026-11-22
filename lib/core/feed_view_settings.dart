import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 朋友圈动态媒体的两种看法，开关在「我的」里（[widescreen]）：
///
/// - 关（默认）：九宫格。每条动态套卡片，缩略图铺成三列格子，信息最密；
/// - 开：大屏。照片铺满屏宽、直接用原图（不走 400px 缩略图），按屏幕高度收
///   一道上限，一张一张看。
///
/// 以前这个切换在每条动态右上角、逐条记忆；现在只有一份全局状态：同一个开关
/// 决定整个朋友圈怎么看，不在「这条大图、那条九宫格」之间摇摆。
class FeedViewSettings {
  FeedViewSettings._();

  /// SharedPreferences 里的键。
  static const String prefsKey = 'feed_widescreen';

  /// 大屏模式，默认关闭（= 九宫格）。
  static final ValueNotifier<bool> widescreen = ValueNotifier<bool>(false);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      widescreen.value = prefs.getBool(prefsKey) ?? false;
    } catch (_) {
      // 读不到设置就按默认（九宫格）走，不影响本次使用。
      widescreen.value = false;
    }
  }

  static Future<void> setWidescreen(bool value) async {
    widescreen.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, value);
    } catch (_) {
      // 设置持久化失败不影响本次生效。
    }
  }
}
