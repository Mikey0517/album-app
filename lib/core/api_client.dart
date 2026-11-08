import 'dart:io';

import 'package:dio/dio.dart';

import 'auth_storage.dart';
import 'current_user.dart';
import 'server_config.dart';
import 'upload_errors.dart';

class ApiClient {
  ApiClient._();

  static final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 5),
      sendTimeout: const Duration(minutes: 5),
      headers: {'Accept': 'application/json'},
    ),
  );

  static Future<void> Function()? onUnauthorized;
  static bool _handlingUnauthorized = false;
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 不用 Dio.baseUrl：它用 Uri.resolve，baseUrl 带 /album 时会丢前缀。
          final incoming = options.path;
          final absolute =
              incoming.startsWith('http://') || incoming.startsWith('https://');
          if (!absolute) {
            final relative = (options.extra['relativePath'] as String?) ??
                (incoming.startsWith('/') ? incoming : '/$incoming');
            options.extra['relativePath'] = relative;
            options.baseUrl = '';
            options.path = '${ServerConfig.current}$relative';
          }
          final token = await AuthStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;
          final path = error.requestOptions.path;
          final isLoginPath = path.contains('/api/auth/login') ||
              path.contains('/api/auth/register') ||
              path.contains('/health');

          if (status == 401 && !isLoginPath) {
            await _triggerUnauthorized();
            handler.next(error);
            return;
          }

          final isNetworkError =
              error.type == DioExceptionType.connectionTimeout ||
                  error.type == DioExceptionType.connectionError ||
                  error.type == DioExceptionType.receiveTimeout ||
                  error.type == DioExceptionType.sendTimeout;

          // multipart 的 FormData 流只能消费一次，不能在拦截器里重放；
          // 上传接口会重建 FormData 并在业务层自行重试。
          final isMultipart = error.requestOptions.data is FormData;

          // 网络错误只切换一次，并用 retried 防止来回切换死循环。
          if (isNetworkError &&
              !isMultipart &&
              error.requestOptions.extra['retried'] != true) {
            final switched = await ServerConfig.trySwitchFallback();
            if (switched) {
              try {
                final options = error.requestOptions;
                options.extra['retried'] = true;
                final relative = options.extra['relativePath'] as String?;
                if (relative != null) {
                  options.baseUrl = '';
                  options.path = '${ServerConfig.current}$relative';
                }
                final response = await dio.fetch(options);
                return handler.resolve(response);
              } catch (_) {
                // 重试也失败，继续走原错误。
              }
            }
          }

          handler.next(error);
        },
      ),
    );
  }

  static Future<void> _triggerUnauthorized() async {
    if (_handlingUnauthorized) return;
    _handlingUnauthorized = true;
    try {
      await AuthStorage.clear();
      CurrentUser.notifier.value = null;
      await onUnauthorized?.call();
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        _handlingUnauthorized = false;
      });
    }
  }

  /// 供设置页测试单个地址用；返回 null 表示连通。
  static Future<String?> ping(String baseUrl) async {
    final result = await ServerConfig.probe(baseUrl);
    return result.ok ? null : (result.error ?? '连接失败');
  }

  static String errorText(Object error) {
    if (error is UploadSourceMissingException) {
      return '原文件已失效，请重新上传';
    }
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '网络超时，请稍后重试';
        case DioExceptionType.connectionError:
          return '无法连接服务器';
        case DioExceptionType.cancel:
          return '上传已取消';
        case DioExceptionType.unknown:
          final inner = error.error;
          if (inner is SocketException || inner is HttpException) {
            return '网络已断开，请检查网络后重试';
          }
          if (inner is FileSystemException) {
            return '原文件已失效，请重新上传';
          }
          break;
        default:
          break;
      }
      final status = error.response?.statusCode;
      if (status != null) return '请求失败（HTTP $status）';
      return error.message ?? '网络请求失败';
    }
    if (error is FileSystemException) return '原文件已失效，请重新上传';
    if (error is FormatException) return error.message;
    return '操作失败，请稍后重试';
  }
}
