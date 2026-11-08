import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/app_user.dart';

class UserApi {
  static final Dio _dio = ApiClient.dio;

  /// 按登录 ID 或昵称搜索用户（分享相册时找人用）。
  static Future<List<AppUser>> search(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];
    final response = await _dio.get<dynamic>(
      '/api/users/search',
      queryParameters: {'q': keyword},
    );
    final data = response.data;
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    final raw = map['items'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AppUser.fromJson)
        .toList(growable: false);
  }
}
