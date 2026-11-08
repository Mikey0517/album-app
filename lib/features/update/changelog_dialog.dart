import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/shadow.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';

/// 展示打包进 APK 的 assets/changelog.md。
/// 首次安装与每次升级后的第一次启动都会调用，是否记录由调用方在对话框关闭后决定。
Future<void> showChangelogDialog(
  BuildContext context,
  String versionName,
) async {
  String notes;
  try {
    notes = await rootBundle.loadString('assets/changelog.md');
  } catch (_) {
    notes = '';
  }
  if (notes.trim().isEmpty) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    useSafeArea: true,
    builder: (context) {
      return PopScope(
        canPop: false,
        child: _ChangelogDialog(versionName: versionName, notes: notes),
      );
    },
  );
}

class _ChangelogDialog extends StatelessWidget {
  final String versionName;
  final String notes;

  const _ChangelogDialog({required this.versionName, required this.notes});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 420,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: AppShadow.dialog,
        ),
        child: SingleChildScrollView(
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
                  Icons.celebration_outlined,
                  size: 28,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '已更新到 v$versionName',
                style: AppText.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                '以下是本次更新内容',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 300),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    notes.trim(),
                    style: AppText.bodySmall.copyWith(
                      height: 1.7,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
