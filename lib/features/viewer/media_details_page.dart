import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/radius.dart';
import '../../core/design/spacing.dart';
import '../../core/formatters.dart';
import '../../models/media.dart';

/// 媒体详情页：拍摄时间、文件信息、拍摄地点。
/// 全屏浏览时点右上角的圆形叹号进入，保持和浏览器一致的深色风格。
class MediaDetailsPage extends StatelessWidget {
  const MediaDetailsPage({super.key, required this.media});

  final Media media;

  bool get _isVideo => media.isVideo;

  /// 视频叫「拍摄时间/拍摄地点」，照片叫「拍照时间/拍照地点」。
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
    final lat = media.latitude!;
    final lng = media.longitude!;
    // 高德的地图链接：手机上能直接唤起高德/地图 App，没有就落到网页。
    final uri = Uri.parse(
      'https://uri.amap.com/marker?position=$lng,$lat&name=拍摄地点&src=album&coordinate=gaode',
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
    final takenAt = media.takenAt.toLocal();
    final rows = <(String, String)>[
      (_timeLabel, _formatDateTime(takenAt)),
      ('类型', _typeLabel),
      ('分辨率', _resolution),
      ('格式', _format),
      if (_isVideo) ('时长', formatDuration(media.durationMs)),
      ('大小', media.fileSize == null ? '未知' : formatBytes(media.fileSize)),
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
            _Section(
              title: _timeLabel,
              children: [_Row(label: '', value: _formatDateTime(takenAt))],
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: '文件信息',
              children: [
                for (final row in rows)
                  _Row(label: row.$1, value: row.$2),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: _placeLabel,
              children: [
                _Row(label: '', value: _locationText),
                if (_hasLocation)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _openMap(context),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('在地图中查看'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF7CB8FF),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
            ),
          ],
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
