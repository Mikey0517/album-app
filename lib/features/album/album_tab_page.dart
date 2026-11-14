import 'package:flutter/material.dart';

import '../../core/album_view_settings.dart';
import '../../core/design/colors.dart';
import '../../widgets/app_category_menu.dart';
import 'custom_albums_page.dart';
import 'feed_gallery_page.dart';

/// 分类顺序即选中下标：0 朋友圈相册 / 1 家庭相册 / 2 私人相册。
const List<String> _categories = ['朋友圈相册', '家庭相册', '私人相册'];

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

  /// 分类标题行的紧凑高度：标题一行说完，下面直接是内容。
  static const double _toolbarHeight = 48;

  final GlobalKey<FeedGalleryPageState> _feedGalleryKey = GlobalKey();
  int _selected = _defaultTab;
  bool _feedSelecting = false;
  int _feedSelected = 0;
  int _feedTotal = 0;

  /// 各个分类的相册数量，由子页加载完回报；没加载完就先不显示数字。
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
    return Scaffold(
      appBar: AppBar(
        // 相册总页的「分类」是这一页的层级，用标题 + 下拉表达；相册详情页里
        // 的「全部/照片/视频」才是页内筛选（分段条）。两者形式必须区分开。
        // 高度压到 48：标题行下面直接是内容，不再夹一条 46 高的分段条带子。
        toolbarHeight: _toolbarHeight,
        centerTitle: false,
        leading: _feedEditing
            ? IconButton(
                onPressed: () => _feedGalleryKey.currentState?.exitSelection(),
                icon: const Icon(Icons.close),
                tooltip: '退出选择',
              )
            : null,
        title: _feedEditing
            ? Text('已选 $_feedSelected 项')
            : AppCategoryMenu(
                items: [
                  for (var i = 0; i < _categories.length; i++)
                    AppCategoryItem(
                      _categories[i],
                      count: _tabCounts[i],
                    ),
                ],
                selectedIndex: _selected,
                onChanged: (index) {
                  if (_feedEditing) return;
                  _select(index);
                },
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
