import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServerProbeResult {
  final bool ok;
  final int? latencyMs;
  final String? error;

  const ServerProbeResult({required this.ok, this.latencyMs, this.error});

  String get label {
    if (ok) return '已连接 · ${latencyMs ?? 0} ms';
    return error ?? '连接失败';
  }
}

class ServerConfig {
  static const String _kLanUrl = 'lan_url';
  static const String _kWanUrl = 'wan_url';
  static const String _kActive = 'active_url';
  static const String _kLegacy = 'server_base_url';

  static const String defaultLanUrl = 'http://192.168.1.100:8000';
  static const String defaultWanUrl = 'https://album.mikeyxu.top:8443';

  static String? _lan;
  static String? _wan;
  static String? _active;
  static bool _loaded = false;

  @visibleForTesting
  static String? networkKindForTest;

  static String? get lanUrl => _lan;
  static String? get wanUrl => _wan;
  static String? get activeUrl => _active;

  /// 同步返回当前生效地址；init() 之前退化为默认局域网地址。
  static String get current =>
      _active ?? _lan ?? _normalizeDefault(defaultLanUrl);

  static bool get isUsingLan => _active != null && _active == _lan;

  /// '局域网' / '互联网' / ''（未连接）。
  static final ValueNotifier<String> notifier = ValueNotifier<String>('');

  @visibleForTesting
  static void resetForTest() {
    _lan = null;
    _wan = null;
    _active = null;
    _loaded = false;
    _detecting = null;
    notifier.value = '';
  }

  static Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      var lan = normalize(prefs.getString(_kLanUrl) ?? '');
      var wan = normalize(prefs.getString(_kWanUrl) ?? '');
      final legacy = prefs.getString(_kLegacy);

      // 旧版本只有一个地址；迁移到局域网地址，互联网使用默认值。
      if (lan == null && legacy != null && legacy.trim().isNotEmpty) {
        lan = normalize(legacy);
        if (lan != null) {
          await prefs.setString(_kLanUrl, lan);
        }
        await prefs.remove(_kLegacy);
      }

      lan ??= _normalizeDefault(defaultLanUrl);
      // 互联网入口固定使用当前子域名；旧版本保存的地址在升级时自动纠正。
      wan = _normalizeDefault(defaultWanUrl);
      await prefs.setString(_kWanUrl, wan);

      _lan = lan;
      _wan = wan;

      // 冷启动按当前链路选择：WiFi 先局域网，移动数据先互联网。
      _active = await _preferredUrlForCurrentNetwork();
    } catch (_) {
      _lan ??= _normalizeDefault(defaultLanUrl);
      _wan ??= _normalizeDefault(defaultWanUrl);
      _active ??= _wan;
    } finally {
      _loaded = true;
    }
  }

  static Future<void> setLan(String url) async {
    final normalized = normalize(url);
    if (url.trim().isNotEmpty && normalized == null) {
      throw FormatException(validate(url) ?? '局域网地址格式不正确');
    }
    _lan = normalized;
    final prefs = await SharedPreferences.getInstance();
    if (normalized == null) {
      await prefs.remove(_kLanUrl);
    } else {
      await prefs.setString(_kLanUrl, normalized);
    }
    _ensureActiveIsOneOf();
  }

  static Future<void> setWan(String url) async {
    final normalized = normalize(url);
    if (url.trim().isNotEmpty && normalized == null) {
      throw FormatException(validate(url) ?? '互联网地址格式不正确');
    }
    _wan = normalized;
    final prefs = await SharedPreferences.getInstance();
    if (normalized == null) {
      await prefs.remove(_kWanUrl);
    } else {
      await prefs.setString(_kWanUrl, normalized);
    }
    _ensureActiveIsOneOf();
  }

  static void _ensureActiveIsOneOf() {
    if (_active == null || (_active != _lan && _active != _wan)) {
      _active = _lan ?? _wan;
    }
  }

  static Future<bool>? _detecting;

  @visibleForTesting
  static void setNetworkKindForTest(String? kind) {
    networkKindForTest = kind;
  }

  static Future<String?> _networkKind() async {
    if (networkKindForTest != null) return networkKindForTest;
    try {
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        return 'wifi';
      }
      if (results.contains(ConnectivityResult.mobile)) return 'mobile';
    } catch (_) {
      // 测试环境或系统接口异常时交给探测顺序兜底。
    }
    return null;
  }

  static Future<String> _preferredUrlForCurrentNetwork() async {
    final kind = await _networkKind();
    if (kind == 'wifi') return _lan ?? _wan!;
    if (kind == 'mobile') return _wan ?? _lan!;
    return _lan ?? _wan!;
  }

  static Future<bool> detectActive() {
    return _detecting ??= _doDetect().whenComplete(() => _detecting = null);
  }

  static Future<bool> _doDetect() async {
    final kind = await _networkKind();
    final wanFirst = kind == 'mobile';
    if (!wanFirst &&
        _lan != null &&
        await _ping(_lan!, timeout: const Duration(seconds: 3))) {
      await _activate(_lan!, '局域网');
      return true;
    }
    if (_wan != null &&
        await _ping(_wan!, timeout: const Duration(seconds: 12))) {
      await _activate(_wan!, '互联网');
      return true;
    }
    if (wanFirst &&
        _lan != null &&
        await _ping(_lan!, timeout: const Duration(seconds: 3))) {
      await _activate(_lan!, '局域网');
      return true;
    }
    notifier.value = '';
    return false;
  }

  /// 切到移动网络时优先使用互联网地址。
  static Future<bool> switchToWan() async {
    if (_wan == null) return false;
    if (_active == _wan) return true;
    if (await _ping(_wan!, timeout: const Duration(seconds: 12))) {
      await _activate(_wan!, '互联网');
      return true;
    }
    return false;
  }

  static Future<bool> trySwitchFallback() async {
    final current = _active;
    if (current == null) return detectActive();

    if (current == _lan && _wan != null) {
      if (await _ping(_wan!, timeout: const Duration(seconds: 12))) {
        await _activate(_wan!, '互联网');
        return true;
      }
    } else if (current == _wan && _lan != null) {
      if (await _ping(_lan!, timeout: const Duration(seconds: 3))) {
        await _activate(_lan!, '局域网');
        return true;
      }
    }
    return false;
  }

  static Future<void> _activate(String url, String mode) async {
    _active = url;
    notifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActive, url);
    } catch (_) {
      // 持久化失败不影响本次使用。
    }
  }

  static Future<bool> _ping(
    String url, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final result = await probe(url, timeout: timeout);
    return result.ok;
  }

  static Future<ServerProbeResult> probe(
    String input, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final validation = validate(input);
    if (validation != null) {
      return ServerProbeResult(ok: false, error: validation);
    }
    final normalized = normalize(input)!;
    final dio = Dio();
    final watch = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>(
        '$normalized/health',
        options: Options(
          connectTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (status) => status != null,
        ),
      );
      watch.stop();
      if (response.statusCode != 200) {
        return ServerProbeResult(
          ok: false,
          latencyMs: watch.elapsedMilliseconds,
          error: '服务器异常（HTTP ${response.statusCode}）',
        );
      }
      final data = response.data;
      if (data is Map && data['ok'] == false) {
        return ServerProbeResult(
          ok: false,
          latencyMs: watch.elapsedMilliseconds,
          error: '服务器响应异常',
        );
      }
      return ServerProbeResult(
        ok: true,
        latencyMs: watch.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      watch.stop();
      final error = switch (e.type) {
        DioExceptionType.connectionTimeout => '连接超时',
        DioExceptionType.receiveTimeout => '响应超时',
        DioExceptionType.sendTimeout => '发送超时',
        DioExceptionType.connectionError => '无法连接',
        DioExceptionType.badResponse => '服务器异常',
        _ => '连接失败',
      };
      return ServerProbeResult(
        ok: false,
        latencyMs: watch.elapsedMilliseconds,
        error: error,
      );
    } catch (_) {
      watch.stop();
      return const ServerProbeResult(ok: false, error: '连接失败');
    } finally {
      dio.close(force: true);
    }
  }

  static String? validate(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return '请输入服务器地址';
    if (raw.contains(RegExp(r'\s'))) return '地址不能包含空格';

    final withScheme = raw.contains('://') ? raw : 'http://$raw';
    final Uri uri;
    try {
      uri = Uri.parse(withScheme);
    } on FormatException {
      return '服务器地址格式不正确';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '仅支持 http:// 或 https://';
    }
    if (uri.host.isEmpty) return '缺少服务器 IP 或域名';
    if (uri.userInfo.isNotEmpty) return '地址不能包含用户名或密码';
    if (uri.hasQuery || uri.hasFragment) return '地址不能包含查询参数';
    return null;
  }

  /// 去空格、补 http://、去末尾斜杠，并保留路径（例如 /album）。
  static String? normalize(String input) {
    if (validate(input) != null) return null;
    var value = input.trim();
    if (!value.contains('://')) value = 'http://$value';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    final uri = Uri.parse(value);
    final host =
        uri.host.contains(':') ? '[${uri.host}]' : uri.host.toLowerCase();
    final port = uri.hasPort ? ':${uri.port}' : '';
    final path = uri.path == '/' ? '' : uri.path;
    return '${uri.scheme.toLowerCase()}://$host$port$path';
  }

  static String _normalizeDefault(String value) {
    return normalize(value) ?? value;
  }
}
