import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design/accent.dart';

/// 主题色的运行时状态与持久化。
///
/// 只暴露一个 [seed]（用户选中的颜色，未做明暗微调）。`AppColors.primary`
/// 读它现算实际主色，所以换色只需要改这里 + 让根节点重建。
class AppAccentController {
  AppAccentController._();

  static const String _key = 'app_accent_color';

  static final ValueNotifier<Color> seed = ValueNotifier<Color>(AppAccent.brand);

  /// 冷启动恢复：读不到/读坏都退回品牌默认色，不阻塞启动。
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_key);
      seed.value =
          stored == null ? AppAccent.brand : AppAccent.clamp(Color(stored));
    } catch (_) {
      seed.value = AppAccent.brand;
    }
  }

  /// 切换主题色。[persist] 为 false 时只改内存（取色器拖动预览用）。
  static Future<void> setSeed(Color value, {bool persist = true}) async {
    final next = AppAccent.clamp(value);
    if (seed.value != next) seed.value = next;
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, next.value);
    } catch (_) {
      // 落盘失败不影响本次生效，下次冷启动回到上一次成功保存的颜色。
    }
  }

  /// 当前颜色是否正好命中某个预设（设置页/取色器用来高亮）。
  static bool isPreset(Color value) => AppAccent.presets
      .any((preset) => preset.color.value == AppAccent.clamp(value).value);
}
