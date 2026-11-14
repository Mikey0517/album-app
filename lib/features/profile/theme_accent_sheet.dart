import 'package:flutter/material.dart';

import '../../core/app_accent_controller.dart';
import '../../core/design/accent.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';
import 'theme_accent_picker_page.dart';

/// 主题色选择：6 个预设 + 自定义（HSV 取色）。
///
/// 预设点一下立即生效并关掉面板；自定义进整页取色器。
Future<void> showThemeAccentSheet(BuildContext context) async {
  final custom = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (context) => const _ThemeAccentSheet(),
  );
  if (custom != true || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ThemeAccentPickerPage()),
  );
}

class _ThemeAccentSheet extends StatelessWidget {
  const _ThemeAccentSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<Color>(
        valueListenable: AppAccentController.seed,
        builder: (context, seed, child) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Text('主题色', style: AppText.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () => AppAccentController.setSeed(
                        AppAccent.brand,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        textStyle: AppText.bodySmall,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('恢复默认'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final preset in AppAccent.presets)
                      _AccentSwatch(
                        preset: preset,
                        selected: preset.color.toARGB32() == seed.toARGB32(),
                        onTap: () async {
                          await AppAccentController.setSeed(preset.color);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Divider(color: AppColors.divider, height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => Navigator.pop(context, true),
                  leading: _CustomSwatch(seed: AppAccentController.seed.value),
                  title: const Text('自定义', style: AppText.body),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  final AppAccentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _AccentSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: preset.label,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        containedInkWell: true,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: preset.color,
            border: Border.all(
              color: selected ? AppColors.textPrimary : AppColors.borderLight,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 18,
                  color: AppAccent.onColor(preset.color),
                )
              : null,
        ),
      ),
    );
  }
}

/// 自定义入口：色轮 + 当前主题色的小圆心。
class _CustomSwatch extends StatelessWidget {
  final Color seed;

  const _CustomSwatch({required this.seed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            for (var hue = 0; hue <= 360; hue += 60)
              HSVColor.fromAHSV(1, hue.toDouble(), 1, 1).toColor(),
          ],
        ),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
            border: Border.all(color: AppColors.bgSurface, width: 2),
          ),
        ),
      ),
    );
  }
}
