import 'package:flutter/material.dart';

import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/text_styles.dart';
import '../../core/page_backdrop_controller.dart';

/// 「页面背景」弹层里能选的动作。
enum PageBackdropChoice {
  /// 不放图，走默认渐变（当前已经是渐变时这一项就是「已选中」）。
  defaultGradient,

  /// 从相册选一张图，压好复制进私有目录。
  pick,

  /// 删掉已保存的图 + 清 key，回到默认渐变。
  reset,
}

/// 「我的 → 页面背景」中的两个选项 key（有自定义背景图时第一项变成「恢复默认」）。
const Key pageBackdropDefaultKey = Key('page-backdrop-default');
const Key pageBackdropPickKey = Key('page-backdrop-pick');

/// 弹出「页面背景」选择层并执行选中的动作。
///
/// 三个页面共用一张图，所以这里只是改 [PageBackdropController] 的全局状态，
/// 不需要哪个页面自己 setState。
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

  String message;
  try {
    switch (choice) {
      case PageBackdropChoice.pick:
        final saved = await PageBackdropController.pickAndSave();
        // 用户在系统选择器里取消：什么都不提示。
        if (saved == null) return;
        message = '背景已更新';
      case PageBackdropChoice.defaultGradient:
      case PageBackdropChoice.reset:
        await PageBackdropController.reset();
        message = '已恢复默认渐变';
    }
  } catch (e) {
    message = '设置失败：$e';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

class _PageBackdropSheet extends StatelessWidget {
  const _PageBackdropSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<String?>(
        valueListenable: PageBackdropController.path,
        builder: (context, saved, _) {
          final custom = PageBackdropController.imageFileOrNull(saved) != null;
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
                  child: Text('页面背景', style: AppText.titleMedium),
                ),
                // 没有自定义图时这一项是「默认渐变」的选中态；有图时同一个
                // 位置变成真正的「恢复默认」（删文件 + 清 key），不会出现
                // 两条做同一件事的选项。
                ListTile(
                  key: pageBackdropDefaultKey,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(
                    custom ? Icons.restart_alt : Icons.gradient_outlined,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                  title: Text(
                    custom ? '恢复默认' : '默认渐变',
                    style: AppText.body,
                  ),
                  trailing: custom
                      ? const SizedBox(width: 20)
                      : Icon(Icons.check, size: 20, color: AppColors.primary),
                  onTap: () => Navigator.pop(
                    context,
                    custom
                        ? PageBackdropChoice.reset
                        : PageBackdropChoice.defaultGradient,
                  ),
                ),
                ListTile(
                  key: pageBackdropPickKey,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(
                    Icons.image_outlined,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                  title: const Text('从相册选一张图', style: AppText.body),
                  onTap: () =>
                      Navigator.pop(context, PageBackdropChoice.pick),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
