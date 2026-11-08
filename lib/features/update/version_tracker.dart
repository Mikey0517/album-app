import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VersionTracker {
  static const _kLastRunCode = 'last_run_version_code';

  /// true 表示当前 versionCode 第一次运行（首次安装时 lastRun 为 0，也会返回 true）。
  static Future<bool> isFirstRunOfCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      final prefs = await SharedPreferences.getInstance();
      final lastRun = prefs.getInt(_kLastRunCode) ?? 0;
      return currentCode > lastRun;
    } catch (_) {
      return false;
    }
  }

  /// 必须在更新日志对话框关闭之后调用。
  static Future<void> markCurrentVersionRun() async {
    final info = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(info.buildNumber) ?? 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastRunCode, currentCode);
  }
}
