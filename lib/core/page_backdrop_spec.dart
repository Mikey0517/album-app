import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 页面背景的四种形态。
///
/// 以前只有「默认渐变 / 一张图」两态，图片路径是唯一的状态；现在多了纯色与
/// 双色渐变，光靠一个 String 已经表达不了，于是统一成 [PageBackdropSpec]。
enum PageBackdropType {
  /// 品牌渐变：主题色对角线 + 两团光斑（[AppGlassBackdrop] 自己画的那套）。
  defaultGradient,

  /// 纯色：用户选的一个颜色铺满整页。
  color,

  /// 双色渐变：左上 → 右下，两个色标各自可选。
  gradient,

  /// 自定义图片：私有目录里的副本，上面盖一层可读性遮罩。
  image,
}

/// 「我的 → 页面背景」的统一模型：**一个 spec 决定整页底色**。
///
/// 为什么不只存图片路径：四种形态都要能被持久化、被渲染层与设置项读到同一个
/// 状态。用「类型 + 对应字段」的单一对象，比散在多个 key 里好判断「现在是什
/// 么」——设置页那一行文案、弹层里的勾选态、AppGlassBackdrop 画哪一层，全都
/// 从同一个 spec 推出来，不会出现「文案说自定义、页面还是渐变」的错位。
///
/// 不变式（构造器与 [fromMap] 一起保证）：
/// - [type] == [PageBackdropType.color] 时 [color] 非空；
/// - [type] == [PageBackdropType.gradient] 时 [gradientStart]/[gradientEnd] 非空；
/// - [type] == [PageBackdropType.image] 时 [imagePath] 非空。
///
/// 持久化就是 [toJson] 的 JSON（见 [encode]），键名刻意短而稳定；旧版本只存
/// 图片路径的那个 key 由 PageBackdropController 迁移成 [PageBackdropSpec.image]。
@immutable
class PageBackdropSpec {
  const PageBackdropSpec._({
    required this.type,
    this.color,
    this.gradientStart,
    this.gradientEnd,
    this.imagePath,
  });

  /// 品牌渐变（默认）。
  const PageBackdropSpec.defaultGradient()
      : this._(type: PageBackdropType.defaultGradient);

  /// 纯色。
  const PageBackdropSpec.solid(Color color)
      : this._(type: PageBackdropType.color, color: color);

  /// 双色渐变（左上 → 右下）。
  const PageBackdropSpec.gradient({
    required Color start,
    required Color end,
  }) : this._(
          type: PageBackdropType.gradient,
          gradientStart: start,
          gradientEnd: end,
        );

  /// 自定义图片（持久化的私有目录副本路径）。
  const PageBackdropSpec.image(String path)
      : this._(type: PageBackdropType.image, imagePath: path);

  final PageBackdropType type;

  /// [PageBackdropType.color] 时有效。
  final Color? color;

  /// [PageBackdropType.gradient] 时的起始色（左上）。
  final Color? gradientStart;

  /// [PageBackdropType.gradient] 时的结束色（右下）。
  final Color? gradientEnd;

  /// [PageBackdropType.image] 时的图片路径。
  final String? imagePath;

  bool get isDefault => type == PageBackdropType.defaultGradient;

  bool get isColor => type == PageBackdropType.color;

  bool get isGradient => type == PageBackdropType.gradient;

  bool get isImage => type == PageBackdropType.image;

  /// 设置页那一行右侧的文案。
  String get label => switch (type) {
        PageBackdropType.defaultGradient => '默认渐变',
        PageBackdropType.color => '纯色',
        PageBackdropType.gradient => '渐变',
        PageBackdropType.image => '自定义',
      };

  /// 持久化用的 JSON 视图。
  ///
  /// 颜色存成 ARGB 整数（[Color.toARGB32]）：JSON 里就是一个数字，不依赖
  /// '#RRGGBBAA' 这类字符串格式，也把 alpha 一起带上（目前恒为 0xFF，但模型
  /// 不该假设调用点总是给不透明色）。
  Map<String, Object?> toJson() => switch (type) {
        PageBackdropType.defaultGradient => const {'type': 'default'},
        PageBackdropType.color => {
            'type': 'color',
            'color': color!.toARGB32(),
          },
        PageBackdropType.gradient => {
            'type': 'gradient',
            'start': gradientStart!.toARGB32(),
            'end': gradientEnd!.toARGB32(),
          },
        PageBackdropType.image => {
            'type': 'image',
            'path': imagePath!,
          },
      };

  /// 落盘用的字符串（[toJson] 的 JSON 编码）。
  String encode() => jsonEncode(toJson());

  /// 从 [toJson] 的视图还原；缺字段 / 类型不对一律返回 null（调用点回退默认）。
  static PageBackdropSpec? fromMap(Map<Object?, Object?> map) {
    switch (map['type']) {
      case 'default':
        return const PageBackdropSpec.defaultGradient();
      case 'color':
        final color = _colorOrNull(map['color']);
        return color == null ? null : PageBackdropSpec.solid(color);
      case 'gradient':
        final start = _colorOrNull(map['start']);
        final end = _colorOrNull(map['end']);
        if (start == null || end == null) return null;
        return PageBackdropSpec.gradient(start: start, end: end);
      case 'image':
        final path = map['path'];
        if (path is! String || path.isEmpty) return null;
        return PageBackdropSpec.image(path);
      default:
        return null;
    }
  }

  /// 从 [encode] 的字符串还原；空串、坏 JSON、缺字段都是 null。
  static PageBackdropSpec? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    return fromMap(json);
  }

  /// 只认 [toJson] 写出去的那个形态：ARGB 整数。
  ///
  /// 不接受 '#RRGGBB' 之类的字符串——那种写法丢了 alpha，读回来会是透明色，
  /// 比「读不出来就回退默认」更糟。
  static Color? _colorOrNull(Object? value) {
    if (value is int) return Color(value);
    if (value is num) return Color(value.toInt());
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PageBackdropSpec &&
        other.type == type &&
        _argb(other.color) == _argb(color) &&
        _argb(other.gradientStart) == _argb(gradientStart) &&
        _argb(other.gradientEnd) == _argb(gradientEnd) &&
        other.imagePath == imagePath;
  }

  @override
  int get hashCode => Object.hash(
        type,
        _argb(color),
        _argb(gradientStart),
        _argb(gradientEnd),
        imagePath,
      );

  static int? _argb(Color? color) => color?.toARGB32();

  @override
  String toString() => 'PageBackdropSpec(${toJson()})';
}
