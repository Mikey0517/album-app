import 'package:album_app/core/feed_view_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => FeedViewSettings.widescreen.value = false);

  test('默认关闭 = 九宫格', () async {
    SharedPreferences.setMockInitialValues({});
    await FeedViewSettings.init();
    expect(FeedViewSettings.widescreen.value, isFalse);
  });

  test('读到上次打开的大屏模式', () async {
    SharedPreferences.setMockInitialValues({FeedViewSettings.prefsKey: true});
    await FeedViewSettings.init();
    expect(FeedViewSettings.widescreen.value, isTrue);
  });

  test('切换后写回 SharedPreferences，冷启动能读回来', () async {
    SharedPreferences.setMockInitialValues({});
    await FeedViewSettings.init();

    await FeedViewSettings.setWidescreen(true);
    expect(FeedViewSettings.widescreen.value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FeedViewSettings.prefsKey), isTrue,
        reason: '开关要能记住，重启回到九宫格会很烦');

    await FeedViewSettings.setWidescreen(false);
    expect(prefs.getBool(FeedViewSettings.prefsKey), isFalse);
  });

  test('init 以存储值为准：没存过就回到关闭', () async {
    FeedViewSettings.widescreen.value = true;
    SharedPreferences.setMockInitialValues({});
    await FeedViewSettings.init();
    expect(FeedViewSettings.widescreen.value, isFalse);
  });
}
