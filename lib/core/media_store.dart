import 'package:flutter/services.dart';

/// 删除结果：成功删除的张数与失败的张数。
class SourceDeleteResult {
  final int deleted;
  final int failed;

  /// 系统拒绝删除时的原因，用来在 UI 上说明为什么没删掉。
  final String? error;

  const SourceDeleteResult({
    required this.deleted,
    required this.failed,
    this.error,
  });

  bool get isSuccess => deleted > 0;
  bool get isPartial => deleted > 0 && failed > 0;
}

/// 要删除的一张原图：相册 URI + 是不是视频。
typedef SourceTarget = ({String uri, bool isVideo});

/// 删除手机相册里的原图（Android 11+ 会走系统确认弹窗）。
class MediaStore {
  MediaStore._();

  static const MethodChannel _channel = MethodChannel('album/media_store');

  static Future<SourceDeleteResult> deleteSources(
      List<SourceTarget> targets) async {
    if (targets.isEmpty) {
      return const SourceDeleteResult(deleted: 0, failed: 0);
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'deleteUris',
        {
          'items': targets
              .map((target) => {'uri': target.uri, 'video': target.isVideo})
              .toList(growable: false),
        },
      );
      return SourceDeleteResult(
        deleted: (result?['deleted'] as num?)?.toInt() ?? 0,
        failed: (result?['failed'] as num?)?.toInt() ?? 0,
        error: result?['error'] as String?,
      );
    } catch (e) {
      return SourceDeleteResult(deleted: 0, failed: targets.length, error: '$e');
    }
  }
}
