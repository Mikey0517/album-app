import 'dart:async';

import 'package:flutter/material.dart';

import 'design/colors.dart';
import 'design/radius.dart';
import 'design/shadow.dart';
import 'design/spacing.dart';
import 'design/text_styles.dart';
import 'server_config.dart';

/// 服务器地址固定只读；这里只展示地址、测试连通性并重新检测当前线路。
Future<bool> showServerSettings(
  BuildContext context, {
  bool autoTest = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ServerSettingsDialog(autoTest: autoTest),
  );
  return result ?? false;
}

class _ServerSettingsDialog extends StatefulWidget {
  final bool autoTest;

  const _ServerSettingsDialog({this.autoTest = true});

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  bool _ready = false;
  bool _testing = false;
  ServerProbeResult? _lanResult;
  ServerProbeResult? _wanResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    await ServerConfig.init();
    if (!mounted) return;
    setState(() => _ready = true);
    if (widget.autoTest) {
      unawaited(_test());
    }
  }

  Future<void> _test() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _lanResult = null;
      _wanResult = null;
    });
    final results = await Future.wait<ServerProbeResult>([
      ServerConfig.probe(
        ServerConfig.lanUrl ?? ServerConfig.defaultLanUrl,
        timeout: const Duration(seconds: 3),
      ),
      ServerConfig.probe(
        ServerConfig.wanUrl ?? ServerConfig.defaultWanUrl,
        timeout: const Duration(seconds: 12),
      ),
    ]);
    await ServerConfig.detectActive();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _lanResult = results[0];
      _wanResult = results[1];
    });
  }

  Widget _statusRow(ServerProbeResult? result) {
    if (_testing) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          SizedBox(width: 6),
          Text('测试中…', style: AppText.caption),
        ],
      );
    }
    if (result == null) {
      return const Text('未测试', style: AppText.caption);
    }
    final color = result.ok ? AppColors.success : AppColors.danger;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          result.ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          result.ok ? '${result.latencyMs ?? 0} ms' : (result.error ?? '连接失败'),
          style: AppText.caption.copyWith(color: color),
        ),
      ],
    );
  }

  Widget _readOnlyRow({
    required String label,
    required String url,
    required ServerProbeResult? result,
    required bool active,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppText.bodySmall),
            if (active) ...[
              const SizedBox(width: 5),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          decoration: BoxDecoration(
            color: AppColors.bgPage,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 15, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  url,
                  style: AppText.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _statusRow(result),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lan = ServerConfig.lanUrl ?? ServerConfig.defaultLanUrl;
    final wan = ServerConfig.wanUrl ?? ServerConfig.defaultWanUrl;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: AppShadow.dialog,
        ),
        child: !_ready
            ? SizedBox(
                height: 180,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('服务器状态', style: AppText.titleLarge),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          tooltip: '关闭',
                          icon: const Icon(Icons.close, size: 22),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _readOnlyRow(
                      label: '局域网',
                      url: lan,
                      result: _lanResult,
                      active: ServerConfig.activeUrl == lan,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _readOnlyRow(
                      label: '互联网',
                      url: wan,
                      result: _wanResult,
                      active: ServerConfig.activeUrl == wan,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _testing ? null : _test,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        child: Text(_testing ? '测试中…' : '测试连接'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
