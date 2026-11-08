import 'package:flutter/material.dart';

import '../core/design/colors.dart';
import '../core/design/text_styles.dart';

class LoadingView extends StatelessWidget {
  final String? message;
  final bool compact;

  const LoadingView({super.key, this.message, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message!, style: AppText.caption),
            ],
          ],
        ),
      ),
    );
  }
}
