import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'server_config.dart';

enum _NetKind { wifi, mobile, none }

/// 监听 WiFi / 移动网络变化：
/// - 连上 WiFi：先试局域网，失败保持/切到互联网
/// - 切到移动网络：直接尝试互联网
class NetworkMonitor {
  static final Connectivity _connectivity = Connectivity();

  /// 网络重新可用时回调（用于自动补传失败的上传任务）。
  static void Function()? onAvailable;
  static bool _started = false;
  static _NetKind? _lastKind;
  static _NetKind? _pendingKind;
  static Future<void>? _drainFuture;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    _lastKind = await _readKind();
    _connectivity.onConnectivityChanged.listen((results) {
      final kind = _kindOf(results);
      if (kind == _NetKind.none) return;
      // WiFi 每次事件都尝试局域网（例如从一个 WiFi 换到另一个）；
      // 移动网络只在类型变化时处理。
      if (kind == _NetKind.wifi || kind != _lastKind) {
        _lastKind = kind;
        unawaited(_enqueue(kind));
      }
    });
  }

  /// App 回前台时调用：补上后台期间可能漏掉的网络切换。
  static Future<void> refresh() async {
    if (!_started) return;
    final kind = await _readKind();
    if (kind == _NetKind.none || kind == _lastKind) return;
    _lastKind = kind;
    await _enqueue(kind);
  }

  static Future<_NetKind> _readKind() async {
    try {
      return _kindOf(await _connectivity.checkConnectivity());
    } catch (_) {
      return _NetKind.none;
    }
  }

  static _NetKind _kindOf(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return _NetKind.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) return _NetKind.mobile;
    return _NetKind.none;
  }

  static Future<void> _enqueue(_NetKind kind) {
    _pendingKind = kind;
    final existing = _drainFuture;
    if (existing != null) return existing;
    final future = _drain();
    _drainFuture = future;
    future.whenComplete(() {
      if (identical(_drainFuture, future)) _drainFuture = null;
    });
    return future;
  }

  static Future<void> _drain() async {
    try {
      while (_pendingKind != null) {
        final kind = _pendingKind!;
        _pendingKind = null;
        if (kind == _NetKind.wifi) {
          // 局域网优先，局域网不可达时 detectActive 会自动落回互联网。
          await ServerConfig.detectActive();
        } else if (kind == _NetKind.mobile) {
          await ServerConfig.switchToWan();
        }
        try {
          onAvailable?.call();
        } catch (_) {
          // 补传失败不影响网络切换本身。
        }
      }
    } finally {}
  }
}
