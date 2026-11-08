import 'package:intl/intl.dart';

String _two(int v) => v.toString().padLeft(2, '0');

String dayKey(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String formatDayHeader(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(local.year, local.month, local.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return '今天 · ${local.month}月${local.day}日';
  if (diff == 1) return '昨天 · ${local.month}月${local.day}日';
  if (local.year == now.year) return '${local.month}月${local.day}日';
  return '${local.year}年${local.month}月${local.day}日';
}

String formatPostTime(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(local.year, local.month, local.day);
  final diff = today.difference(target).inDays;
  final hm = '${_two(local.hour)}:${_two(local.minute)}';
  if (diff == 0) return hm;
  if (diff == 1) return '昨天 $hm';
  if (local.year == now.year) {
    return '${local.month}月${local.day}日 $hm';
  }
  return '${local.year}/${local.month}/${local.day}';
}

String formatTakenAt(DateTime time) {
  final local = time.toLocal();
  return DateFormat('yyyy年M月d日 HH:mm').format(local);
}

String formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '00:00';
  final total = (durationMs / 1000).round();
  final minutes = total ~/ 60;
  final seconds = total % 60;
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    return '$hours:${_two(minutes % 60)}:${_two(seconds)}';
  }
  return '${_two(minutes)}:${_two(seconds)}';
}

String formatCount(int count) {
  if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)} 万';
  }
  return '$count';
}

String formatBytes(int? bytes) {
  final n = (bytes ?? 0).toDouble();
  if (n < 1024) return '${n.round()} B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  if (n < 1024 * 1024 * 1024) {
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(n / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}
