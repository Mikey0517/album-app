import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 删除失败的原因。
///
/// 原生只回原因码，文案在 [sourceDeleteMessage] 里拼：把
/// "IllegalArgumentException: All requested items must be referenced by
/// specific ID" 这种异常原文丢给用户，等于什么都没说。
enum SourceDeleteFailure {
  /// 用户在系统确认弹窗里点了取消。
  userCancelled,

  /// 条目已经不在手机相册里（被别的 App 删掉或挪走）。
  notFound,

  /// 声明是视频、实际是图片（或反过来），集合对不上。
  typeMismatch,

  /// 不是相册条目（不是 content://media、集合不对、缺 id）。
  unsupported,

  /// Photo Picker 给的 URI 换不成 MediaStore 的单项 URI。
  unresolvedPicker,

  /// 系统不接受这批删除（没有删除权限、厂商限制等）。
  systemRejected,
}

/// 删除结果：成功删除的张数与失败的张数。
class SourceDeleteResult {
  final int deleted;
  final int failed;

  /// 失败的原因，用来在 UI 上讲清楚为什么没删掉。
  final SourceDeleteFailure? reason;

  const SourceDeleteResult({
    required this.deleted,
    required this.failed,
    this.reason,
  });

  bool get isSuccess => deleted > 0;
  bool get isPartial => deleted > 0 && failed > 0;
}

/// 要删除的一张原图：相册 URI + 是不是视频。
typedef SourceTarget = ({String uri, bool isVideo});

/// 形状自检：返回 null 表示这条形态上可能是个相册条目，可以送给系统；
/// 否则返回剔除原因，这条不会进入 createDeleteRequest。
///
/// 只认两种形态：
/// * `content://media/<volume>/(images|video)/media/<数字 id>`（可以直接删）；
/// * `content://media/picker/.../<数字 id>`（原生还能按 id 换成上面那种）。
///
/// 别的形态一条都不能塞进同一批：createDeleteRequest 会整批抛
/// IllegalArgumentException，结果是一条都删不掉。
@visibleForTesting
SourceDeleteFailure? sourceTargetRejection(SourceTarget target) {
  final uri = Uri.tryParse(target.uri);
  if (uri == null || uri.scheme != 'content' || uri.authority != 'media') {
    return SourceDeleteFailure.unsupported;
  }
  final segments = uri.pathSegments;
  if (segments.isEmpty) return SourceDeleteFailure.unsupported;
  if (segments.first == 'picker') {
    // Photo Picker 的 URI 末尾是媒体 id；不是数字就没法换成系统认的单项 URI。
    return _isMediaId(segments.last) ? null : SourceDeleteFailure.unresolvedPicker;
  }
  if (segments.length != 4 || segments[2] != 'media') {
    return SourceDeleteFailure.unsupported;
  }
  final collection = segments[1];
  if (collection != 'images' && collection != 'video') {
    return SourceDeleteFailure.unsupported;
  }
  if (!_isMediaId(segments[3])) return SourceDeleteFailure.unsupported;
  // URI 说的是图片、调用方说是视频：两边必有一边错，别拿去删。
  if (target.isVideo != (collection == 'video')) {
    return SourceDeleteFailure.typeMismatch;
  }
  return null;
}

bool _isMediaId(String value) {
  final id = int.tryParse(value);
  return id != null && id > 0;
}

/// 删除手机相册里的原图（Android 11+ 会走系统确认弹窗）。
class MediaStore {
  MediaStore._();

  static const MethodChannel _channel = MethodChannel('album/media_store');

  /// 删除相册原图。
  ///
  /// 顺序是：形状自检 → 原生按 id 查库确认 → 交给系统删。
  /// 任何一条通不过检查的就从这一批里剔除并计入失败：一个非法 URI 混进去，
  /// createDeleteRequest 会让整批抛异常，好的一条也删不掉。
  static Future<SourceDeleteResult> deleteSources(
      List<SourceTarget> targets) async {
    if (targets.isEmpty) {
      return const SourceDeleteResult(deleted: 0, failed: 0);
    }

    final rejected = <SourceDeleteFailure>[];
    final shaped = <SourceTarget>[];
    for (final target in targets) {
      final reason = sourceTargetRejection(target);
      if (reason == null) {
        shaped.add(target);
      } else {
        rejected.add(reason);
      }
    }

    // 原生按 id + 媒体类型查一遍库：还在不在、到底是 images 还是 video。
    final checked = await _resolveDeletable(shaped);
    final ready = <SourceTarget>[];
    for (final item in checked) {
      final uri = item.uri;
      if (uri != null && item.reason == null) {
        ready.add((uri: uri, isVideo: item.isVideo));
      } else {
        rejected.add(item.reason ?? SourceDeleteFailure.unsupported);
      }
    }

    if (ready.isEmpty) {
      return SourceDeleteResult(
        deleted: 0,
        failed: targets.length,
        reason: rejected.isEmpty
            ? SourceDeleteFailure.systemRejected
            : rejected.first,
      );
    }

    Map<String, dynamic>? result;
    try {
      result = await _channel.invokeMapMethod<String, dynamic>(
        'deleteUris',
        {
          'items': ready
              .map((target) => {'uri': target.uri, 'video': target.isVideo})
              .toList(growable: false),
        },
      );
    } catch (e) {
      // 通道本身出问题（原生没注册、Activity 已销毁）：照样按失败报，别抛给 UI。
      debugPrint('删除相册原图失败: $e');
      return SourceDeleteResult(
        deleted: 0,
        failed: targets.length,
        reason: rejected.isEmpty
            ? SourceDeleteFailure.systemRejected
            : rejected.first,
      );
    }

    final deleted = (result?['deleted'] as num?)?.toInt() ?? 0;
    final failed = (result?['failed'] as num?)?.toInt() ?? 0;
    final nativeReason = _failureFromCode(result?['reason']);
    return SourceDeleteResult(
      deleted: deleted,
      failed: failed + rejected.length,
      reason: nativeReason ?? (rejected.isEmpty ? null : rejected.first),
    );
  }

  /// 让原生逐条确认「这一条还能不能删」，返回顺序和入参一致。
  ///
  /// 原生不可用（老版本、桌面、测试没 mock 这个方法）时原样放行：真正的校验
  /// 在 deleteUris 里还会再做一遍，这里失败只是少了提前剔除，不会把删除搞挂。
  static Future<List<_ResolvedTarget>> _resolveDeletable(
      List<SourceTarget> items) async {
    if (items.isEmpty) return const <_ResolvedTarget>[];
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'resolveDeleteUris',
        {
          'items': items
              .map((target) => {'uri': target.uri, 'video': target.isVideo})
              .toList(growable: false),
        },
      );
      final list = result?['items'];
      if (list is! List || list.length != items.length) return _passThrough(items);
      return [
        for (var i = 0; i < items.length; i++)
          _resolvedFrom(list[i], items[i]),
      ];
    } catch (e) {
      debugPrint('删除前校验不可用，降级为形状校验: $e');
      return _passThrough(items);
    }
  }

  static List<_ResolvedTarget> _passThrough(List<SourceTarget> items) => [
        for (final item in items)
          _ResolvedTarget(uri: item.uri, isVideo: item.isVideo),
      ];

  static _ResolvedTarget _resolvedFrom(Object? raw, SourceTarget fallback) {
    if (raw is! Map) {
      return _ResolvedTarget(uri: fallback.uri, isVideo: fallback.isVideo);
    }
    final video = raw['video'] as bool? ?? fallback.isVideo;
    final reason = _failureFromCode(raw['reason']);
    final uri = raw['uri'] as String?;
    // 原生说「这条不能删」（没给 uri 或给了原因码）时不能退回原 URI：
    // 那正是会整批抛 IllegalArgumentException 的那种地址。
    if (reason != null || uri == null) {
      return _ResolvedTarget(
        uri: null,
        isVideo: video,
        reason: reason ?? SourceDeleteFailure.unsupported,
      );
    }
    return _ResolvedTarget(uri: uri, isVideo: video);
  }
}

/// 原生校验过的一条：uri 为空表示被剔除，[reason] 说明原因。
class _ResolvedTarget {
  final String? uri;
  final bool isVideo;
  final SourceDeleteFailure? reason;

  const _ResolvedTarget({this.uri, required this.isVideo, this.reason});
}

/// 原生原因码 → 文案用的枚举。
SourceDeleteFailure? _failureFromCode(Object? code) {
  switch (code) {
    case 'user_cancelled':
      return SourceDeleteFailure.userCancelled;
    case 'not_found':
      return SourceDeleteFailure.notFound;
    case 'type_mismatch':
      return SourceDeleteFailure.typeMismatch;
    case 'unsupported_uri':
      return SourceDeleteFailure.unsupported;
    case 'unresolved_picker':
      return SourceDeleteFailure.unresolvedPicker;
    case 'system_rejected':
      return SourceDeleteFailure.systemRejected;
  }
  return null;
}
