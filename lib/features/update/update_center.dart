import 'dart:async';

import '../../core/patch/patch_service.dart';
import '../../models/app_release.dart';
import 'update_service.dart';

/// 一次更新检测的结论。
///
/// 补丁优先：[patch] 非空时 [release] 一定是 null——能热更新就不再拿 APK
/// 更新去挡启动，只有补丁覆盖不到的原生改动才走安装包。
class UpdateCheckResult {
  final AppRelease? release;
  final PatchInfo? patch;

  /// 补丁已下载并落盘，等下次冷启动生效。
  final bool patchApplied;

  const UpdateCheckResult({this.release, this.patch, this.patchApplied = false});

  bool get hasPatch => patch != null;
  bool get hasRelease => release != null;

  static const UpdateCheckResult none = UpdateCheckResult();
}

/// 更新检测的唯一入口：补丁与 APK 的任务并行查询，再按「补丁优先」下结论。
///
/// 以前是「先等 APK 检查完 → 再在后台查补丁」，只要服务端发了新 APK，补丁就
/// 永远轮不到；现在两个请求同时发、结论只有一个。启动路径只等查询（
/// [downloadPatch] = false，下载交给后台），手动检查才等下载。
class UpdateCenter {
  UpdateCenter._();

  /// 查询更新。[downloadPatch] 为 true 时顺带下载补丁（手动检查用）。
  ///
  /// [probePatch] / [probeRelease] / [applyPatch] 是测试注入点，正常路径不传。
  static Future<UpdateCheckResult> check({
    bool downloadPatch = false,
    Future<PatchInfo?> Function()? probePatch,
    Future<AppRelease?> Function()? probeRelease,
    Future<bool> Function(PatchInfo patch)? applyPatch,
  }) async {
    // 两个请求同时发：慢的那个不把快的拖成串行等待。
    final patchFuture = (probePatch ?? PatchService.fetchAvailable)();
    final releaseFuture = (probeRelease ?? UpdateService.check)();
    final patch = await patchFuture;
    var applied = false;
    if (patch != null && downloadPatch) {
      applied = await (applyPatch ?? PatchService.apply)(patch);
      if (!applied) {
        // 补丁装不上（原生拒绝、黑名单、文件校验失败……）：退回安装包更新，
        // 别让用户卡在「补丁下载失败」这一条死路上。
        final release = await releaseFuture.catchError((_) => null);
        return UpdateCheckResult(
          patch: patch,
          release: release,
          patchApplied: false,
        );
      }
    }
    if (patch != null) {
      // 补丁优先：APK 的结论已经用不上了，别再等它把启动拖长；异常自己吞掉。
      unawaited(releaseFuture.catchError((_) => null));
      return resolve(patch: patch, release: null, patchApplied: applied);
    }
    final release = await releaseFuture;
    return resolve(patch: null, release: release, patchApplied: applied);
  }

  /// 纯决策：有补丁就压掉 APK 更新。单独抽出来是为了能不碰网络地测。
  static UpdateCheckResult resolve({
    required PatchInfo? patch,
    required AppRelease? release,
    bool patchApplied = false,
  }) {
    if (patch != null) {
      return UpdateCheckResult(patch: patch, patchApplied: patchApplied);
    }
    return UpdateCheckResult(release: release);
  }
}
