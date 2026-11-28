import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 全屏视频播放时隐藏系统状态栏。
///
/// 优先走原生 `album/app` 通道的 `setImmersive`（WindowInsetsController）：
/// HyperOS + edgeToEdge 下只靠 Flutter 的 SystemChrome 会被框架的 overlay
/// style 覆盖，状态栏仍可见。通道不可用（iOS/测试）时退回 SystemChrome。
class ViewerImmersive {
  ViewerImmersive._();

  static const MethodChannel _channel = MethodChannel('album/app');

  static Future<void> set(bool hidden) async {
    try {
      await _channel.invokeMethod<bool>('setImmersive', {'hidden': hidden});
      return;
    } catch (e) {
      debugPrint('原生沉浸式不可用，退回 SystemChrome: $e');
    }
    try {
      await SystemChrome.setEnabledSystemUIMode(
        hidden ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } catch (_) {
      // 桌面/测试环境没有系统栏，忽略。
    }
  }
}
