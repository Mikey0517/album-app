import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
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
