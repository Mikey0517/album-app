import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/colors.dart';
import 'design/radius.dart';
import 'design/shadow.dart';
import 'design/spacing.dart';
import 'design/text_styles.dart';
import 'network_diagnostics.dart';

/// 服务器弹窗里的「网络诊断」：把每次请求拆成建连/首字节/总计，
/// 并给出一句人话结论，方便判断慢在设备链路还是服务端。
Future<void> showNetworkDiagnostics(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _NetworkDiagnosticsDialog(),
  );
}

class _NetworkDiagnosticsDialog extends StatefulWidget {
  const _NetworkDiagnosticsDialog();

  @override
  State<_NetworkDiagnosticsDialog> createState() =>
      _NetworkDiagnosticsDialogState();
}

class _NetworkDiagnosticsDialogState extends State<_NetworkDiagnosticsDialog> {
  NetworkDiagnosticsReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _report = null;
      _error = null;
    });
    try {
      final report = await NetworkDiagnostics.run();
      if (!mounted) return;
      setState(() => _report = report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _copy() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report.toText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('诊断结果已复制')),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Text('诊断失败：$_error', style: AppText.bodySmall);
    }
    final report = _report;
    if (report == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgPage,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: SelectableText(
        report.toText(),
        style: AppText.caption.copyWith(
          fontFamily: 'monospace',
          height: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: AppShadow.dialog,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('网络诊断', style: AppText.titleLarge),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                  icon: const Icon(Icons.close, size: 22),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(child: SingleChildScrollView(child: _body())),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _report == null && _error == null ? null : _run,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text('重新诊断'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _report == null ? null : _copy,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text('复制结果'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
