import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/media.dart';

/// 全屏浏览时当前的屏幕方向。
enum ViewerOrientation { portrait, landscape }

/// 主界面以竖屏为主；视频页允许用户手动旋转到横屏，但不再按视频比例
/// 自动切换方向。
/// iPad 允许竖屏上下颠倒（系统习惯），手机上只有 portraitUp 会被 Info.plist 过滤。
const List<DeviceOrientation> _portraitOrientations = [
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
];

// 包含 4 个方向时 Android 使用 FULL_SENSOR：即使用户关闭了系统自动旋转，
// 视频页仍能通过手动转动手机横屏。
const List<DeviceOrientation> _videoOrientations = [
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

Future<void> lockAppPortrait() {
  return SystemChrome.setPreferredOrientations(_portraitOrientations);
}

/// 视频播放时允许手动横屏；是否真的旋转由用户和系统自动旋转开关决定。
Future<void> allowVideoRotation() {
  return SystemChrome.setPreferredOrientations(_videoOrientations);
}

/// 强制横屏（播放横屏视频、或用户点旋转按钮）。
Future<void> forceLandscape() {
  return SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}

/// 强制竖屏。
Future<void> forcePortrait() {
  return SystemChrome.setPreferredOrientations(_portraitOrientations);
}

/// 视频是不是横屏：优先用服务端返回的宽高，拿不到时按横屏处理。
bool isLandscapeVideo(Media media) {
  final width = media.width ?? 0;
  final height = media.height ?? 0;
  if (width > 0 && height > 0) return width > height;
  return true;
}

/// video_player 的 aspectRatio 不包含 90/270 度旋转元数据；
/// 竖屏手机拍摄的视频如果带旋转标记，会用错误比例渲染。
double correctedVideoAspectRatio(VideoPlayerValue value) {
  final ratio = value.aspectRatio;
  if (ratio <= 0) return 1;
  return value.rotationCorrection % 180 == 0 ? ratio : 1 / ratio;
}
