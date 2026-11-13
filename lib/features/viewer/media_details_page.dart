import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/radius.dart';
import '../../core/formatters.dart';
import '../../models/media.dart';

/// 媒体详情页：拍摄时间、文件信息、拍摄地点，一路 label 平铺。
class MediaDetailsPage extends StatelessWidget {
  const MediaDetailsPage({super.key, required this.media});

  final Media media;

  bool get _isVideo => media.isVideo;

  String get _timeLabel => _isVideo ? '拍摄时间' : '拍照时间';

  String get _placeLabel => _isVideo ? '拍摄地点' : '拍照地点';

  String get _typeLabel {
    if (media.isVideo) return '视频';
    if (media.isLivePhoto) return '动态照片';
    return '照片';
  }

  String get _resolution {
    final width = media.width;
    final height = media.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return '未知';
    }
    return '$width × $height';
  }

  String get _format {
    final raw = media.originalFormat?.trim();
    if (raw == null || raw.isEmpty) return _isVideo ? 'MP4' : 'JPEG';
    return raw.toUpperCase();
  }

  bool get _hasLocation => media.latitude != null && media.longitude != null;

  String get _locationText {
    if (!_hasLocation) return '无位置信息';
    final lat = media.latitude!;
    final lng = media.longitude!;
    return '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  }

  Future<void> _openMap(BuildContext context) async {
    if (!_hasLocation) return;
    final uri = Uri.parse(
      'https://uri.amap.com/marker?position=${media.longitude},${media.latitude}'
      '&name=拍摄地点&src=album&coordinate=gaode',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的地图应用')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      (_timeLabel, _formatDateTime(media.takenAt.toLocal())),
      ('类型', _typeLabel),
      ('分辨率', _resolution),
      ('格式', _format),
      if (_isVideo) ('时长', formatDuration(media.durationMs)),
      ('大小', media.fileSize == null ? '未知' : formatBytes(media.fileSize)),
      (_placeLabel, _locationText),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('详情'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                children: [
                  for (final row in rows)
                    _Row(
                      label: row.$1,
                      value: row.$2,
                      trailing: row.$1 == _placeLabel && _hasLocation
                          ? TextButton(
                              onPressed: () => _openMap(context),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF7CB8FF),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('地图'),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            if (!_hasLocation)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 12),
                child: Text(
                  '原图里没有 GPS 信息，或这个格式不支持读取位置。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Colors.white.withOpacity(0.45),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.55),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.white,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
