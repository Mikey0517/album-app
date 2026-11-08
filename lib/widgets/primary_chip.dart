import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/radius.dart';
import '../core/design/text_styles.dart';

class PrimaryChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  const PrimaryChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: AppText.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: foreground,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
