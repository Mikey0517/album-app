import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/text_styles.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;

  /// 可选：能靠标题讲清楚的地方就别加副标题（AGENTS.md 的文案规则）。
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 14),
            Text(title,
                style: AppText.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: AppText.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              SizedBox(width: 200, child: action),
            ],
          ],
        ),
      ),
    );
  }
}
