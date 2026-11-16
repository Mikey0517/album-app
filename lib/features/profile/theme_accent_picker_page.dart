import 'package:flutter/material.dart';

import '../../core/app_accent_controller.dart';
import '../../core/design/accent.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';

/// 打开 HSV 取色页，返回用户选的颜色；用户取消（返回键 / 侧滑）是 null。
///
/// 主题色、页面背景的纯色、双色渐变的两个色标都用它：取色这件事只有一份实现
/// （[HsvColorPickerPage] 的三条 Slider），谁要颜色谁调这个函数。
Future<Color?> pickHsvColor(
  BuildContext context, {
  required Color initial,
  required String title,
}) {
  return Navigator.of(context).push<Color>(
    MaterialPageRoute<Color>(
      builder: (_) => HsvColorPickerPage(initial: initial, title: title),
    ),
  );
}

/// 自定义主题色：整页取色，保存后写回 [AppAccentController] 并落盘。
///
/// 只是 [HsvColorPickerPage] 的一层「保存到哪里」的包装：主题色和页面背景的
/// 纯色 / 渐变两个色标共用同一个取色器，不各写一份。
class ThemeAccentPickerPage extends StatelessWidget {
  const ThemeAccentPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return HsvColorPickerPage(
      initial: AppAccentController.seed.value,
      title: '自定义主题色',
      onSave: AppAccentController.setSeed,
    );
  }
}

/// 只用 Slider 拼出 色相 / 饱和度 / 明度 三条通道，顶部大圆实时预览。
///
/// [onSave] 为 null：「保存」把选中的颜色 pop 回去（[pickHsvColor] 走这条）；
/// 非 null：先交给调用点落盘，再关页面（路由结果类型是 void，不往回带颜色）。
class HsvColorPickerPage extends StatefulWidget {
  const HsvColorPickerPage({
    super.key,
    required this.initial,
    required this.title,
    this.onSave,
  });

  /// 进来时的初始颜色（决定三条 Slider 的起点）。
  final Color initial;

  /// 页面标题（「自定义主题色」/「纯色背景」/「起始色」…）。
  final String title;

  /// 保存回调；为空表示「把颜色 pop 回去」。
  final Future<void> Function(Color color)? onSave;

  @override
  State<HsvColorPickerPage> createState() => _HsvColorPickerPageState();
}

class _HsvColorPickerPageState extends State<HsvColorPickerPage> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = AppAccent.hsvOf(widget.initial);
  }

  Future<void> _save() async {
    final color = _color;
    final onSave = widget.onSave;
    if (onSave != null) {
      await onSave(color);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (mounted) Navigator.of(context).pop(color);
  }

  Color get _color =>
      HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, _hsv.value).toColor();

  @override
  Widget build(BuildContext context) {
    final hue = _hsv.hue;
    final saturation = _hsv.saturation;
    final value = _hsv.value;
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _color,
                border: Border.all(color: AppColors.borderLight),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              _hex(_color),
              style: AppText.caption.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _HsvSlider(
            label: '色相',
            valueLabel: '${hue.round()}°',
            value: hue,
            min: 0,
            max: 360,
            gradient: const [
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
            onChanged: (next) => setState(
              () => _hsv = _hsv.withHue(next),
            ),
          ),
          _HsvSlider(
            label: '饱和度',
            valueLabel: '${(saturation * 100).round()}%',
            value: saturation,
            min: 0,
            max: 1,
            gradient: [
              HSVColor.fromAHSV(1, hue, 0, value).toColor(),
              HSVColor.fromAHSV(1, hue, 1, value).toColor(),
            ],
            onChanged: (next) => setState(
              () => _hsv = _hsv.withSaturation(next),
            ),
          ),
          _HsvSlider(
            label: '明度',
            valueLabel: '${(value * 100).round()}%',
            value: value,
            min: 0,
            max: 1,
            gradient: [
              const Color(0xFF000000),
              HSVColor.fromAHSV(1, hue, saturation, 1).toColor(),
            ],
            onChanged: (next) => setState(
              () => _hsv = _hsv.withValue(next),
            ),
          ),
        ],
      ),
    );
  }

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _HsvSlider extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final List<Color> gradient;
  final ValueChanged<double> onChanged;

  const _HsvSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.gradient,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: AppText.caption),
            const Spacer(),
            Text(valueLabel, style: AppText.caption),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 渐变条自己画，Slider 的轨道透明叠在上面，只保留拖拽和滑块。
              Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  gradient: LinearGradient(colors: gradient),
                ),
              ),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 12,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: AppColors.primary.withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 9,
                    elevation: 1.5,
                    pressedElevation: 3,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  value: value.clamp(min, max).toDouble(),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
