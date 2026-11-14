import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_restart.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/text_styles.dart';

/// 补丁下载完成后的提示：主按钮立刻重启进程让补丁生效，次按钮继续用，
/// 等下次冷启动自然生效。
Future<void> showPatchReadyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PatchReadyDialog(),
  );
}

class _PatchReadyDialog extends StatefulWidget {
  const _PatchReadyDialog();

  @override
  State<_PatchReadyDialog> createState() => _PatchReadyDialogState();
}

class _PatchReadyDialogState extends State<_PatchReadyDialog> {
  /// 点过「立即重启」后禁用两个按钮：进程正在退出，别再让用户点第二次。
  bool _restarting = false;

  Future<void> _restartNow() async {
    if (_restarting) return;
    setState(() => _restarting = true);
    if (await AppRestart.restart()) {
      // 原生已接管，进程马上结束，不需要再收尾。
      return;
    }
    // 通道不可用或没拿到启动 Intent：直接退出 App，用户手动重开同样能生效。
    await SystemNavigator.pop();
    // 退出没生效时别把用户锁死在一个两个按钮都灰掉的弹窗里。
    if (mounted) setState(() => _restarting = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.restart_alt,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '更新已准备好',
                style: AppText.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '重启后生效',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _restarting
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: const Text('稍后'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _restarting ? null : _restartNow,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: const Text('立即重启'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
