import 'package:album_app/core/network_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

ProbeSample _sample(int connect, int ttfb, int total, {bool ok = true}) {
  return ProbeSample(
    connectMs: connect,
    ttfbMs: ttfb,
    totalMs: total,
    statusCode: ok ? 200 : null,
    error: ok ? null : '连接失败',
  );
}

NetworkDiagnosticsReport _report(List<UrlDiagnostics> targets) {
  return NetworkDiagnosticsReport(
    networkKind: 'Wi-Fi',
    activeMode: '局域网',
    activeUrl: 'http://192.168.1.100:8000',
    targets: targets,
    platform: 'iOS',
    appVersion: '1.2.71 (75)',
  );
}

void main() {
  test('首次慢、后续快时判定为建连阶段丢包重传', () {
    final report = _report([
      UrlDiagnostics(
        label: '局域网',
        url: 'http://192.168.1.100:8000',
        samples: [
          _sample(1010, 1380, 1385),
          _sample(3, 21, 24),
          _sample(3, 20, 23),
        ],
      ),
    ]);
    final findings = report.findings.join();
    expect(findings, contains('第一次 1385ms'));
    expect(findings, contains('丢包重传'));
  });

  test('每次都慢时判定为链路问题', () {
    final report = _report([
      UrlDiagnostics(
        label: '局域网',
        url: 'http://192.168.1.100:8000',
        samples: [
          _sample(600, 900, 950),
          _sample(600, 880, 920),
        ],
      ),
    ]);
    expect(report.findings.join(), contains('整条链路都慢'));
  });

  test('建连快但首字节慢时判定为服务端或代理', () {
    final report = _report([
      UrlDiagnostics(
        label: '互联网',
        url: 'https://album.mikeyxu.top:8443',
        samples: [_sample(40, 1200, 1210)],
      ),
    ]);
    expect(report.findings.join(), contains('慢在服务端或中间代理'));
  });

  test('连不上时给出失败原因', () {
    final report = _report([
      UrlDiagnostics(
        label: '局域网',
        url: 'http://192.168.1.100:8000',
        samples: [_sample(3000, 3000, 3000, ok: false)],
      ),
    ]);
    expect(report.findings.join(), contains('连不上'));
  });

  test('复制出来的文本包含设备、版本与每次采样', () {
    final text = _report([
      UrlDiagnostics(
        label: '局域网',
        url: 'http://192.168.1.100:8000',
        samples: [_sample(1010, 1380, 1385), _sample(3, 21, 24)],
      ),
    ]).toText();
    expect(text, contains('版本：1.2.71 (75)'));
    expect(text, contains('网络类型：Wi-Fi'));
    expect(text, contains('第1次'));
    expect(text, contains('第2次'));
    expect(text, contains('结论：'));
  });
}
