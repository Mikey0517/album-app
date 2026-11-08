import 'package:flutter/foundation.dart';

/// 跨 Tab 的轻量刷新信号，避免引入全局状态管理库。
class AppEvents {
  /// 朋友圈动态变化（发布/删除）后自增，朋友圈相册监听并刷新。
  static final ValueNotifier<int> feedGalleryRevision = ValueNotifier<int>(0);

  /// 相册内容变化（例如重启后补传完成）后自增，相册详情页静默刷新。
  static final ValueNotifier<int> albumContentRevision = ValueNotifier<int>(0);

  static void notifyPostChanged() {
    feedGalleryRevision.value++;
  }

  static void notifyAlbumContentChanged() {
    albumContentRevision.value++;
  }
}
