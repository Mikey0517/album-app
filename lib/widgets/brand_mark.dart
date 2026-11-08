import 'package:flutter/material.dart';

import '../core/design/colors.dart';

/// App icon / wordmark mark used on boot and login screens.
class BrandMark extends StatelessWidget {
  final double size;
  final bool shadow;

  const BrandMark({super.key, this.size = 72, this.shadow = true});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.225;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.24),
                  blurRadius: size * 0.24,
                  offset: Offset(0, size * 0.10),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/brand_mark.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
