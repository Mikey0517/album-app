import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'upload_errors.dart';

/// 一条待续传任务（只持久化未完成的）。
class StoredUploadItem {
  final int albumId;
  final String name;
  final String path;
  final bool isVideo;
  final UploadFailureKind failure;
  final String? error;
  final int autoRetries;

  const StoredUploadItem({
    required this.albumId,
    required this.name,
    required this.path,
    required this.isVideo,
    required this.failure,
    required this.error,
    required this.autoRetries,
  });

  Map<String, dynamic> toJson() => {
        'album_id': albumId,
        'name': name,
        'path': path,
        'is_video': isVideo,
        'failure': failure.name,
        'error': error,
        'auto_retries': autoRetries,
      };

  static StoredUploadItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'] as String?;
    final name = raw['name'] as String?;
    final albumId = (raw['album_id'] as num?)?.toInt();
    if (path == null || path.isEmpty || albumId == null) return null;
    var failure = UploadFailureKind.none;
    final failureName = raw['failure'] as String?;
    for (final kind in UploadFailureKind.values) {
      if (kind.name == failureName) failure = kind;
    }
    return StoredUploadItem(
      albumId: albumId,
      name: name == null || name.isEmpty ? path.split('/').last : name,
      path: path,
      isVideo: raw['is_video'] as bool? ?? false,
      failure: failure,
      error: raw['error'] as String?,
      autoRetries: (raw['auto_retries'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 上传队列的持久化：App 被杀掉后重新打开还能接着传。
class UploadQueueStore {
  UploadQueueStore._();

  static const String _key = 'upload_queue';

  static Future<List<StoredUploadItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(StoredUploadItem.tryParse)
          .whereType<StoredUploadItem>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<StoredUploadItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(
      _key,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }
}
