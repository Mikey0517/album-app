import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/storage_info.dart';

class StorageApi {
  static final Dio _dio = ApiClient.dio;

  static Future<StorageInfo> fetch() async {
    final response = await _dio.get<dynamic>('/api/system/storage');
    final data = response.data;
    final map = data is Map<String, dynamic>
        ? data
        : data is String
            ? jsonDecode(data) as Map<String, dynamic>
            : const <String, dynamic>{};
    return StorageInfo.fromJson(map);
  }
}
