import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/text_styles.dart';

class SelectionFooterAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const SelectionFooterAction({
    required this.icon,
    required this.label,
    this.onTap,
  });
}

class SelectionFooter extends StatelessWidget {
  final List<SelectionFooterAction> actions;
  final bool safeArea;

  const SelectionFooter({
    super.key,
    required this.actions,
    this.safeArea = false,
  });

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          for (final action in actions)
            Expanded(
              child: InkWell(
                onTap: action.onTap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      action.icon,
                      size: 22,
                      color: action.onTap == null
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      action.label,
                      style: AppText.caption.copyWith(
                        color: action.onTap == null
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (!safeArea) return bar;
    return SafeArea(top: false, child: bar);
  }
}
