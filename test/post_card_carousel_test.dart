import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/feed_view_settings.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/models/post.dart';
import 'package:album_app/widgets/album_thumb.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Media _photo(int id, {int width = 1920, int height = 1080}) => Media(
      id: id,
      type: 'image',
      // 两个地址都给：九宫格走 400px 缩略图，大屏要走 /files/display 原图。
      thumbUrl: '/files/thumb_$id.jpg',
      url: '/files/$id.jpg',
      width: width,
      height: height,
      durationMs: null,
      takenAt: DateTime(2024, 8, 1),
      createdAt: DateTime(2024, 8, 1),
      postId: 7,
    );

Post _post(List<Media> medias, {String? content = '今天的晚饭'}) => Post(
      id: 7,
      authorId: 1,
      authorNickname: 'Mikey',
      content: content,
      postedAt: DateTime(2024, 8, 1),
      medias: medias,
    );

void main() {
  setUp(() => FeedViewSettings.widescreen.value = false);
  tearDown(() => FeedViewSettings.widescreen.value = false);

  Future<void> pump(
    WidgetTester tester,
    Post post, {
    bool widescreen = false,
    void Function(List<Media>, int)? onOpen,
  }) async {
    FeedViewSettings.widescreen.value = widescreen;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              PostCard(
                post: post,
                onOpenMedia: onOpen ?? (_, __) {},
                onDeleted: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('默认（大屏关闭）：九宫格', () {
    testWidgets('套卡片、格子铺满卡片内容宽度，图片走缩略图', (tester) async {
      await pump(tester, _post([
        _photo(1),
        _photo(2),
        _photo(3),
      ]));

      expect(find.byType(AppGlassSurface), findsOneWidget, reason: '九宫格在卡片里');
      expect(find.byType(PageView), findsNothing);
      expect(find.byType(PostPageDots), findsNothing);

      final tiles = tester.widgetList<AlbumThumb>(find.byType(AlbumThumb));
      expect(tiles, hasLength(3));
      for (final tile in tiles) {
        expect(tile.imagePath, isNull, reason: '九宫格用缩略图，不拉原图');
      }
      final first = tester.getRect(find.byType(AlbumThumb).at(0));
      expect(first.width, closeTo((326 - 8) / 3, 0.5), reason: '卡片内容宽 326 三列');
      expect(first.left, closeTo(32, 0.5), reason: '卡片内边距 16 + 玻璃内边距 16');
    });

    testWidgets('没有右上角模式切换按钮（开关已经挪到「我的」）', (tester) async {
      await pump(tester, _post([_photo(1), _photo(2), _photo(3)]));
      expect(find.byTooltip('切换大图'), findsNothing);
      expect(find.byTooltip('切换九宫格'), findsNothing);
      expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
      expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
    });

    testWidgets('点格子打开查看器，索引是格子自己的', (tester) async {
      final opened = <int>[];
      await pump(
        tester,
        _post([_photo(1), _photo(2), _photo(3)]),
        onOpen: (_, index) => opened.add(index),
      );
      await tester.tap(find.byType(AlbumThumb).at(2));
      await tester.pumpAndSettle();
      expect(opened, [2]);
    });
  });

  group('大屏模式', () {
    testWidgets('不套卡片、一张铺满屏宽，图片换成 /files/display 原图', (tester) async {
      await pump(tester, _post([_photo(1)]), widescreen: true);

      expect(find.byType(AppGlassSurface), findsNothing, reason: '大屏不套卡片');
      final thumb = tester.widget<AlbumThumb>(find.byType(AlbumThumb));
      expect(thumb.imagePath, '/files/display/1.jpg',
          reason: '大屏要最清晰的：走 2560px 原图，不再是 400px 缩略图');

      final rect = tester.getRect(find.byType(AlbumThumb));
      expect(rect.width, 390, reason: '铺满屏宽');
      expect(rect.left, 0);
      expect(rect.height, closeTo(390 * 9 / 16, 0.5), reason: '16:9 按自己的比例出高度');
    });

    testWidgets('超高竖图按屏高收口，整张图完整露出（不裁边）', (tester) async {
      await pump(tester, _post([_photo(1, width: 1080, height: 2400)]),
          widescreen: true);

      const maxHeight = 844 * kFeedWideMaxHeightFactor;
      final rect = tester.getRect(find.byType(AlbumThumb));
      expect(rect.height, closeTo(maxHeight, 0.5), reason: '高度不超过屏高的 72%');
      expect(rect.width, closeTo(maxHeight * 1080 / 2400, 0.5),
          reason: '宽度按原比例收窄，整张图都在，没有被裁');
      expect(rect.center.dx, closeTo(195, 0.5), reason: '收窄后居中');
    });

    testWidgets('宽图仍然铺满屏宽、不无谓放大', (tester) async {
      await pump(tester, _post([_photo(1, width: 4000, height: 800)]),
          widescreen: true);
      final rect = tester.getRect(find.byType(AlbumThumb));
      expect(rect.width, 390);
      expect(rect.height, closeTo(390 / 5, 0.5), reason: '4000:800 = 5:1');
    });

    testWidgets('多图：一次一张，页码是底部居中的小圆点', (tester) async {
      await pump(
        tester,
        _post([_photo(1), _photo(2), _photo(3)]),
        widescreen: true,
      );

      final carousel = tester.getRect(find.byType(PageView));
      expect(carousel.width, 390);
      expect(
        find.descendant(
          of: find.byType(PageView),
          matching: find.byType(AlbumThumb),
        ),
        findsOneWidget,
        reason: '一次只建一页，不会同时露出两张',
      );

      final dots = find.byType(PostPageDots);
      expect(dots, findsOneWidget);
      expect(tester.widget<PostPageDots>(dots).count, 3);
      expect(tester.widget<PostPageDots>(dots).index, 0);
      final dotsRect = tester.getRect(dots);
      expect(dotsRect.center.dx, closeTo(carousel.center.dx, 1),
          reason: '圆点在底部居中');
      expect(dotsRect.bottom, closeTo(carousel.bottom - 10, 0.5),
          reason: '贴着图片底边 10');

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<PostPageDots>(find.byType(PostPageDots)).index, 1,
          reason: '滑一张圆点跟着走');
    });

    testWidgets('点当前这一张打开查看器，索引跟着滑动走', (tester) async {
      final opened = <int>[];
      List<Media>? openedList;
      await pump(
        tester,
        _post([_photo(1), _photo(2)]),
        widescreen: true,
        onOpen: (medias, index) {
          openedList = medias;
          opened.add(index);
        },
      );

      await tester.tapAt(tester.getRect(find.byType(PageView)).center);
      await tester.pumpAndSettle();
      expect(opened, [0]);
      expect(openedList!.map((m) => m.id), [1, 2]);

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getRect(find.byType(PageView)).center);
      await tester.pumpAndSettle();
      expect(opened, [0, 1], reason: '滑到第二张再点，打开的是第二张');
    });

    testWidgets('开关切回来，同一条动态立刻变回九宫格', (tester) async {
      await pump(tester, _post([_photo(1), _photo(2)]), widescreen: true);
      expect(find.byType(PageView), findsOneWidget);

      FeedViewSettings.widescreen.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsNothing);
      expect(find.byType(AppGlassSurface), findsOneWidget);

      FeedViewSettings.widescreen.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('没有媒体的动态在大屏模式下仍然是卡片', (tester) async {
      await pump(tester, _post(const [], content: '只有文字'), widescreen: true);
      expect(find.byType(AppGlassSurface), findsOneWidget);
      expect(find.byType(AlbumThumb), findsNothing);
    });
  });

  group('尺寸计算', () {
    test('大屏尺寸保持原比例，超过高度上限就缩窄', () {
      final tall = feedWideMediaSize(_photo(1, width: 1080, height: 2400), 390, 600);
      expect(tall.height, 600);
      expect(tall.width, closeTo(270, 0.01));

      final wide = feedWideMediaSize(_photo(1, width: 1920, height: 1080), 390, 600);
      expect(wide.width, 390);
      expect(wide.height, closeTo(219.375, 0.01));
    });
  });
}
