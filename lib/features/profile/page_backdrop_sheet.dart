import 'package:flutter/material.dart';

import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/text_styles.dart';
import '../../core/page_backdrop_controller.dart';
import '../../core/page_backdrop_spec.dart';
import 'theme_accent_picker_page.dart';

/// 「页面背景」弹层里能选的四类。
enum PageBackdropChoice {
  /// 品牌渐变（默认）。选了它就是「恢复默认」：顺带删掉旧图片副本。
  defaultGradient,

  /// 纯色：一个颜色，用 [pickHsvColor] 的 HSV 取色器选。
  color,

  /// 双色渐变：两个色标各自选色，方向固定左上 → 右下。
  gradient,

  /// 从相册选一张图（现有逻辑：压缩后复制进私有目录）。
  image,
}

/// 主弹层里的四个选项 key（测试按 key 找，不依赖文案）。
const Key pageBackdropDefaultKey = Key('page-backdrop-default');
const Key pageBackdropColorKey = Key('page-backdrop-color');
const Key pageBackdropGradientKey = Key('page-backdrop-gradient');
const Key pageBackdropPickKey = Key('page-backdrop-pick');

/// 渐变编辑层的两个色标 / 预览 / 保存 key。
const Key pageBackdropGradientStartKey = Key('page-backdrop-gradient-start');
const Key pageBackdropGradientEndKey = Key('page-backdrop-gradient-end');
const Key pageBackdropGradientPreviewKey =
    Key('page-backdrop-gradient-preview');
const Key pageBackdropGradientSaveKey = Key('page-backdrop-gradient-save');

/// 弹出「页面背景」选择层并执行选中的动作。
///
/// 三个页面共用一份背景，所以这里只是改 [PageBackdropController.spec] 的全局
/// 状态，不需要哪个页面自己 setState。
///
/// **成功不提示**：背景就铺在用户眼前，选完/恢复默认的效果本身就是反馈；
/// 再弹一条「背景已更新」只是挡视野的噪音（用户明确要求去掉）。用户在选择器
/// 里取消也什么都不提示。只有**失败**才说话——选图/写文件出错时页面看起来
/// 「没反应」，这时必须告诉用户没生效。
Future<void> showPageBackdropSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<PageBackdropChoice>(
    context: context,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (context) => const _PageBackdropSheet(),
  );
  if (choice == null) return;
  // 弹层关掉之后还会用这个 context 进去取色页 / 报错：先确认它还挂着。
  if (!context.mounted) return;

  try {
    switch (choice) {
      case PageBackdropChoice.defaultGradient:
        await PageBackdropController.reset();
      case PageBackdropChoice.color:
        await _pickSolid(context);
      case PageBackdropChoice.gradient:
        await _pickGradient(context);
      case PageBackdropChoice.image:
        // null = 用户在系统选择器里取消，静默返回。
        await PageBackdropController.pickAndSave();
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('设置失败：$e')),
    );
  }
}

/// 纯色：复用主题色的 HSV 取色器，选完立刻生效。
Future<void> _pickSolid(BuildContext context) async {
  final current = PageBackdropController.spec.value;
  final picked = await pickHsvColor(
    context,
    initial: current.color ?? AppColors.primary,
    title: '纯色背景',
  );
  if (picked == null) return;
  await PageBackdropController.setColor(picked);
}

/// 双色渐变：两个色标各自进取色器，方向不开放设置（固定左上 → 右下）。
Future<void> _pickGradient(BuildContext context) async {
  final current = PageBackdropController.spec.value;
  final picked = await showModalBottomSheet<(Color, Color)>(
    context: context,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _GradientBackdropSheet(
      start: current.gradientStart ?? _defaultGradientStart(),
      end: current.gradientEnd ?? AppColors.primary,
    ),
  );
  if (picked == null) return;
  await PageBackdropController.setGradient(picked.$1, picked.$2);
}

/// 第一次配渐变时的起始色：主题色往白里提一点，两个色标一眼能分出上下。
Color _defaultGradientStart() =>
    Color.lerp(AppColors.primary, Colors.white, 0.35) ?? AppColors.primary;

class _PageBackdropSheet extends StatelessWidget {
  const _PageBackdropSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<PageBackdropSpec>(
        valueListenable: PageBackdropController.spec,
        builder: (context, spec, _) {
          // 图片形态但副本已经没了：勾选态按「实际生效」算（渲染层这时也回退
          // 渐变），不让勾落在一条其实没生效的选项上。
          final imageActive = PageBackdropController.imageFileOf(spec) != null;
          final gradientStart = spec.gradientStart ?? _defaultGradientStart();
          final gradientEnd = spec.gradientEnd ?? AppColors.primary;
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
                  child: Text('页面背景', style: AppText.titleMedium),
                ),
                _BackdropOption(
                  optionKey: pageBackdropDefaultKey,
                  icon: Icons.gradient_outlined,
                  title: '默认（品牌渐变）',
                  selected: spec.isDefault,
                  onTap: () => Navigator.pop(
                    context,
                    PageBackdropChoice.defaultGradient,
                  ),
                ),
                _BackdropOption(
                  optionKey: pageBackdropColorKey,
                  icon: Icons.circle_outlined,
                  title: '纯色',
                  selected: spec.isColor,
                  swatch: _ColorSwatch(color: spec.color ?? AppColors.primary),
                  onTap: () =>
                      Navigator.pop(context, PageBackdropChoice.color),
                ),
                _BackdropOption(
                  optionKey: pageBackdropGradientKey,
                  icon: Icons.gradient,
                  title: '双色渐变',
                  selected: spec.isGradient,
                  swatch: _GradientSwatch(
                    start: gradientStart,
                    end: gradientEnd,
                  ),
                  onTap: () =>
                      Navigator.pop(context, PageBackdropChoice.gradient),
                ),
                _BackdropOption(
                  optionKey: pageBackdropPickKey,
                  icon: Icons.image_outlined,
                  title: '从相册选一张图',
                  selected: imageActive,
                  onTap: () => Navigator.pop(context, PageBackdropChoice.image),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 弹层顶部那条小横杠。
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.borderLight,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}

/// 主弹层里的一行：图标 + 文案 + 可选色样 + 选中勾。
class _BackdropOption extends StatelessWidget {
  const _BackdropOption({
    required this.optionKey,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.swatch,
  });

  final Key optionKey;
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final Widget? swatch;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: optionKey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(icon, size: 22, color: AppColors.textSecondary),
      title: Text(title, style: AppText.body),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (swatch != null) ...[
            swatch!,
            if (selected) const SizedBox(width: 8),
          ],
          if (selected) Icon(Icons.check, size: 20, color: AppColors.primary),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// 纯色色样：一枚小圆点。
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: AppColors.borderLight),
      ),
    );
  }
}

/// 渐变预览：和渲染层同一个方向（左上 → 右下）、同样两个色标。
class _GradientSwatch extends StatelessWidget {
  const _GradientSwatch({required this.start, required this.end});

  final Color start;
  final Color end;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [start, end],
        ),
        border: Border.all(color: AppColors.borderLight),
      ),
    );
  }
}

/// 双色渐变的编辑层：两个色标各自进 HSV 取色器，顶部一条实时预览。
///
/// 两个色标一起看、一起确认，而不是「选完第一个颜色就生效、再选第二个」：
/// 后者用户没法在同一屏里比较两端，也说不清中间那次落盘算不算数。
class _GradientBackdropSheet extends StatefulWidget {
  const _GradientBackdropSheet({required this.start, required this.end});

  final Color start;
  final Color end;

  @override
  State<_GradientBackdropSheet> createState() => _GradientBackdropSheetState();
}

class _GradientBackdropSheetState extends State<_GradientBackdropSheet> {
  late Color _start = widget.start;
  late Color _end = widget.end;

  Future<void> _editStart() async {
    final picked = await pickHsvColor(
      context,
      initial: _start,
      title: '起始色（左上）',
    );
    if (picked == null || !mounted) return;
    setState(() => _start = picked);
  }

  Future<void> _editEnd() async {
    final picked = await pickHsvColor(
      context,
      initial: _end,
      title: '结束色（右下）',
    );
    if (picked == null || !mounted) return;
    setState(() => _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: Text('双色渐变', style: AppText.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Container(
                key: pageBackdropGradientPreviewKey,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_start, _end],
                  ),
                ),
              ),
            ),
            _GradientStop(
              stopKey: pageBackdropGradientStartKey,
              label: '起始色（左上）',
              color: _start,
              onTap: _editStart,
            ),
            _GradientStop(
              stopKey: pageBackdropGradientEndKey,
              label: '结束色（右下）',
              color: _end,
              onTap: _editEnd,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FilledButton(
                key: pageBackdropGradientSaveKey,
                onPressed: () => Navigator.pop(context, (_start, _end)),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一个色标：左侧色样、文案、右侧十六进制 + 进入取色器的箭头。
class _GradientStop extends StatelessWidget {
  const _GradientStop({
    required this.stopKey,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final Key stopKey;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: stopKey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: _ColorSwatch(color: color),
      title: Text(label, style: AppText.body),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _hexColor(color),
            style: AppText.caption.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.textTertiary,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

String _hexColor(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
