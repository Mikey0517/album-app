import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/server_config.dart';

/// iOS 更新信息：iPad 不能自己安装 IPA，只能跳浏览器去 TestFlight / 下载页。
class IosReleaseInfo {
  final int versionCode;
  final String versionName;
  final String url;

  const IosReleaseInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
  });
}

class IosUpdateService {
  IosUpdateService._();

  /// 没有配置更新地址（或解析失败）时返回 null，不打扰用户。
  static Future<IosReleaseInfo?> check() async {
    if (!Platform.isIOS) return null;
    Dio? dio;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final response = await dio.get<dynamic>(
        '${ServerConfig.current}/api/app/ios',
        options:
            Options(validateStatus: (status) => status == 200 || status == 404),
      );
      if (response.statusCode != 200 || response.data is! Map) return null;
      final map = Map<String, dynamic>.from(response.data as Map);
      final url = (map['url'] as String?)?.trim() ?? '';
      final versionCode = (map['versionCode'] as num?)?.toInt() ?? 0;
      if (url.isEmpty || versionCode <= currentCode) return null;
      return IosReleaseInfo(
        versionCode: versionCode,
        versionName: (map['versionName'] as String?)?.trim() ?? '',
        url: url,
      );
    } catch (_) {
      return null;
    } finally {
      dio?.close(force: true);
    }
  }
}
