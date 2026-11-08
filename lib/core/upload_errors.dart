import 'dart:io';

import 'package:dio/dio.dart';

/// 上传源文件已不存在（系统清理缓存 / 相册文件被移动）时抛出，
/// 这样界面可以给出“重新选择”的明确提示，而不是笼统的“操作失败”。
class UploadSourceMissingException implements Exception {
  final String path;

  const UploadSourceMissingException(this.path);

  @override
  String toString() => '上传源文件不存在：$path';
}

/// 用户主动点了“取消”。
class UploadCanceledException implements Exception {
  const UploadCanceledException();

  @override
  String toString() => '上传已取消';
}

/// 上传失败的原因分类，决定能否自动/手动重试。
enum UploadFailureKind {
  none,

  /// 用户主动取消。
  canceled,

  /// 网络中断、超时、连接被重置（锁屏后最常见）。
  network,

  /// 本地源文件已被清理，重试没有意义，必须重新选择。
  sourceMissing,

  /// 服务端明确拒绝（4xx）。
  server,

  other,
}

UploadFailureKind classifyUploadFailure(Object error) {
  if (error is UploadCanceledException) {
    return UploadFailureKind.canceled;
  }
  if (error is UploadSourceMissingException) {
    return UploadFailureKind.sourceMissing;
  }
  if (error is FileSystemException) {
    return UploadFailureKind.sourceMissing;
  }
  if (error is SocketException || error is HttpException) {
    return UploadFailureKind.network;
  }
  if (error is DioException) {
    // 上传途中源文件被清理时，dio 会把读取异常包进 unknown。
    final inner = error.error;
    if (inner is FileSystemException || inner is PathNotFoundException) {
      return UploadFailureKind.sourceMissing;
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return UploadFailureKind.network;
      case DioExceptionType.cancel:
        return UploadFailureKind.canceled;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        if (status == 408 || status == 429 || status >= 500) {
          return UploadFailureKind.network;
        }
        return UploadFailureKind.server;
      case DioExceptionType.transformTimeout:
        return UploadFailureKind.other;
    }
  }
  return UploadFailureKind.other;
}
