import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../media_picker.dart';
import 'hidden_space_store.dart';

/// 导入队列里的一条：来源（content URI）+ 复制进度。
class HiddenImportItem {
  final String id;
  final HiddenSource source;

  /// 复制完成后的私有目录路径；还没复制完是 null。
  String? path;
  double progress;
  bool done;
  bool failed;
  String? error;

  HiddenImportItem({required this.source})
      : id = const Uuid().v4(),
        progress = 0,
        done = false,
        failed = false;

  String get name => source.name;
  String get mime => source.mime;

  bool get isImage => source.mime.startsWith('image/');
  bool get isVideo => source.mime.startsWith('video/');

  String get status {
    if (failed) return '失败';
    if (done) return '已完成';
    if (progress > 0) return '上传中';
    return '等待中';
  }
}

/// 隐藏空间的导入队列。
///
/// 和相册的上传是同一套「上传中 x/y → 点开列表」的交互，只是动作不是网络上传，
/// 而是把系统选择器给的 content URI 一条条复制进 App 私有目录（原生
/// `copyHiddenFile`）。队列挂在进程上，**退出隐藏空间也在继续**；它的状态条
/// 只画在隐藏空间页面里，所以退出后看不到，再进来又能看到进度。
class HiddenImportManager extends ChangeNotifier {
  HiddenImportManager._();

  static final HiddenImportManager instance = HiddenImportManager._();

  final List<HiddenImportItem> items = [];

  bool _running = false;
  bool _sheetOpen = false;
  bool _acknowledged = true;
  int _added = 0;

  bool get isBusy => _running;
  bool get isUploading => _running;
  bool get hasItems => items.isNotEmpty;
  int get total => items.length;
  int get finished => items.where((item) => item.done || item.failed).length;
  int get failedCount => items.where((item) => item.failed).length;
  bool get sheetOpen => _sheetOpen;

  /// 状态条只在「有记录、面板没开、还没确认过」时出现。
  bool get showStatusChip => items.isNotEmpty && !_sheetOpen && !_acknowledged;

  /// 已经成功落盘的文件总数：页面靠它决定要不要刷新文件列表。
  int get addedCount => _added;

  double get progress {
    if (items.isEmpty) return 0;
    var sum = 0.0;
    for (final item in items) {
      sum += item.progress;
    }
    return sum / items.length;
  }

  /// 把新选中的文件排进队列，立刻开始逐条复制。
  Future<void> enqueue(List<HiddenSource> sources) async {
    if (sources.isEmpty) return;
    _acknowledged = false;
    for (final source in sources) {
      items.add(HiddenImportItem(source: source));
    }
    notifyListeners();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    notifyListeners();
    try {
      String? targetDir;
      for (final item in List<HiddenImportItem>.of(items)) {
        if (item.done || item.failed) continue;
        try {
          targetDir ??= (await HiddenSpaceStore.directory()).path;
          // 0.05 表示「这一条已经开始」，列表里能看到它从等待变成上传中。
          item.progress = 0.05;
          notifyListeners();
          final copied =
              await copyHiddenSource(item.source, targetDir: targetDir);
          await HiddenSpaceStore.addImported(
            path: copied.path,
            name: item.source.name,
            mime: item.source.mime,
            size: copied.size,
          );
          item.path = copied.path;
          item.progress = 1;
          item.done = true;
          _added += 1;
        } catch (e) {
          item.progress = 1;
          item.failed = true;
          item.error = '$e';
        }
        notifyListeners();
      }
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  void setSheetOpen(bool open) {
    if (_sheetOpen == open) return;
    _sheetOpen = open;
    notifyListeners();
  }

  /// 面板关掉、这一轮也结束了：状态条收起来（和相册上传的确认逻辑一致）。
  void acknowledgeCompleted() {
    if (_running || items.isEmpty) return;
    _acknowledged = true;
    notifyListeners();
  }

  /// 测试用：清空队列状态。
  @visibleForTesting
  void resetForTest() {
    items.clear();
    _running = false;
    _sheetOpen = false;
    _acknowledged = true;
    _added = 0;
  }

  void clearFinished() {
    items.removeWhere((item) => item.done || item.failed);
    if (items.isEmpty) _acknowledged = true;
    notifyListeners();
  }
}
