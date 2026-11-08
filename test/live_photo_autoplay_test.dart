import 'package:album_app/features/viewer/live_photo_view.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WiFi / 有线下自动播放动态照片', () {
    expect(shouldAutoPlayMotionPhoto([ConnectivityResult.wifi]), isTrue);
    expect(shouldAutoPlayMotionPhoto([ConnectivityResult.ethernet]), isTrue);
  });

  test('移动流量下不自动播放', () {
    expect(shouldAutoPlayMotionPhoto([ConnectivityResult.mobile]), isFalse);
    expect(
      shouldAutoPlayMotionPhoto(
        [ConnectivityResult.mobile, ConnectivityResult.wifi],
      ),
      isTrue,
      reason: '同时连着 WiFi 时按 WiFi 处理',
    );
    expect(shouldAutoPlayMotionPhoto([]), isFalse);
  });
}
