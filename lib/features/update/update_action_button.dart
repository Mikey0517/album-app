import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/colors.dart';
import '../../core/design/text_styles.dart';

/// 更新按钮：按钮本身就是进度条。
///
/// 旧版在按钮上方单独占一块「进度条 + 百分比 + 已下载/总量 + 速度 + 剩余
/// 时间」的仪表盘，弹窗被撑成两截。进度改成按钮内部的填充之后，同一块
/// 面积既表达「可以点」也表达「推进到哪了」：下载中填充从左往右长，文字
/// 跟着变成「下载中 42%」，完成后按钮闪一下、换成下一步的文案。
///
/// 填充用 [TweenAnimationBuilder] 补间（[fillDuration] = 220ms、
/// easeOutCubic）：下载回调大约每 100~500ms 来一次，直接 setState 会让填充
/// 一格一格地跳；补间从当前值出发追新值，视觉上是一条连续的推进入。
/// 时长压在 150~250ms 之间——更短会跳，更长会落后于真实进度。
class UpdateActionButton extends StatefulWidget {
  const UpdateActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.progress,
    this.completed = false,
    this.height = 50,
  });

  /// 按钮内部那层填充。测试按它的宽度断言进度比例。
  static const Key fillKey = Key('update-action-fill');

  /// 完成时那一次高亮的叠层。
  static const Key flashKey = Key('update-action-flash');

  /// 进度补间的时长。
  static const Duration fillDuration = Duration(milliseconds: 220);

  /// 按钮文字：调用点按状态给（立即更新 / 下载中 42% / 正在安装…）。
  final String label;

  /// 点按回调；null = 本次不可点（下载中、安装中）。
  final VoidCallback? onPressed;

  /// 按钮内部填充的进度（0..1）；null = 不画填充。
  final double? progress;

  /// 完成反馈标记：由 false 变 true 的那一帧触发一次高亮 + 轻微放大。
  /// 只触发一次，不做循环——强制更新弹窗里没有值得庆祝的东西。
  final bool completed;

  final double height;

  @override
  State<UpdateActionButton> createState() => _UpdateActionButtonState();
}

class _UpdateActionButtonState extends State<UpdateActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _feedback = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void didUpdateWidget(UpdateActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.completed && !oldWidget.completed) {
      _feedback.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final base =
        enabled ? AppColors.primary : AppColors.primary.withValues(alpha: 0.55);
    // 填充是主色上的白：禁用态（下载中按钮不可点）底色本来就压暗了，
    // 填充再淡一点，读起来仍是「进度在走」而不是「按钮变亮」。
    final fill = Colors.white.withValues(alpha: enabled ? 0.28 : 0.22);
    final progress = widget.progress;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _feedback,
        // 一次 sin 脉冲：0 → 1 → 0，放大 2% 就够看得出来，不晃眼。
        builder: (context, child) {
          final pulse = math.sin(math.pi * _feedback.value);
          return Transform.scale(scale: 1 + 0.02 * pulse, child: child);
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.height / 2),
          child: Material(
            color: base,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (progress != null)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 0,
                          end: progress.clamp(0.0, 1.0),
                        ),
                        duration: UpdateActionButton.fillDuration,
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return FractionallySizedBox(
                            widthFactor: value,
                            heightFactor: 1,
                            child: child,
                          );
                        },
                        child: DecoratedBox(
                          key: UpdateActionButton.fillKey,
                          decoration: BoxDecoration(color: fill),
                        ),
                      ),
                    ),
                  ),
                if (widget.completed)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _feedback,
                        builder: (context, child) {
                          return DecoratedBox(
                            key: UpdateActionButton.flashKey,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha:
                                    0.16 * math.sin(math.pi * _feedback.value),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: InkWell(
                    onTap: widget.onPressed,
                    child: Center(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.button.copyWith(
                          color: enabled ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
