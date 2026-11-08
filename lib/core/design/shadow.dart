import 'package:flutter/material.dart';

class AppShadow {
  static const card = [
    BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 2)),
  ];
  static const fab = [
    BoxShadow(color: Color(0x1A4A6CF7), blurRadius: 20, offset: Offset(0, 6)),
  ];
  static const dialog = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 32, offset: Offset(0, 12)),
  ];
}
