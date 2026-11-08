import 'package:flutter/widgets.dart';

/// 手机宽度下返回 [phoneColumns]；平板/横屏时适当增加列数。
///
/// iPad 竖屏约 768~834、横屏 1024~1366，分屏会窄到 320~680，
/// 所以只按当前可用宽度判断，不依赖设备类型。
int responsiveColumns(BuildContext context, int phoneColumns) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 1100) return phoneColumns + 2;
  if (width >= 760) return phoneColumns + 1;
  return phoneColumns;
}

/// 单列内容（朋友圈、发布页等）在平板上限制最大宽度，避免被拉得太宽。
double responsiveContentWidth(BuildContext context, {double maxWidth = 680}) {
  final width = MediaQuery.sizeOf(context).width;
  return width > maxWidth ? maxWidth : width;
}
