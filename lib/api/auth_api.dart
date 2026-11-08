import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/app_user.dart';

class AuthResult {
  final String token;
  final AppUser user;

  const AuthResult({required this.token, required this.user});

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      token: json['token'] as String? ?? '',
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>? ?? const {}),
    );
  }
}

class AuthApi {
  static final Dio _dio = ApiClient.dio;

  static Future<AuthResult> login(String userId, String password) async {
    final response = await _dio.post<dynamic>(
      '/api/auth/login',
      data: {'user_id': userId, 'password': password},
    );
    return AuthResult.fromJson(_asMap(response.data));
  }

  static Future<AuthResult> register(
    String userId,
    String nickname,
    String password,
  ) async {
    final response = await _dio.post<dynamic>(
      '/api/auth/register',
      data: {
        'user_id': userId,
        'nickname': nickname,
        'password': password,
      },
    );
    return AuthResult.fromJson(_asMap(response.data));
  }

  /// 修改当前用户昵称（服务端校验全局唯一）。
  static Future<AppUser> updateNickname(String nickname) async {
    final response = await _dio.patch<dynamic>(
      '/api/auth/me',
      data: {'nickname': nickname},
    );
    return AppUser.fromJson(_asMap(response.data));
  }

  static Future<AppUser> me() async {
    final response = await _dio.get<dynamic>('/api/auth/me');
    return AppUser.fromJson(_asMap(response.data));
  }

  static Future<void> logout() async {
    await _dio.post<dynamic>('/api/auth/logout');
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return const {};
  }
}
