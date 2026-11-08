import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api/album_api.dart';
import '../models/media.dart';
import 'api_client.dart';
import 'app_events.dart';
import 'picked_media_cleaner.dart';
import 'upload_errors.dart';
import 'upload_queue_store.dart';

/// 实际上传动作，单元测试可替换成假实现。
typedef UploadAction = Future<List<Media>> Function(
  int albumId,
  List<XFile> files, {
  void Function(int sent, int total)? onSendProgress,
  CancelToken? cancelToken,
});

class UploadItem {
  final int albumId;
  final String name;
  final String path;
  final bool isVideo;

  /// 系统相册里的原始 URI（上传成功后可以问用户要不要删除原图）。
  final String? sourceUri;

  /// 已经提示过「删除原图」，避免重复弹窗。
  bool sourceDeleteOffered;

  double progress;
  bool done;
  bool failed;
  String? error;

  /// 失败分类：决定重试按钮是否有意义。
  UploadFailureKind failure;

  /// 已排进队列等待重试（还没有开始上传）。
  bool retrying;

  /// 自动重试次数，避免后台恢复时无限重试。
  int autoRetries;

  /// 用户已取消（取消后条目会从列表移除，这里防止失败状态回写）。
  bool canceled;

  /// 上传成功后本地副本已删除（列表里不再显示缩略图）。
  bool sourceCleaned;

  UploadItem({
    required this.albumId,
    required this.name,
    required this.path,
    required this.isVideo,
    this.sourceUri,
    this.sourceDeleteOffered = false,
  })  : progress = 0,
        done = false,
        failed = false,
        error = null,
        failure = UploadFailureKind.none,
        retrying = false,
        autoRetries = 0,
        canceled = false,
        sourceCleaned = false;

  bool get sourceMissing => failure == UploadFailureKind.sourceMissing;

  /// 网络类失败可以重试；源文件丢失的只能重新选择。
  bool get canRetry => failed && !sourceMissing;

  String get status {
    if (failed) {
      if (sourceMissing) return '原文件已失效，请重新上传';
      return error == null ? '上传失败' : '失败：$error';
    }
    if (done) return '已完成';
    if (retrying && progress <= 0) return '等待重试…';
    if (progress > 0) {
      return '上传中 ${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';
    }
    return '等待上传';
  }
}

class _UploadBatch {
  final int albumId;
  final List<UploadItem> items;
  final VoidCallback? onFinished;

  /// 下一个待派发的下标。
  int next = 0;

  /// 已派发但还没结束的数量。
  int inFlight = 0;

  _UploadBatch({
    required this.albumId,
    required this.items,
    this.onFinished,
  });
}

/// 一次派发给某个并发槽位的任务。
class _UploadTask {
  final UploadItem item;
  final _UploadBatch batch;

  const _UploadTask(this.item, this.batch);
}

/// 一键重试的结果，用于给用户准确反馈。
class RetryAllResult {
  final int retried;
  final int missingSource;

  const RetryAllResult({required this.retried, required this.missingSource});

  bool get isEmpty => retried == 0 && missingSource == 0;

  int get total => retried + missingSource;
}

/// App 全局上传队列。页面关闭/切换 Tab 不会中断上传。
///
/// 几个关键行为：
/// - 上传期间保持屏幕常亮，避免锁屏把连接掐断（锁屏后上传失败的主因）。
/// - 锁屏/切到后台导致的网络失败不算失败，回到前台自动续传。
/// - 源文件被系统清理时明确提示“重新上传”，不再给一个点了没反应的重试。
class UploadManager extends ChangeNotifier {
  UploadManager._();

  static final UploadManager instance = UploadManager._();

  /// 上传实现，测试时替换。
  @visibleForTesting
  static UploadAction uploader = AlbumApi.upload;

  final List<UploadItem> items = [];
  final List<_UploadBatch> _queue = [];
  final Map<UploadItem, CancelToken> _activeTokens = {};
  final List<UploadItem> _pausedItems = [];
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _persistChain = Future<void>.value();
  bool _restored = false;
  final List<UploadItem> _restoredPending = [];
  bool _restoredRefreshPending = false;
  bool _running = false;
  bool _sheetOpen = false;
  bool _completedAwaitingAck = false;
  bool _appActive = true;
  bool _pausedForBackground = false;
  bool _keepAwake = false;

  /// 自动重试上限：网络恢复/回到前台时最多自动补几次。
  static const int maxAutoRetries = 2;

  /// 同时上传的文件数。
  ///
  /// 服务端每个文件都要 sha256 + ffprobe + ffmpeg 生成缩略图（同步），
  /// 单条串行时大部分时间都在等服务端处理；3 路并发可以让「传下一个文件」
  /// 和服务端「处理上一个文件」重叠，实测能明显缩短整批耗时。
  /// 再多会同时跑太多 ffmpeg、占用服务端 CPU，收益递减。
  static const int maxConcurrentUploads = 3;

  bool get isUploading => _running || _queue.isNotEmpty;

  /// 队列是否正在执行（测试用，避免在 _drain 退出前就恢复前台）。
  @visibleForTesting
  bool get running => _running;
  bool get sheetOpen => _sheetOpen;
  bool get completedAwaitingAck => _completedAwaitingAck;
  bool get showStatusChip =>
      isUploading || _completedAwaitingAck || failedCount > 0;
  int get total => items.length;
  int get finished => items.where((item) => item.done || item.failed).length;
  int get failedCount => items.where((item) => item.failed).length;
  int get retryableCount =>
      items.where((item) => item.failed && !item.sourceMissing).length;
  bool get hasItems => items.isNotEmpty;
  bool get appActive => _appActive;

  double get progress {
    if (total == 0) return 0;
    var value = finished.toDouble();
    for (final item in _activeTokens.keys) {
      if (!item.done && !item.failed) value += item.progress;
    }
    return (value / total).clamp(0.0, 1.0);
  }

  void acknowledgeCompleted() {
    if (!_completedAwaitingAck) return;
    _completedAwaitingAck = false;
    notifyListeners();
  }

  void setSheetOpen(bool open) {
    if (_sheetOpen == open) return;
    _sheetOpen = open;
    notifyListeners();
  }

  void enqueue({
    required int albumId,
    required List<XFile> files,
    List<String?>? sourceUris,
    VoidCallback? onFinished,
  }) {
    if (files.isEmpty) return;
    if (!_running && _queue.isEmpty) {
      // 只清掉上一批的成功项，失败项留着方便一键重试。
      items.removeWhere((item) => item.done && !item.failed);
    }
    _completedAwaitingAck = false;
    final batchItems = files
        .asMap()
        .entries
        .map((entry) => UploadItem(
              albumId: albumId,
              name: entry.value.name,
              path: entry.value.path,
              isVideo: _isVideo(entry.value.name),
              sourceUri: sourceUris != null && entry.key < sourceUris.length
                  ? sourceUris[entry.key]
                  : null,
            ))
        .toList(growable: true);
    items.addAll(batchItems);
    _queue.add(_UploadBatch(
      albumId: albumId,
      items: batchItems,
      onFinished: onFinished,
    ));
    _persistSoon();
    notifyListeners();
    unawaited(_drain());
  }

  /// 并发调度：同时最多跑 [maxConcurrentUploads] 个上传，
  /// 每完成一个就补上下一个，直到队列清空。
  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    _syncWakelock();
    notifyListeners();
    final running = <Future<void>>{};
    try {
      while (true) {
        while (running.length < maxConcurrentUploads && !_pausedForBackground) {
          final task = _takeNext();
          if (task == null) break;
          late Future<void> future;
          future = _uploadItem(task.item).whenComplete(() {
            running.remove(future);
            _finishTask(task);
          });
          running.add(future);
        }
        if (running.isEmpty) break;
        await Future.any(running.toList());
      }
    } finally {
      _running = false;
      _syncWakelock();
      _persistSoon();
      if (items.isNotEmpty) _completedAwaitingAck = true;
      if (_restoredRefreshPending && _queue.isEmpty) {
        // 重启后续传完成，通知已打开的相册页静默刷新。
        _restoredRefreshPending = false;
        AppEvents.notifyAlbumContentChanged();
      }
      notifyListeners();
      // 收尾瞬间可能有新任务入队（重试/新一批），这里补一次调度。
      if (_queue.isNotEmpty && !_pausedForBackground && _activeTokens.isEmpty) {
        unawaited(_drain());
      }
    }
  }

  /// 从队首取下一个待上传的条目；一批全部派发完且没有在途任务时收尾。
  _UploadTask? _takeNext() {
    while (_queue.isNotEmpty) {
      final batch = _queue.first;
      while (batch.next < batch.items.length) {
        final candidate = batch.items[batch.next++];
        if (candidate.done || candidate.canceled) continue;
        batch.inFlight += 1;
        return _UploadTask(candidate, batch);
      }
      if (batch.inFlight > 0) return null;
      _queue.remove(batch);
      batch.onFinished?.call();
    }
    return null;
  }

  void _finishTask(_UploadTask task) {
    final batch = task.batch;
    batch.inFlight -= 1;
    if (batch.inFlight <= 0 && batch.next >= batch.items.length) {
      _queue.remove(batch);
      batch.onFinished?.call();
    }
  }

  Future<void> _uploadItem(UploadItem item) async {
    final cancelToken = CancelToken();
    _activeTokens[item] = cancelToken;
    item
      ..failed = false
      ..done = false
      ..failure = UploadFailureKind.none
      ..error = null
      ..progress = 0
      ..retrying = false
      ..canceled = false;
    notifyListeners();
    try {
      await uploader(
        item.albumId,
        [XFile(item.path, name: item.name)],
        onSendProgress: (sent, totalBytes) {
          item.progress = totalBytes > 0 ? sent / totalBytes : 0;
          _notifyProgress();
        },
        cancelToken: cancelToken,
      );
      item.progress = 1;
      item.done = true;
      item.autoRetries = 0;
      // 先落盘再去删副本：万一删完立刻被系统杀掉，重开也不会把这条当成待传。
      await _saveNow();
      final cleaned = await PickedMediaCleaner.deleteCopy(item.path);
      if (cleaned) item.sourceCleaned = true;
    } catch (e) {
      final kind = classifyUploadFailure(e);
      if (kind == UploadFailureKind.canceled || item.canceled) {
        // 用户取消：条目已从列表移除，这里只做收尾。
      } else if (kind == UploadFailureKind.network && !_appActive) {
        // 锁屏/切后台时系统掐断连接：先挂起，回到前台继续，不误报失败。
        item.retrying = true;
        item.autoRetries += 1;
        _pausedForBackground = true;
        _pausedItems.add(item);
        _persistSoon();
      } else {
        item.failed = true;
        item.done = false;
        item.failure = kind;
        item.error = kind == UploadFailureKind.sourceMissing
            ? null
            : ApiClient.errorText(e);
        _persistSoon();
      }
    } finally {
      _activeTokens.remove(item);
      notifyListeners();
    }
  }

  /// 进度回调很密集：最多每 100ms 通知一次 UI，避免并发上传把主线程刷爆。
  void _notifyProgress() {
    final now = DateTime.now();
    if (now.difference(_lastProgressNotify).inMilliseconds < 100) return;
    _lastProgressNotify = now;
    notifyListeners();
  }

  /// 取走「已上传成功、带相册 URI、还没提示过删除原图」的条目。
  /// 每个条目只会被取走一次，避免重复弹窗。
  List<UploadItem> takeCompletedWithSource({int? albumId}) {
    final result = <UploadItem>[];
    for (final item in items) {
      if (!item.done || item.canceled) continue;
      if (albumId != null && item.albumId != albumId) continue;
      if (item.sourceUri == null || item.sourceDeleteOffered) continue;
      item.sourceDeleteOffered = true;
      result.add(item);
    }
    return result;
  }

  /// 只重试失败的那一条。返回是否真的排进了队列。
  bool retry(UploadItem item) {
    if (item.done) return false;
    item.autoRetries = 0;
    if (!File(item.path).existsSync()) {
      item
        ..failed = true
        ..done = false
        ..failure = UploadFailureKind.sourceMissing
        ..error = null
        ..progress = 0
        ..retrying = false;
      notifyListeners();
      return false;
    }
    _requeue([item]);
    return true;
  }

  /// 一键重试所有失败项（跳过源文件已失效的）。
  RetryAllResult retryAllFailed() {
    final failedItems =
        items.where((item) => item.failed).toList(growable: false);
    if (failedItems.isEmpty) {
      return const RetryAllResult(retried: 0, missingSource: 0);
    }
    final retryable = <UploadItem>[];
    var missing = 0;
    for (final item in failedItems) {
      if (File(item.path).existsSync()) {
        item.autoRetries = 0;
        retryable.add(item);
      } else {
        // 源文件已被系统清理：标记为“请重新上传”，不再给无效的重试。
        item
          ..failed = true
          ..done = false
          ..failure = UploadFailureKind.sourceMissing
          ..error = null
          ..progress = 0
          ..retrying = false;
        missing += 1;
      }
    }
    if (retryable.isNotEmpty) {
      _requeue(retryable);
    } else {
      notifyListeners();
    }
    return RetryAllResult(retried: retryable.length, missingSource: missing);
  }

  void _requeue(List<UploadItem> targets) {
    final byAlbum = <int, List<UploadItem>>{};
    for (final item in targets) {
      if (item.done) continue;
      if (!File(item.path).existsSync()) {
        item
          ..failed = true
          ..done = false
          ..failure = UploadFailureKind.sourceMissing
          ..error = null
          ..progress = 0
          ..retrying = false;
        continue;
      }
      item
        ..failed = false
        ..done = false
        ..failure = UploadFailureKind.none
        ..error = null
        ..progress = 0
        ..retrying = true;
      byAlbum.putIfAbsent(item.albumId, () => []).add(item);
    }
    if (byAlbum.isEmpty) {
      notifyListeners();
      return;
    }
    for (final entry in byAlbum.entries) {
      _queue.add(_UploadBatch(albumId: entry.key, items: entry.value));
    }
    _completedAwaitingAck = false;
    notifyListeners();
    unawaited(_drain());
  }

  /// 取消某一条：排队中的直接移除，正在上传的中断请求。
  void cancel(UploadItem item) {
    item.canceled = true;
    for (final batch in _queue) {
      batch.items.remove(item);
    }
    _queue.removeWhere((batch) => batch.items.isEmpty);
    _activeTokens[item]?.cancel('user');
    items.remove(item);
    unawaited(PickedMediaCleaner.deleteCopy(item.path));
    _persistSoon();
    _syncWakelock();
    notifyListeners();
  }

  /// 取消全部排队中/正在上传的任务，保留已完成与失败记录。
  void cancelAll() {
    for (final token in _activeTokens.values) {
      token.cancel('user');
    }
    _queue.clear();
    _pausedItems.clear();
    for (final item in items) {
      if (!item.done && !item.failed) item.canceled = true;
    }
    final discarded =
        items.where((item) => !item.done && !item.failed).toList();
    items.removeWhere((item) => !item.done && !item.failed);
    for (final item in discarded) {
      unawaited(PickedMediaCleaner.deleteCopy(item.path));
    }
    _persistSoon();
    _syncWakelock();
    notifyListeners();
  }

  /// 移除一条记录（源文件失效时用“移除”代替无效的“重试”）。
  void removeItem(UploadItem item) {
    items.remove(item);
    for (final batch in _queue) {
      batch.items.remove(item);
    }
    _queue.removeWhere((batch) => batch.items.isEmpty);
    if (!_activeTokens.containsKey(item)) {
      unawaited(PickedMediaCleaner.deleteCopy(item.path));
    }
    _persistSoon();
    _syncWakelock();
    notifyListeners();
  }

  /// 清空已完成/失败的记录。
  void clearFinished() {
    if (_running) return;
    final discarded = items.where((item) => item.done || item.failed).toList();
    items.removeWhere((item) => item.done || item.failed);
    for (final item in discarded) {
      unawaited(PickedMediaCleaner.deleteCopy(item.path));
    }
    _completedAwaitingAck = false;
    _persistSoon();
    _syncWakelock();
    notifyListeners();
  }

  /// App 生命周期：前后台切换。后台断网不算失败，回前台自动续传。
  /// 注意：这里不清除 _pausedForBackground，续传统一由 [onAppResumed] 处理。
  void setAppActive(bool active) {
    if (_appActive == active) return;
    _appActive = active;
    notifyListeners();
  }

  /// 回到前台：继续被挂起的队列，或自动补一次网络失败。
  void onAppResumed() {
    _appActive = true;
    if (_pausedForBackground) {
      _pausedForBackground = false;
      final paused = List<UploadItem>.of(_pausedItems);
      _pausedItems.clear();
      if (paused.isNotEmpty) {
        _requeue(paused);
      } else {
        unawaited(_drain());
      }
      return;
    }
    _autoRetryNetworkFailures();
  }

  /// 网络恢复（WiFi/移动数据重新可用）时自动补传。
  void onNetworkRestored() {
    _autoRetryNetworkFailures();
  }

  void _autoRetryNetworkFailures() {
    final targets = items
        .where((item) =>
            item.failed &&
            item.failure == UploadFailureKind.network &&
            item.autoRetries < maxAutoRetries)
        .toList(growable: false);
    if (targets.isEmpty) return;
    for (final item in targets) {
      item.autoRetries += 1;
    }
    _requeue(targets);
  }

  // ---- 队列持久化：App 被杀后重新打开可以接着传 ----

  void _persistSoon() {
    _persistChain =
        _persistChain.then((_) => _saveSnapshot()).catchError((Object _) {});
  }

  /// 立刻把当前快照写盘（上传成功后先写盘、再删本地副本）。
  Future<void> _saveNow() async {
    _persistSoon();
    await _persistChain;
  }

  Future<void> _saveSnapshot() async {
    final pending = items
        .where((item) => !item.done && !item.canceled)
        .map((item) => StoredUploadItem(
              albumId: item.albumId,
              name: item.name,
              path: item.path,
              isVideo: item.isVideo,
              failure: item.failure,
              error: item.error,
              autoRetries: item.autoRetries,
            ))
        .toList(growable: false);
    await UploadQueueStore.save(pending);
  }

  /// App 启动时调用：把上次没传完的任务读回列表（不发请求）。
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    final stored = await UploadQueueStore.load();
    if (stored.isEmpty) {
      // 队列是空的，顺手清掉上次崩溃/取消残留的副本。
      unawaited(PickedMediaCleaner.deleteOrphans(const []));
      return;
    }
    for (final entry in stored) {
      final item = UploadItem(
        albumId: entry.albumId,
        name: entry.name,
        path: entry.path,
        isVideo: entry.isVideo,
      )
        ..autoRetries = entry.autoRetries
        ..error = entry.error
        ..failure = entry.failure;
      if (!File(entry.path).existsSync()) {
        // 副本在上次被杀之后被系统清掉了：直接标成需要重新选择。
        item
          ..failed = true
          ..failure = UploadFailureKind.sourceMissing
          ..error = null;
      } else if (entry.failure == UploadFailureKind.none ||
          entry.failure == UploadFailureKind.network) {
        // 未完成 / 当时断网的，等登录态确认后自动继续。
        item.retrying = true;
        _restoredPending.add(item);
      } else {
        item.failed = true;
      }
      items.add(item);
    }
    // 只保留队列里还在用的副本，其余删掉，避免占满手机存储。
    unawaited(
      PickedMediaCleaner.deleteOrphans(items.map((item) => item.path)),
    );
    _persistSoon();
    notifyListeners();
  }

  /// 登录态确认后调用：开始续传上次没传完的任务。
  void resumeRestored() {
    if (_restoredPending.isEmpty) return;
    final pending = List<UploadItem>.of(_restoredPending);
    _restoredPending.clear();
    _restoredRefreshPending = true;
    _requeue(pending);
  }

  @visibleForTesting
  Future<void> flushPersistence() => _persistChain;

  @visibleForTesting
  List<UploadItem> get restoredPending => List.unmodifiable(_restoredPending);

  /// 上传时保持屏幕常亮，避免锁屏后连接被系统掐断。
  void _syncWakelock() {
    final want = isUploading;
    if (want == _keepAwake) return;
    _keepAwake = want;
    try {
      final future = want ? WakelockPlus.enable() : WakelockPlus.disable();
      unawaited(future.catchError((Object _) {}));
    } catch (_) {
      // 桌面/测试环境没有该插件时忽略。
    }
  }

  bool _isVideo(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    return const {'mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'}.contains(ext);
  }

  @visibleForTesting
  void resetForTest() {
    items.clear();
    _queue.clear();
    _running = false;
    _sheetOpen = false;
    _completedAwaitingAck = false;
    _appActive = true;
    _pausedForBackground = false;
    _keepAwake = false;
    _activeTokens.clear();
    _pausedItems.clear();
    _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);
    _persistChain = Future<void>.value();
    _restored = false;
    _restoredPending.clear();
    _restoredRefreshPending = false;
    uploader = AlbumApi.upload;
  }
}
