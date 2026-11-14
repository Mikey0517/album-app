import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/design/colors.dart';
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

  /// 底部导航：玻璃可用（`wrap` 成功且自适应质量没降到 minimal）时用
  /// [GlassTabBar.bottom]，否则回退原来的 [AppBottomTabBar]。
  ///
  /// 没有 [GlassAdaptiveScope] 说明 main() 里 initialize 失败或没包 wrap，
  /// 此时同样回退 —— 不能在拿不到 shader 质量上限的上下文里画玻璃。
  Widget _buildBottomBar(BuildContext context) {
    final quality = GlassAdaptiveScopeData.maybeOf(context)?.effectiveQuality;
    if (quality == null || quality == GlassQuality.minimal) {
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
    return GlassTabBar.bottom(
      selectedIndex: _index,
      onTabSelected: _onTabSelected,
      // 对齐 AppBottomTabBar 的 56 内容高 / 22 图标 / 10.5 字号。barHeight 本身
      // 可配，不必退让到默认 64；verticalPadding 是胶囊外浮动留白，收到 4 让
      // 整条高度 = 56 + 8 = 64，和 GlassTabBar 默认高度一致，比原来只高 8。
      barHeight: 56,
      iconSize: 22,
      labelFontSize: 10.5,
      verticalPadding: 4,
      selectedIconColor: AppColors.primary,
      unselectedIconColor: AppColors.textSecondary,
      selectedLabelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textSecondary,
      tabs: const [
        GlassTab(
          icon: Icon(Icons.people_outline),
          activeIcon: Icon(Icons.people),
          label: '朋友圈',
        ),
        GlassTab(
          icon: Icon(Icons.photo_library_outlined),
          activeIcon: Icon(Icons.photo_library),
          label: '相册',
        ),
        GlassTab(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
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
        bottomNavigationBar: _hideNavigation ? null : _buildBottomBar(context),
      ),
    );
  }
}
