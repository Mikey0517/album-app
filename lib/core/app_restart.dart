import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 重启整个进程，让刚下载的 Dart 补丁在下次冷启动时被 flutter_patcher 装载。
///
/// 补丁只在 Application.attachBaseContext 里注入，跑着的进程换不掉，所以必须把
/// 进程整个换掉：Android 端由 MainActivity 的 album/app 通道起一个新的启动 Intent
/// 并结束当前进程；iOS 没有补丁逻辑，通道固定返回失败。
class AppRestart {
  AppRestart._();

  static const MethodChannel channel = MethodChannel('album/app');

  /// 返回 true 表示原生已接管（进程马上结束）；false 表示没成功，调用方自己兜底。
  ///
  /// 通道不存在、原生报错、取不到启动 Intent 都只算失败，绝不向上抛。
  static Future<bool> restart() async {
    try {
      final restarted = await channel.invokeMethod<bool>('restart');
      return restarted ?? false;
    } catch (e) {
      debugPrint('重启 App 失败: $e');
      return false;
    }
  }
}
