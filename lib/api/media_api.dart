import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/api_client.dart';

class MediaApi {
  static final Dio _dio = ApiClient.dio;

  static Future<bool> toggleFavorite(int mediaId) async {
    final response = await _dio.post<dynamic>(
      '/api/media/$mediaId/favorite',
    );
    final data = response.data;
    final map = data is Map<String, dynamic>
        ? data
        : data is String
            ? jsonDecode(data) as Map<String, dynamic>
            : const <String, dynamic>{};
    return map['favorite'] == true;
  }
}
