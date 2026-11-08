import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/colors.dart';
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
      child: Scaffold(
        backgroundColor: AppColors.bgPage,
        body: GestureDetector(
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
        bottomNavigationBar: _hideNavigation
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) {
                  // 点底部「相册」始终先回到家庭相册。
                  if (value == 1) _albumKey.currentState?.resetToDefault();
                  setState(() => _index = value);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.people_outline),
                    selectedIcon: Icon(Icons.people),
                    label: '朋友圈',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.photo_library_outlined),
                    selectedIcon: Icon(Icons.photo_library),
                    label: '相册',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: '我的',
                  ),
                ],
              ),
      ),
    );
  }
}
