import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_tab_page.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/features/home/home_page.dart';
import 'package:album_app/features/profile/profile_page.dart';
import 'package:album_app/features/viewer/image_view.dart';
import 'package:album_app/features/viewer/media_viewer_page.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_chrome_glass_bar.dart';
import 'package:album_app/widgets/stable_view_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http.dart';

/// 手机竖屏 + 「状态栏 24 / 三键导航条 48」的安全区。
const Size _phone = Size(390, 844);
const FakeViewPadding _visibleBars =
    FakeViewPadding(top: 24, bottom: 48);

/// 进入全屏浏览页后系统栏隐藏，平台这时上报的安全区是 0。
const FakeViewPadding _hiddenBars = FakeViewPadding.zero;

/// 「主界面上的列表 + 底部胶囊」：这几个 widget 在过渡期间重建一次都算翻车。
const Set<Type> _watched = <Type>{
  FeedPage,
  AlbumTabPage,
  ProfilePage,
  AppBottomTabBar,
};

Media _photo(int id) => Media(
      id: id,
      type: 'image',
      thumbUrl: null,
      url: 'https://example.test/media/$id.jpg',
      width: 1920,
      height: 1080,
      durationMs: null,
      takenAt: DateTime(2024, 8, 1),
      createdAt: DateTime(2024, 8, 1),
      postId: null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 直接给现成用户：主界面里的「我的」页不用去打 AuthApi.me。
    CurrentUser.notifier.value = const AppUser(
      id: 1,
      userId: 'mikey',
      nickname: 'Mikey',
    );
  });

  tearDown(() {
    CurrentUser.notifier.value = null;
  });

  /// 主界面用的就是生产那一层（main.dart 的 [appChromeBuilder]）。
  Widget host(GlobalKey<NavigatorState> navigatorKey) => MaterialApp(
        navigatorKey: navigatorKey,
        theme: buildAppTheme(),
        builder: appChromeBuilder(navigatorKey),
        home: HomePage(onLogout: () {}),
      );

  Future<void> usePhone(WidgetTester tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    tester.view.padding = _visibleBars;
    tester.view.viewPadding = _visibleBars;
  }

  Future<void> setInsets(WidgetTester tester, FakeViewPadding value) async {
    tester.view.padding = value;
    tester.view.viewPadding = value;
    await tester.pump();
  }

  testWidgets('进/出全屏浏览页：不切系统 UI 模式，主界面尺寸与底部胶囊 rect 一动不动，列表不重建',
      (tester) async {
    await usePhone(tester);
    addTearDown(installFakeApi(json: '{"items": [], "next_cursor": null}'));

    // 记下浏览页真的去切了系统 UI：否则这个用例的「insets 变了」就只是自说自话。
    final uiModes = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        uiModes.add(call.arguments.toString());
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    // 过渡期间的重建计数（框架的 debug 钩子，不改生产代码）。
    final rebuilds = <String, int>{};
    var counting = false;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (!counting || !_watched.contains(element.widget.runtimeType)) return;
      final type = element.widget.runtimeType.toString();
      rebuilds[type] = (rebuilds[type] ?? 0) + 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(host(navigatorKey));
    await tester.pumpAndSettle();

    final scaffoldFinder = find.byType(Scaffold).first;
    final barFinder = find.byType(AppBottomTabBar);
    final pillFinder = find.descendant(
      of: barFinder,
      matching: find.byType(AppChromeGlassBar),
    );
    final scaffoldBefore = tester.getRect(scaffoldFinder);
    final barBefore = tester.getRect(barFinder);
    final pillBefore = tester.getRect(pillFinder);
    final feedElement = tester.element(find.byType(FeedPage));
    final barElement = tester.element(barFinder);

    counting = true;

    // 1. 进入：浏览页一次都不动系统 UI 模式（旧实现切 immersiveSticky，退出再切
    //    回 edgeToEdge —— 那一下在不少 ROM 上连窗口尺寸一起变，钉住 padding 也
    //    救不回来，所以现在整条路径上没有 inset 变化）。
    navigatorKey.currentState!.push(
      MediaViewerPage.route(items: [_photo(1)], initialIndex: 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MediaViewerPage), findsOneWidget);
    expect(uiModes, isEmpty,
        reason: '浏览页不许切系统 UI 模式：实测调用 = $uiModes');

    // 满屏照旧：照片铺到屏幕四边（含状态栏/导航条底下那两块），全屏靠的是
    // 内容铺满 + 状态栏透明，不是靠藏系统栏。
    expect(
      tester.getRect(find.byType(ImageView)),
      Rect.fromLTWH(0, 0, _phone.width, _phone.height),
      reason: '浏览页必须仍然满屏',
    );
    // 全屏页自己读平台原始安全区（不是主界面那一层钉住的值），控制条照样躲开
    // 系统栏。
    expect(
      MediaQuery.paddingOf(tester.element(find.byType(ImageView))).bottom,
      _visibleBars.bottom,
      reason: '全屏页用的是原始 insets',
    );

    // 2. 顺手压一遍钉住那一层：就算平台真把安全区报成 0（下拉通知栏、系统手势
    //    提示、分屏拖动都会），主界面也不许动。
    await setInsets(tester, _hiddenBars);
    await tester.pump();

    // 3. 退出：220ms 反向动画跑完，页面整屏可见。
    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewerPage), findsNothing);
    expect(
      tester.getRect(barFinder),
      barBefore,
      reason: '安全区报成 0 的那一帧，胶囊就已经不许动了',
    );
    expect(tester.getRect(pillFinder), pillBefore);

    // 4. 安全区补回来。
    await setInsets(tester, _visibleBars);
    await tester.pump();
    counting = false;

    expect(find.byType(MediaViewerPage), findsNothing);

    // 5. 返回后一切照旧：Scaffold 尺寸、胶囊外框、胶囊玻璃，逐项相等。
    expect(tester.getRect(scaffoldFinder), scaffoldBefore,
        reason: 'Scaffold 尺寸/位置在退出前后必须完全一致');
    expect(tester.getRect(barFinder), barBefore,
        reason: '底部胶囊外框在退出前后必须完全一致');
    expect(tester.getRect(pillFinder), pillBefore,
        reason: '胶囊玻璃本体不许移动');

    // 6. 没有重建，也没有整棵子树被换掉。
    expect(
      rebuilds,
      isEmpty,
      reason: '进出全屏浏览页期间列表与胶囊一次都不许重建，实测: $rebuilds',
    );
    expect(
      identical(tester.element(find.byType(FeedPage)), feedElement),
      isTrue,
      reason: '朋友圈列表的 Element 必须是同一个',
    );
    expect(
      identical(tester.element(barFinder), barElement),
      isTrue,
      reason: '底部胶囊的 Element 必须是同一个',
    );
  });

  testWidgets('StableViewInsets：系统栏藏/露只钉安全区，窗口尺寸变了才重新取', (tester) async {
    var builds = 0;
    var capturedPadding = EdgeInsets.zero;
    var capturedViewPadding = EdgeInsets.zero;

    // 子树只建一次、实例复用：下面的「不重建」断言测的才是安全区，而不是
    // pumpWidget 换了个新 widget。
    final child = Builder(
      builder: (context) {
        builds++;
        final media = MediaQuery.of(context);
        capturedPadding = media.padding;
        capturedViewPadding = media.viewPadding;
        return const SizedBox.shrink();
      },
    );

    Widget hostWith({
      required Size size,
      required EdgeInsets padding,
      required EdgeInsets viewPadding,
      EdgeInsets viewInsets = EdgeInsets.zero,
    }) {
      return MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: padding,
          viewPadding: viewPadding,
          viewInsets: viewInsets,
        ),
        child: StableViewInsets(child: child),
      );
    }

    await tester.pumpWidget(hostWith(
      size: _phone,
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 48),
      viewPadding: const EdgeInsets.fromLTRB(0, 24, 0, 48),
    ));
    expect(capturedPadding.bottom, 48);
    expect(builds, 1);

    // 系统栏藏起来：安全区归零，但钉住的值不变，子树一次都不重建。
    await tester.pumpWidget(hostWith(
      size: _phone,
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.zero,
    ));
    expect(capturedPadding.bottom, 48);
    expect(capturedViewPadding.bottom, 48);
    expect(builds, 1, reason: '安全区变小不采纳，也不许通知依赖方重建');

    // 系统栏回来：值与原值相等，同样不重建。
    await tester.pumpWidget(hostWith(
      size: _phone,
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 48),
      viewPadding: const EdgeInsets.fromLTRB(0, 24, 0, 48),
    ));
    expect(capturedPadding.bottom, 48);
    expect(builds, 1);

    // 键盘弹起：平台只把 padding 压到 0，viewPadding 不变。钉的是 viewPadding，
    // 所以 padding 照样归零——编辑页/底部弹窗不会被钉出 48 的空隙。
    await tester.pumpWidget(hostWith(
      size: _phone,
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
      viewPadding: const EdgeInsets.fromLTRB(0, 24, 0, 48),
      viewInsets: const EdgeInsets.only(bottom: 300),
    ));
    expect(capturedPadding.bottom, 0, reason: '键盘占走的那块不再算进 padding');
    expect(capturedPadding.top, 24);
    expect(capturedViewPadding.bottom, 48);
    expect(builds, 2);

    // 旋转到横屏：窗口尺寸变了，安全区重新取当前值（左右 48、上下 0）。
    await tester.pumpWidget(hostWith(
      size: const Size(844, 390),
      padding: const EdgeInsets.fromLTRB(48, 0, 48, 0),
      viewPadding: const EdgeInsets.fromLTRB(48, 0, 48, 0),
    ));
    expect(capturedPadding.left, 48);
    expect(capturedPadding.bottom, 0, reason: '尺寸变了就不能再钉着竖屏的 48');
    expect(builds, 3);
  });
}
