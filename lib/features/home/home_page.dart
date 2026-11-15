import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/app_bottom_tab_bar.dart';
import '../album/album_tab_page.dart';
import '../feed/feed_page.dart';
import '../profile/profile_page.dart';

class HomePage extends StatefulWidget {
  final VoidCallback onLogout;

  const HomePage({super.key, required this.onLogout});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  bool _hideNavigation = false;
  final GlobalKey<AlbumTabPageState> _albumKey = GlobalKey<AlbumTabPageState>();

  void _goTo(int index) {
    if (_hideNavigation || index < 0 || index > 2 || index == _index) return;
    setState(() => _index = index);
  }

  void _onTabSelected(int value) {
    // 点底部「相册」始终先回到家庭相册。
    if (value == 1) _albumKey.currentState?.resetToDefault();
    setState(() => _index = value);
  }

  /// 底部导航：一块悬浮胶囊玻璃（见 [AppBottomTabBar]），里面三个 tab 只是
  /// 图标 + 文字，没有滑块/胶囊指示器。玻璃不可用或降到 minimal 时由它自己
  /// 退化成同样的胶囊（不透明底 + 细边），这里不需要再分支。
  ///
  /// 它盖在页面上面（Stack 里排在 IndexedStack 之后），不占 Scaffold 的
  /// bottomNavigationBar 槽位：页面内容一直铺到屏幕底边，胶囊背后才有真实
  /// 的照片/卡片在滚动。页面只在滚动内容末尾留 [AppBottomTabBar.contentBottomInset]
  /// 的余量，不再整块让出胶囊高度。
  Widget _buildBottomBar(BuildContext context) {
    return AppBottomTabBar(
      selectedIndex: _index,
      onSelected: _onTabSelected,
      items: const [
        AppBottomTabItem(
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          label: '朋友圈',
        ),
        AppBottomTabItem(
          icon: Icons.photo_library_outlined,
          selectedIcon: Icons.photo_library,
          label: '相册',
        ),
        AppBottomTabItem(
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          label: '我的',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      // 外壳自己不上色：底色由三个页面各自的 [AppGlassBackdrop] 渐变负责，
      // 这层只是容器。extendBody 让 body 一直铺到屏幕底边——胶囊是叠在内容
      // 上的 overlay，任何「为它让出高度」的槽位都会让胶囊下面变回一片空底。
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  if (_index == 1 || _hideNavigation) return;
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() < 260) return;
                  _goTo(velocity < 0 ? _index + 1 : _index - 1);
                },
                child: IndexedStack(
                  index: _index,
                  children: [
                    // 非 const：主题切换时需要重建整个朋友圈页面。
                    // ignore: prefer_const_constructors
                    FeedPage(),
                    AlbumTabPage(
                      key: _albumKey,
                      onEditingChanged: (editing) {
                        if (!mounted || _hideNavigation == editing) return;
                        setState(() => _hideNavigation = editing);
                      },
                      onSwipeLeft: () => _goTo(2),
                      onSwipeRight: () => _goTo(0),
                    ),
                    ProfilePage(onLogout: widget.onLogout),
                  ],
                ),
              ),
            ),
            // 悬浮胶囊：盖在页面之上，页面内容从它底下穿过。
            if (!_hideNavigation)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomBar(context),
              ),
          ],
        ),
      ),
    );
  }
}
