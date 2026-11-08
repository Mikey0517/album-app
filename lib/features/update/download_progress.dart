class DownloadProgress {
  final int received;
  final int total;
  final double bytesPerSecond;

  const DownloadProgress({
    required this.received,
    required this.total,
    required this.bytesPerSecond,
  });

  double get percent {
    if (total <= 0) return 0;
    return (received / total).clamp(0.0, 1.0);
  }

  String get receivedLabel => _bytes(received);

  String get totalLabel => total > 0 ? _bytes(total) : '未知';

  String get speedLabel =>
      bytesPerSecond <= 0 ? '0 KB/s' : '${_bytes(bytesPerSecond.round())}/s';

  Duration get eta {
    if (total <= 0 || bytesPerSecond <= 0 || received >= total) {
      return Duration.zero;
    }
    final seconds = ((total - received) / bytesPerSecond).ceil();
    return Duration(seconds: seconds.clamp(0, 24 * 60 * 60).toInt());
  }

  String get etaLabel {
    if (total > 0 && received >= total) return '即将完成';
    if (total <= 0 || bytesPerSecond <= 0) return '正在计算剩余时间…';
    final seconds = eta.inSeconds;
    if (seconds <= 0) return '即将完成';
    if (seconds < 60) return '剩余 约 $seconds 秒';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes < 60) {
      return '剩余 约 $minutes 分${rest > 0 ? ' $rest 秒' : ''}';
    }
    final hours = minutes ~/ 60;
    return '剩余 约 $hours 小时${minutes % 60 > 0 ? ' ${minutes % 60} 分' : ''}';
  }

  static String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    if (value < 1024 * 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
