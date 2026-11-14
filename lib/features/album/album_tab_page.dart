import 'package:flutter/material.dart';

import '../../core/album_view_settings.dart';
import '../../core/design/colors.dart';
import '../../widgets/app_segmented_bar.dart';
import 'custom_albums_page.dart';
import 'feed_gallery_page.dart';

class AlbumTabPage extends StatefulWidget {
  final ValueChanged<bool>? onEditingChanged;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;

  const AlbumTabPage({
    super.key,
    this.onEditingChanged,
    this.onSwipeLeft,
    this.onSwipeRight,
  });

  @override
  State<AlbumTabPage> createState() => AlbumTabPageState();
}

class AlbumTabPageState extends State<AlbumTabPage> {
  /// 0 朋友圈相册 / 1 家庭相册 / 2 私人相册
  static const int _defaultTab = 1;

  final GlobalKey<FeedGalleryPageState> _feedGalleryKey = GlobalKey();
  int _selected = _defaultTab;
  bool _feedSelecting = false;
  int _feedSelected = 0;
  int _feedTotal = 0;

  /// 各个 tab 的内容数量，由子页加载完回报；没加载完就先不显示数字。
  final Map<int, int> _tabCounts = {};

  bool get _feedEditing => _selected == 0 && _feedSelecting;

  /// 点底部「相册」时回到家庭相册。
  void resetToDefault() {
    if (_selected == _defaultTab) return;
    if (_selected == 0) _feedGalleryKey.currentState?.exitSelection();
    setState(() => _selected = _defaultTab);
  }

  void _select(int next) {
    if (next == _selected) return;
    if (next != 0) _feedGalleryKey.currentState?.exitSelection();
    setState(() => _selected = next);
  }

  void _onTabCount(int tab, int count) {
    if (_tabCounts[tab] == count || !mounted) return;
    setState(() => _tabCounts[tab] = count);
  }

  @override
  Widget build(BuildContext context) {
    // 与相册详情页的筛选条同一套分段条：活动胶囊、字重、数量字号完全一致。
    final bar = AppSegmentedBar(
      expanded: true,
      selectedIndex: _selected,
      onChanged: (index) {
        if (_feedEditing) return;
        _select(index);
      },
      items: [
        AppSegmentedItem('朋友圈相册', count: _tabCounts[0]),
        AppSegmentedItem('家庭相册', count: _tabCounts[1]),
        AppSegmentedItem('私人相册', count: _tabCounts[2]),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: _feedEditing
            ? IconButton(
                onPressed: () => _feedGalleryKey.currentState?.exitSelection(),
                icon: const Icon(Icons.close),
                tooltip: '退出选择',
              )
            : null,
        title: _feedEditing ? Text('已选 $_feedSelected 项') : null,
        // tab 条随 AppBar 一起吸顶；多选态让出这条，操作更集中。
        bottom: _feedEditing
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(kAppSegmentedBarHeight),
                child: AppSegmentedBarSurface(child: bar),
              ),
        actions: _feedEditing
            ? [
                TextButton(
                  onPressed: () => _feedGalleryKey.currentState?.toggleAll(),
                  child: Text(
                    _feedSelected == _feedTotal ? '取消全选' : '全选',
                  ),
                ),
              ]
            : [
                if (_selected == 0)
                  IconButton(
                    onPressed: () => showAlbumViewMenu(context),
                    tooltip: '排序与视图',
                    icon: Icon(
                      Icons.tune_rounded,
                      size: 22,
                      color: AppColors.textPrimary,
                    ),
                  ),
              ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          if (_feedEditing) return;
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 260) return;
          if (velocity < 0) {
            if (_selected < 2) {
              _select(_selected + 1);
            } else {
              widget.onSwipeLeft?.call();
            }
          } else {
            if (_selected > 0) {
              _select(_selected - 1);
            } else {
              widget.onSwipeRight?.call();
            }
          }
        },
        child: IndexedStack(
          index: _selected,
          children: [
            FeedGalleryPage(
              key: _feedGalleryKey,
              onSelectionChanged: (selecting, selected, total) {
                if (!mounted) return;
                final wasEditing = _feedEditing;
                setState(() {
                  _feedSelecting = selecting;
                  _feedSelected = selected;
                  _feedTotal = total;
                });
                final editing = _selected == 0 && selecting;
                if (editing != wasEditing) {
                  widget.onEditingChanged?.call(editing);
                }
              },
              onCountChanged: (count) => _onTabCount(0, count),
            ),
            // 非 const：主题切换时需要重建相册列表，还要回报数量。
            CustomAlbumsPage(
              scope: AlbumScope.family,
              onCountChanged: (count) => _onTabCount(1, count),
            ),
            CustomAlbumsPage(
              scope: AlbumScope.private,
              onCountChanged: (count) => _onTabCount(2, count),
            ),
          ],
        ),
      ),
    );
  }
}
