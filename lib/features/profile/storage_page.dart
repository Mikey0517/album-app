import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cache_service.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';
import '../../core/upload_manager.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';

/// 「存储空间」：App 在本机的占用分项与清理入口。
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  CacheUsage _usage = CacheUsage.empty;
  bool _loading = true;
  bool _clearing = false;
  bool _clearingPending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final usage = await CacheService.measure();
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _loading = false;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _size(int bytes) => _loading ? '…' : formatBytes(bytes);

  String get _pendingLabel {
    if (_loading) return '…';
    final count = _usage.pendingUploadCount;
    if (count == 0) return '0 项';
    return '$count 项 · ${formatBytes(_usage.pendingUploadBytes)}';
  }

  Widget _row(String label, String value, {bool emphasized = false}) {
    final style = emphasized
        ? AppText.body.copyWith(fontWeight: FontWeight.w600)
        : AppText.body;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: emphasized ? style : AppText.bodySmall),
      ],
    );
  }

  Future<void> _clearCache() async {
    if (_clearing) return;
    // 先统计一次，弹窗里的数字才是最新的。
    await _load();
    if (!mounted) return;
    final usage = _usage;
    if (usage.isEmpty) {
      _snack('没有可清理的缓存');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理缓存？', style: AppText.titleMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('图片缓存', formatBytes(usage.imageBytes)),
            const SizedBox(height: 10),
            _row('临时文件', formatBytes(usage.tempBytes)),
            const Divider(height: 22),
            _row('合计可清理', formatBytes(usage.clearableBytes),
                emphasized: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    final result = await CacheService.clear();
    if (!mounted) return;
    setState(() => _clearing = false);
    await _load();
    if (!mounted) return;
    _snack('已清理 ${formatBytes(result.freedBytes)}');
  }

  Future<void> _clearPendingCopies() async {
    if (_clearingPending) return;
    await _load();
    if (!mounted) return;
    final count = _usage.pendingUploadCount;
    if (count == 0) {
      _snack('没有待上传副本');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理待上传副本？', style: AppText.titleMedium),
        content: Text(
          '$count 项副本会从上传队列移除并删除，'
          '之后要重新选择照片才能上传，且无法恢复。',
          style: AppText.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingPending = true);
    final result = await UploadManager.instance.clearPendingCopies();
    if (!mounted) return;
    setState(() => _clearingPending = false);
    await _load();
    if (!mounted) return;
    _snack('已清理 ${result.deletedCopies} 项 · '
        '${formatBytes(result.freedBytes)}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('存储空间')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppCard(
            child: Column(
              children: [
                _row('图片缓存', _size(_usage.imageBytes)),
                const SizedBox(height: 14),
                _row('临时文件', _size(_usage.tempBytes)),
                const SizedBox(height: 14),
                _row('待上传副本', _pendingLabel),
                const SizedBox(height: 14),
                _row('其他', _size(_usage.otherBytes)),
                const Divider(height: 28),
                _row('总计', _size(_usage.appBytes), emphasized: true),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: '清理',
            onPressed: _clearing ? null : _clearCache,
            loading: _clearing,
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: _clearingPending || _loading || _usage.pendingUploadCount == 0
                  ? null
                  : _clearPendingCopies,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
                disabledForegroundColor: AppColors.textTertiary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: _clearingPending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('清理待上传副本'),
            ),
          ),
        ],
      ),
    );
  }
}
