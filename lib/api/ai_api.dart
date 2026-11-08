import 'package:dio/dio.dart';

import '../core/api_client.dart';

class AiApi {
  static final Dio _dio = ApiClient.dio;

  /// 让服务端代理调用 DeepSeek 视觉模型生成朋友圈文案。
  /// [images] 每项是 {base64, mime}，不含 data URL 前缀。
  static Future<String> suggestCaption({
    required List<Map<String, String>> images,
    String? context,
  }) async {
    final response = await _dio.post<dynamic>(
      '/api/ai/suggest-caption',
      data: {
        'images': images,
        if (context != null && context.trim().isNotEmpty)
          'context': context.trim(),
      },
      options: Options(receiveTimeout: const Duration(seconds: 30)),
    );
    final data = response.data;
    if (data is Map && data['caption'] is String) {
      return (data['caption'] as String).trim();
    }
    return '';
  }
}
