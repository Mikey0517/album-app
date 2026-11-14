import 'dart:io';

import 'package:flutter/material.dart';

import 'design/colors.dart';
import 'design/text_styles.dart';
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

/// 询问用户是否删除手机相册里的原图（与相册页同一套文案和按钮）。
///
/// 只有 Android 弹窗；[items] 为空、页面已销毁时不弹，直接返回 false。
/// [targetLabel] 是文案里的去处（相册页传相册名，动态页传「朋友圈」），
/// [action] 是「已上传到 / 已发布到」里的动词，各页面按自己的动作传入。
Future<bool> confirmDeleteSourceMedia(
  BuildContext context,
  List<SourceTarget> items, {
  required String targetLabel,
  String action = '上传到',
}) async {
  if (items.isEmpty || !supportsSourceMediaCleanup) return false;
  if (!context.mounted) return false;
  final targets = List<SourceTarget>.unmodifiable(items);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('删除手机里的原图？', style: AppText.titleMedium),
      content: Text(
        '${targets.length} 项已$action$targetLabel。\n'
        '删除后手机相册里就没有这些照片了，且无法恢复。',
        style: AppText.bodySmall,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
          child: const Text('保留'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// 真的去删系统相册原图，并按「全部删除 / 部分删除 / 全失败」提示结果。
///
/// [messenger] 由调用方在弹窗前取好：动态页会在删除开始前就关掉发布页，
/// 用提前拿到的 messenger 才能在页面销毁后仍然提示结果。
Future<void> deleteSourceMedia(
  List<SourceTarget> items, {
  required ScaffoldMessengerState messenger,
}) async {
  if (items.isEmpty) return;
  final result = await MediaStore.deleteSources(items);
  messenger.showSnackBar(
    SnackBar(content: Text(sourceDeleteMessage(result))),
  );
}

/// 删除结果的文案：三种分支和相册页原来的一致。
@visibleForTesting
String sourceDeleteMessage(SourceDeleteResult result) {
  if (result.deleted == 0) {
    final reason = result.error;
    if (reason == null || reason.isEmpty) {
      return '没能删除，请稍后在系统相册里手动删除';
    }
    return '没能删除（$reason），请到系统相册里手动删除';
  }
  if (result.isPartial) {
    return '已删除 ${result.deleted} 张，${result.failed} 张未能删除';
  }
  return '已删除 ${result.deleted} 张原图';
}
