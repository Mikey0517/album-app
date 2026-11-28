import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/design/text_styles.dart';
import '../../core/media_download_service.dart';
import '../../core/video_orientation.dart';
import '../../core/viewer_immersive.dart';
import '../../models/media.dart';
import 'image_view.dart';
import 'media_details_page.dart';
import 'live_photo_view.dart';
import 'video_view.dart';
import 'viewer_bottom_controls.dart';
import 'viewer_thumbnail_strip.dart';
import 'viewer_top_bar.dart';

class MediaViewerPage extends StatefulWidget {
  final List<Media> items;
  final int initialIndex;
  final String heroPrefix;

  const MediaViewerPage({
    super.key,
    required this.items,
    required this.initialIndex,
    this.heroPrefix = 'media_',
  });

  static Route<void> route({
    required List<Media> items,
    required int initialIndex,
    String heroPrefix = 'media_',
  }) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) => MediaViewerPage(
        items: items,
        initialIndex: initialIndex,
        heroPrefix: heroPrefix,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: child,
        );
      },
    );
  }

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  late int _index;
  Timer? _hideTimer;
  bool _uiVisible = true;
  bool _playing = false;
  bool _zoomed = false;
  ViewerOrientation _orientation = ViewerOrientation.portrait;
  double _dragOffset = 0;
  bool _downloading = false;
  double? _downloadProgress;

  /// 视频播放时是否已经切到沉浸式（状态栏藏起来）。
  bool _immersive = false;

  Media get _current => widget.items[_index.clamp(0, widget.items.length - 1)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.items.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.items.length - 1).toInt();
    _pageController = PageController(initialPage: _index);
    _applyEntryOrientation();
    // **这里不切系统 UI 模式**：以前进来切 immersiveSticky、dispose 里再切回
    // edgeToEdge。系统栏一藏一露，退出后主界面会整页重排一次（真机上就是
    // 「退出全屏抖一下」，量到的数见 lib/widgets/stable_view_insets.dart）。
    // 满屏靠的是内容自己铺到屏幕边缘：Scaffold 透明 + 黑色底，顶部栏和缩略图条
    // 各自让开安全区，状态栏文字在照片上仍是浅色（见 build 里的 AnnotatedRegion）。
  }

  @override
  void didChangeMetrics() {
    // 系统偶尔会把状态栏重新显示出来（下拉通知栏、切后台再回来、分屏拖拽）：
    // 正在播且当前是沉浸式就再藏一次。不等下一帧，直接发。
    if (_playing && _immersive) {
      unawaited(ViewerImmersive.set(true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _playing) {
      unawaited(ViewerImmersive.set(true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _pageController.dispose();
    _setImmersive(false);
    unawaited(lockAppPortrait());
    super.dispose();
  }

  /// 视频播放时藏起状态栏（沉浸式），暂停/离开时恢复 edgeToEdge。
  ///
  /// 只有播放中才藏：暂停时用户要看时间／进度，状态栏留着更自然。退出浏览页
  /// 一定恢复，不然主界面会一直顶着一条黑边。
  void _setImmersive(bool hidden) {
    if (_immersive == hidden) return;
    _immersive = hidden;
    unawaited(ViewerImmersive.set(hidden));
  }

  /// 从列表点进来时：视频按视频本身的横竖屏，图片固定竖屏。
  void _applyEntryOrientation() {
    if (widget.items.isEmpty) return;
    final media = _current;
    if (media.isVideo) {
      _setOrientation(isLandscapeVideo(media)
          ? ViewerOrientation.landscape
          : ViewerOrientation.portrait);
    } else {
      _setOrientation(ViewerOrientation.portrait);
    }
  }

  void _setOrientation(ViewerOrientation value) {
    _orientation = value;
    if (value == ViewerOrientation.landscape) {
      unawaited(forceLandscape());
    } else {
      unawaited(forcePortrait());
    }
  }

  /// 视频右下角的旋转按钮：在当前方向和反方向之间切换。
  void _toggleOrientation() {
    _setOrientation(_orientation == ViewerOrientation.landscape
        ? ViewerOrientation.portrait
        : ViewerOrientation.landscape);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _uiVisible = false);
    });
  }

  void _onPlayingChanged(bool playing) {
    if (!mounted) return;
    _setImmersive(playing);
    setState(() {
      _playing = playing;
      if (!playing) _uiVisible = true;
    });
    if (playing) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _toggleUi() {
    setState(() => _uiVisible = !_uiVisible);
    if (_uiVisible && _playing) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _userInteraction() {
    if (!_uiVisible) setState(() => _uiVisible = true);
    if (_playing) _scheduleHide();
  }

  void _onPageChanged(int index) {
    _hideTimer?.cancel();
    // 从视频滑到图片：_playing 归零，状态栏要跟回来。
    _setImmersive(false);
    setState(() {
      _index = index;
      _playing = false;
      _uiVisible = true;
      _dragOffset = 0;
      _zoomed = false;
    });
    // 左右滑到视频时保持当前方向；滑到图片恢复竖屏。
    if (!_current.isVideo) {
      _setOrientation(ViewerOrientation.portrait);
    }
  }

  void _onDragUpdate(double delta) {
    if (_current.isVideo || _current.isLivePhoto) return;
    setState(() {
      _dragOffset = (_dragOffset + delta).clamp(0.0, 420.0);
    });
  }

  /// 双指缩放开始时取消可能已经开始的下滑，避免图片跟着跳动。
  void _onDragCancel() {
    if (_dragOffset == 0) return;
    setState(() => _dragOffset = 0);
  }

  void _onDragEnd(double velocity) {
    if (_dragOffset > 120 || velocity > 500) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  void _close() => Navigator.of(context).pop();

  /// 打开当前这张的详情页。
  void _openDetails(Media media) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaDetailsPage(media: media),
      ),
    );
  }

  Future<void> _downloadCurrent() async {
    if (_downloading) return;
    final media = _current;
    setState(() {
      _downloading = true;
      _downloadProgress = null;
    });
    try {
      await MediaDownloadService.save(
        media,
        onProgress: (value) {
          if (mounted) setState(() => _downloadProgress = value);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(media.isVideo ? '视频已保存到相册' : '图片已保存到相册'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message =
          e is MediaDownloadException ? e.message : ApiClient.errorText(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$message')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('没有可查看的媒体', style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    final current = _current;
    // 横屏一套、竖屏一套：缩略图条贴着进度条，间距由控制条几何统一算。
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final backgroundOpacity =
        (1 - _dragOffset / 400).clamp(0.3, 1.0).toDouble();
    final viewer = AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ColoredBox(
          color: Colors.black.withValues(alpha: backgroundOpacity),
          child: Transform.translate(
            offset: Offset(0, _dragOffset),
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pageController,
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: widget.items.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final media = widget.items[index];
                    final active = index == _index;
                    final heroTag = '${widget.heroPrefix}${media.id}';
                    if (media.isLivePhoto) {
                      return LivePhotoView(
                        key: ValueKey('live_${media.id}'),
                        media: media,
                        active: active,
                        heroTag: heroTag,
                        // 播放按钮跟着控制层一起显隐；底部有缩略图条时浮到它上面
                        // （那条 52 高、贴底 12，见 viewer_thumbnail_strip.dart）。
                        uiVisible: _uiVisible,
                        bottomClearance:
                            widget.items.length > 1 ? thumbnailStripHeight + 4 : 0,
                        onPlayingChanged: _onPlayingChanged,
                        onZoomChanged: (zoomed) {
                          if (mounted && zoomed != _zoomed) {
                            setState(() => _zoomed = zoomed);
                          }
                        },
                      );
                    }
                    if (media.isVideo) {
                      return VideoView(
                        key: ValueKey('video_${media.id}'),
                        media: media,
                        active: active,
                        uiVisible: _uiVisible,
                        heroTag: heroTag,
                        onToggleUi: _toggleUi,
                        onUserInteraction: _userInteraction,
                        onPlayingChanged: _onPlayingChanged,
                        onToggleRotation: _toggleOrientation,
                      );
                    }
                    return ImageView(
                      key: ValueKey('image_${media.id}'),
                      media: media,
                      heroTag: heroTag,
                      onTap: _toggleUi,
                      onDragUpdate: _onDragUpdate,
                      onDragEnd: _onDragEnd,
                      onPinchClose: _close,
                      onDragCancel: _onDragCancel,
                      onZoomChanged: (zoomed) {
                        if (mounted && zoomed != _zoomed) {
                          setState(() => _zoomed = zoomed);
                        }
                      },
                    );
                  },
                ),
                // 顶部栏
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: !_uiVisible,
                    child: AnimatedOpacity(
                      opacity: _uiVisible ? 1 : 0,
                      duration: Duration(
                        milliseconds: _uiVisible ? 200 : 300,
                      ),
                      child: ViewerTopBar(
                        key: viewerTopBarKey,
                        media: current,
                        onClose: _close,
                        onDownload: _downloadCurrent,
                        onDetails: () => _openDetails(current),
                      ),
                    ),
                  ),
                ),
                if (widget.items.length > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    // 系统栏留在屏幕上（见上面 build 的注释）：底部那一块安全区
                    // 两种媒体都要让开，否则缩略图条会压在导航手势条底下。
                    bottom: current.isVideo
                        ? viewerThumbnailStripBottom(
                            landscape: landscape,
                            bottomInset: MediaQuery.paddingOf(context).bottom,
                          )
                        : 12 + MediaQuery.paddingOf(context).bottom,
                    child: IgnorePointer(
                      ignoring: !_uiVisible,
                      child: AnimatedOpacity(
                        opacity: _uiVisible ? 1 : 0,
                        duration: Duration(
                          milliseconds: _uiVisible ? 200 : 300,
                        ),
                        child: ViewerThumbnailStrip(
                          items: widget.items,
                          currentIndex: _index,
                          onSelected: (value) {
                            _pageController.animateToPage(
                              value,
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                if (_downloading)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 34 + MediaQuery.paddingOf(context).bottom,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _downloadProgress == null
                              ? '正在保存…'
                              : '正在保存 ${(_downloadProgress! * 100).round()}%',
                          style: AppText.caption.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    // 全屏页自己用平台**原始**的 insets：顶部关闭按钮、视频进度条与缩略图条
    // 一律贴着屏幕边缘，不被主界面那一层钉住的安全区影响（见
    // lib/widgets/stable_view_insets.dart）。两者互不影响。
    return MediaQuery.fromView(view: View.of(context), child: viewer);
  }
}
