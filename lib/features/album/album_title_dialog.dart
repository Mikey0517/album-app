import 'package:flutter/material.dart';

import '../../core/design/colors.dart';

/// 新建 / 重命名相册的输入对话框，返回 trim 后的标题。
Future<String?> showAlbumTitleDialog(
  BuildContext context, {
  String heading = '新建相册',
  String actionLabel = '创建',
  String initialTitle = '',
}) {
  final controller = TextEditingController(text: initialTitle);
  String? error;
  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final value = controller.text.trim();
            if (value.isEmpty) {
              setState(() => error = '给相册取一个名字');
              return;
            }
            if (value.length > 40) {
              setState(() => error = '标题不能超过 40 个字');
              return;
            }
            Navigator.of(context).pop(value);
          }

          return AlertDialog(
            title: Text(heading),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 40,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: '例如：2026 夏天',
                errorText: error,
                counterText: '',
              ),
              onChanged: (_) {
                if (error != null) setState(() => error = null);
              },
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: submit,
                child: Text(actionLabel),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}
