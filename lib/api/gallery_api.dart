import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/media.dart';
import '../models/paged.dart';

class GalleryApi {
  static final Dio _dio = ApiClient.dio;

  static Future<Paged<Media>> feed({
    String? cursor,
    int limit = 60,
  }) async {
    final response = await _dio.get<dynamic>(
      '/api/gallery/feed',
      queryParameters: {
        'limit': limit,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final data = response.data;
    final map = data is Map<String, dynamic>
        ? data
        : jsonDecode(data as String) as Map<String, dynamic>;
    return Paged.fromJson(map, Media.fromJson);
  }
}
