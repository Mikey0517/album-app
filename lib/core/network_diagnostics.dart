import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'server_config.dart';

/// 一次请求的三段耗时：建连、首字节、整体。
class ProbeSample {
  final int connectMs;
  final int ttfbMs;
  final int totalMs;
  final int? statusCode;
  final String? server;
  final String? error;

  const ProbeSample({
    required this.connectMs,
    required this.ttfbMs,
    required this.totalMs,
    this.statusCode,
    this.server,
    this.error,
  });

  bool get ok => error == null && statusCode != null && statusCode! < 500;

  String get label {
    if (!ok) return error ?? '连接失败';
    return 'HTTP $statusCode';
  }
}

class UrlDiagnostics {
  final String label;
  final String url;
  final List<ProbeSample> samples;

  const UrlDiagnostics({
    required this.label,
    required this.url,
    required this.samples,
  });

  ProbeSample? get first => samples.isEmpty ? null : samples.first;

  ProbeSample? get best {
    final okSamples = samples.where((s) => s.ok).toList();
    if (okSamples.isEmpty) return null;
    return okSamples.reduce((a, b) => a.totalMs <= b.totalMs ? a : b);
  }
}

/// 网络诊断结果：既给界面展示，也能整段复制发给别人排查。
class NetworkDiagnosticsReport {
  final String networkKind;
  final String activeMode;
  final String activeUrl;
  final List<UrlDiagnostics> targets;
  final String platform;
  final String appVersion;

  const NetworkDiagnosticsReport({
    required this.networkKind,
    required this.activeMode,
    required this.activeUrl,
    required this.targets,
    required this.platform,
    required this.appVersion,
  });

  /// 根据耗时特征给出人话结论。
  List<String> get findings {
    final notes = <String>[];
    for (final target in targets) {
      final first = target.first;
      if (first == null) continue;
      if (!first.ok) {
        notes.add('${target.label}连不上：${first.error ?? '未知原因'}');
        continue;
      }
      final okSamples = target.samples.where((s) => s.ok).toList();
      final others = okSamples.length > 1
          ? okSamples.sublist(1)
          : const <ProbeSample>[];
      final fastest = okSamples.isEmpty
          ? first.totalMs
          : okSamples.map((s) => s.totalMs).reduce((a, b) => a < b ? a : b);
      if (others.isNotEmpty &&
          first.totalMs > 500 &&
          fastest * 3 < first.totalMs) {
        notes.add(
          '${target.label}第一次 ${first.totalMs}ms、之后只要 ${fastest}ms：'
          '连接建立阶段疑似丢包重传（Wi-Fi 省电、弱信号或 VPN/代理接管流量）',
        );
      } else if (first.connectMs < 200 && first.ttfbMs - first.connectMs > 800) {
        notes.add('${target.label}建连只要 ${first.connectMs}ms，但首字节 ${first.ttfbMs}ms：慢在服务端或中间代理');
      } else if (fastest > 500) {
        notes.add('${target.label}每次都要 ${fastest}ms：整条链路都慢，检查 Wi-Fi 频段/信号或代理');
      } else {
        notes.add('${target.label}正常（最快 ${fastest}ms）');
      }
    }
    return notes;
  }

  String toText() {
    final buffer = StringBuffer();
    buffer.writeln('家庭相册 · 网络诊断');
    buffer.writeln('时间：${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln('设备：$platform');
    buffer.writeln('版本：$appVersion');
    buffer.writeln('网络类型：$networkKind');
    buffer.writeln('当前线路：${activeMode.isEmpty ? '未连接' : activeMode} $activeUrl');
    for (final target in targets) {
      buffer.writeln('');
      buffer.writeln('${target.label} ${target.url}');
      if (target.samples.isEmpty) {
        buffer.writeln('  未采样');
        continue;
      }
      for (var i = 0; i < target.samples.length; i++) {
        final sample = target.samples[i];
        buffer.writeln(
          '  第${i + 1}次  建连 ${sample.connectMs}ms  首字节 ${sample.ttfbMs}ms  '
          '总计 ${sample.totalMs}ms  ${sample.label}',
        );
      }
    }
    buffer.writeln('');
    buffer.writeln('结论：');
    for (final note in findings) {
      buffer.writeln('· $note');
    }
    return buffer.toString();
  }
}

class NetworkDiagnostics {
  NetworkDiagnostics._();

  static Future<String> _networkKind() async {
    try {
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));
      if (results.contains(ConnectivityResult.wifi)) return 'Wi-Fi';
      if (results.contains(ConnectivityResult.ethernet)) return '有线';
      if (results.contains(ConnectivityResult.mobile)) return '移动数据';
      if (results.contains(ConnectivityResult.none)) return '未连接';
      return results.map((r) => r.name).join('/');
    } catch (_) {
      return '未知';
    }
  }

  /// 同一个地址连打 [times] 次。共用一条 HttpClient，
  /// 这样第二次开始会复用连接，正好用来区分「建连慢」和「链路一直慢」。
  static Future<UrlDiagnostics> _runTarget(
    String label,
    String url, {
    int times = 3,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final samples = <ProbeSample>[];
    if (url.trim().isEmpty) {
      return UrlDiagnostics(label: label, url: url, samples: samples);
    }
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 15)
      ..userAgent = 'AlbumApp-Diagnostics';
    try {
      final uri = Uri.parse('${url.replaceAll(RegExp(r'/+$'), '')}/health');
      for (var i = 0; i < times; i++) {
        samples.add(await _once(client, uri, timeout));
      }
    } finally {
      client.close(force: true);
    }
    return UrlDiagnostics(label: label, url: url, samples: samples);
  }

  static Future<ProbeSample> _once(
    HttpClient client,
    Uri uri,
    Duration timeout,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final request = await client.openUrl('GET', uri).timeout(timeout);
      final connectMs = watch.elapsedMilliseconds;
      final response = await request.close().timeout(timeout);
      final ttfbMs = watch.elapsedMilliseconds;
      await response.drain<void>().timeout(timeout);
      return ProbeSample(
        connectMs: connectMs,
        ttfbMs: ttfbMs,
        totalMs: watch.elapsedMilliseconds,
        statusCode: response.statusCode,
        server: response.headers.value('server'),
      );
    } catch (e) {
      final elapsed = watch.elapsedMilliseconds;
      return ProbeSample(
        connectMs: elapsed,
        ttfbMs: elapsed,
        totalMs: elapsed,
        error: _describe(e),
      );
    }
  }

  static String _describe(Object error) {
    if (error is TimeoutException) return '超时';
    if (error is SocketException) {
      final message = error.osError?.message ?? error.message;
      return '连接失败（$message）';
    }
    if (error is HttpException) return 'HTTP 异常：${error.message}';
    return error.toString();
  }

  static Future<NetworkDiagnosticsReport> run() async {
    await ServerConfig.init();
    final lan = ServerConfig.lanUrl ?? ServerConfig.defaultLanUrl;
    final wan = ServerConfig.wanUrl ?? ServerConfig.defaultWanUrl;
    final kind = await _networkKind();

    final results = await Future.wait<UrlDiagnostics>([
      _runTarget('局域网', lan),
      _runTarget('互联网', wan, times: 1, timeout: const Duration(seconds: 12)),
    ]);

    var version = '未知';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {
      // 桌面/测试环境拿不到版本号，忽略。
    }

    return NetworkDiagnosticsReport(
      networkKind: kind,
      activeMode: ServerConfig.notifier.value,
      activeUrl: ServerConfig.current,
      targets: results,
      platform: Platform.isIOS
          ? 'iOS ${Platform.operatingSystemVersion}'
          : Platform.isAndroid
              ? 'Android ${Platform.operatingSystemVersion}'
              : Platform.operatingSystem,
      appVersion: version,
    );
  }
}
