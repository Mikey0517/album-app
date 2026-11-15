import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../models/media.dart';
import '../models/paged.dart';
import '../models/post.dart';

class PostApi {
  static final Dio _dio = ApiClient.dio;

  static Future<Paged<Post>> list({
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _dio.get<dynamic>(
      '/api/posts',
      queryParameters: {
        'limit': limit,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    return Paged.fromJson(_asMap(response.data), Post.fromJson);
  }

  static Future<int> create({
    required String content,
    required List<XFile> files,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final form = FormData();
    if (content.trim().isNotEmpty) {
      form.fields.add(MapEntry('content', content.trim()));
    }
    for (final file in files) {
      form.files.add(
        MapEntry(
          'files',
          await MultipartFile.fromFile(file.path, filename: file.name),
        ),
      );
    }
    final response = await _dio.post<dynamic>(
      '/api/posts',
      data: form,
      onSendProgress: onSendProgress,
    );
    final map = _asMap(response.data);
    return (map['id'] as num).toInt();
  }

  /// 往年同月同日的动态。
  static Future<List<Post>> onThisDay() async {
    final response = await _dio.get<dynamic>('/api/posts/on-this-day');
    final map = _asMap(response.data);
    final raw = map['items'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Post.fromJson)
        .toList(growable: false);
  }

  /// 编辑已发布动态：文案 + 最终媒体顺序（media_ids），返回带 edited_at 的最新动态。
  ///
  /// 服务端保证 posted_at 不变——编辑不改变发布时间。媒体 id 需要先通过
  /// [uploadForEdit] 上传拿到，否则新选的图没有 id 可提交。
  static Future<Post> update(
    int id, {
    required String content,
    List<int>? mediaIds,
    List<int>? addMediaIds,
  }) async {
    final response = await _dio.put<dynamic>(
      '/api/posts/$id',
      data: {
        'content': content,
        if (mediaIds != null) 'media_ids': mediaIds,
        if (addMediaIds != null) 'add_media_ids': addMediaIds,
      },
    );
    return Post.fromJson(_asMap(response.data));
  }

  /// 编辑时先上传新增媒体：只落盘、不挂任何动态，返回带 id 的媒体，
  /// 由随后的 [update]（media_ids / add_media_ids）挂上去。
  static Future<List<Media>> uploadForEdit(
    List<XFile> files, {
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final form = FormData();
    for (final file in files) {
      form.files.add(
        MapEntry(
          'files',
          await MultipartFile.fromFile(file.path, filename: file.name),
        ),
      );
    }
    final response = await _dio.post<dynamic>(
      '/api/posts/media',
      data: form,
      options: Options(
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 30),
      ),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
    final map = _asMap(response.data);
    final raw = map['items'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Media.fromJson)
        .toList(growable: false);
  }

  /// 放弃编辑时清理已经上传、但还没挂到动态上的临时媒体；失败不打扰用户。
  static Future<void> deleteUploadedMedia(Iterable<int> ids) async {
    for (final id in ids) {
      try {
        await _dio.delete<dynamic>('/api/posts/media/$id');
      } catch (_) {
        // 服务端只允许删未挂载的临时媒体；删不掉也只是不可见的残留。
      }
    }
  }

  static Future<void> delete(int id) async {
    await _dio.delete<dynamic>('/api/posts/$id');
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return const {};
  }
}
