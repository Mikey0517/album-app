import 'dart:io';

import 'package:flutter/material.dart';

import 'media_store.dart';

/// 平台判定：删除系统相册原图只有 Android 有原生实现，iOS 上不提示。
///
/// 做成可替换的函数变量是因为单测跑在桌面上，[Platform.isAndroid] 恒为 false，
/// 没法直接测「Android 上会弹窗」这条分支。
@visibleForTesting
bool Function() sourceCleanupPlatformCheck = _platformIsAndroid;

bool _platformIsAndroid() => Platform.isAndroid;

/// 当前平台能不能删系统相册原图。
bool get supportsSourceMediaCleanup => sourceCleanupPlatformCheck();

/// 上传/发布完成后，把这一批原图直接交给系统删除。
///
/// **确认只由系统弹**：Android 11+ 的 `createDeleteRequest` 会列出这些照片、
/// 让用户点一次「允许」。App 自己不再多弹一层「删除手机里的原图？」——两层
/// 确认问的是同一件事，多一层只是多一次点击，而且页面刚好被关掉时那一层还会
/// 弹不出来。
///
/// 删除本身不挡页面流程：调用方拿到结果后用 snackbar 说清楚删了几张、失败的
/// 原因（取消 / 系统拒绝 / 找不到原图）。
Future<void> deleteSourceMedia(
  List<SourceTarget> items, {
  required ScaffoldMessengerState? messenger,
}) async {
  if (items.isEmpty || !supportsSourceMediaCleanup) return;
  final result = await MediaStore.deleteSources(items);
  messenger?.showSnackBar(
    SnackBar(content: Text(sourceDeleteMessage(result))),
  );
}

/// 删除结果的文案：说清删了几张、剩下的为什么没删掉。
///
/// 以前这里直接把原生异常原文（IllegalArgumentException: All requested items
/// must be referenced by specific ID）塞给用户，等于什么都没说，现在按原因讲人话。
@visibleForTesting
String sourceDeleteMessage(SourceDeleteResult result) {
  if (result.deleted > 0) {
    if (result.failed == 0) return '已删除 ${result.deleted} 张原图';
    return '已删除 ${result.deleted} 张，${result.failed} 张未能删除';
  }
  if (result.reason == SourceDeleteFailure.userCancelled) {
    return '已取消删除，手机相册里的原图还在';
  }
  if (result.failed <= 0) return '没能删除，请稍后在系统相册里手动删除';
  final reasonText = sourceDeleteFailureText(result.reason);
  // 厂商相册/文件选择器的 URI 不是标准相册条目时，带上来源，方便定位是哪一家。
  final provider = result.provider;
  final providerText = provider == null ? '' : '（来源：$provider）';
  return '${result.failed} 项无法删除：$reasonText$providerText，请到系统相册里手动删除';
}

/// 失败原因 → 用户能看懂的一句话。
@visibleForTesting
String sourceDeleteFailureText(SourceDeleteFailure? reason) {
  switch (reason) {
    case SourceDeleteFailure.userCancelled:
      return '你在系统确认框里点了取消';
    case SourceDeleteFailure.notFound:
      return '手机相册里已经找不到这些条目';
    case SourceDeleteFailure.typeMismatch:
      return '照片和视频的类型对不上';
    case SourceDeleteFailure.unsupported:
      return '这些条目不在手机相册里';
    case SourceDeleteFailure.unresolvedPicker:
      return '系统没能把它们换成相册条目';
    case SourceDeleteFailure.systemRejected:
    case null:
      return '系统不允许这个相册条目被第三方删除';
  }
}
