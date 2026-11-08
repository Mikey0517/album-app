import 'package:flutter/material.dart';

import '../../core/album_view_settings.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/text_styles.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        titleSpacing: 8,
        leading: _feedEditing
            ? IconButton(
                onPressed: () => _feedGalleryKey.currentState?.exitSelection(),
                icon: const Icon(Icons.close),
                tooltip: '退出选择',
              )
            : null,
        title: _feedEditing
            ? Text('已选 $_feedSelected 项')
            : SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('朋友圈相册'),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('家庭相册'),
                    ),
                    ButtonSegment<int>(
                      value: 2,
                      label: Text('私人相册'),
                    ),
                  ],
                  selected: {_selected},
                  showSelectedIcon: false,
                  expandedInsets: EdgeInsets.zero,
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    _select(selection.first);
                  },
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 2),
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? AppColors.primary
                          : AppColors.bgSurface;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? Colors.white
                          : AppColors.textSecondary;
                    }),
                    side: WidgetStateProperty.all(
                      BorderSide(color: AppColors.borderLight),
                    ),
                    textStyle: WidgetStateProperty.all(
                      AppText.bodySmall.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                    minimumSize: WidgetStateProperty.all(const Size(0, 36)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
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
              setState(() => _selected += 1);
            } else {
              widget.onSwipeLeft?.call();
            }
          } else {
            if (_selected > 0) {
              setState(() => _selected -= 1);
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
            ),
            // 非 const：主题切换时需要重建相册列表。
            // ignore: prefer_const_constructors
            CustomAlbumsPage(scope: AlbumScope.family),
            // ignore: prefer_const_constructors
            CustomAlbumsPage(scope: AlbumScope.private),
          ],
        ),
      ),
    );
  }
}
