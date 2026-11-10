import 'package:flutter/material.dart';

import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/text_styles.dart';

/// 补丁下载完成后的提示：不强制、不重启进程，用户点「好的」继续用，
/// 下次冷启动时补丁自然生效。
Future<void> showPatchReadyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.restart_alt,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '更新已准备好',
                style: AppText.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '重启 App 后生效。可以先继续使用，下次打开时会自动应用。',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: const Text('好的'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
