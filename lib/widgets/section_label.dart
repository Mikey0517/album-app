import 'package:flutter/material.dart';

import '../core/design/text_styles.dart';

class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const SectionLabel({
    super.key,
    required this.text,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(text, style: AppText.sectionLabel),
    );
  }
}
