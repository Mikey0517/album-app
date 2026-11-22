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
      expect(find.byType(PostMediaCounter), findsNothing);

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
      expect(thumb.fit, BoxFit.contain, reason: '整张图放进来，剩下的是黑边');
      expect(thumb.backgroundColor, Colors.black);

      final rect = tester.getRect(find.byType(AlbumThumb));
      expect(rect.width, 390, reason: '铺满屏宽');
      expect(rect.left, 0);
      expect(rect.height, closeTo(390 * 9 / 16, 0.5), reason: '16:9 按自己的比例出高度');
    });

    testWidgets('超高竖图按屏高收口：舞台固定高度，整张图居中不裁边', (tester) async {
      await pump(tester, _post([_photo(1, width: 1080, height: 2400)]),
          widescreen: true);

      const maxHeight = 844 * kFeedWideMaxHeightFactor;
      final rect = tester.getRect(find.byType(AlbumThumb));
      expect(rect.width, 390, reason: '舞台铺满屏宽');
      expect(rect.height, closeTo(maxHeight, 0.5), reason: '高度不超过屏高的 72%');
      expect(
        tester.widget<AlbumThumb>(find.byType(AlbumThumb)).fit,
        BoxFit.contain,
        reason: '超出部分不裁，缩窄居中、左右留黑边',
      );
    });

    testWidgets('宽图仍然铺满屏宽、不无谓放大', (tester) async {
      await pump(tester, _post([_photo(1, width: 4000, height: 800)]),
          widescreen: true);
      final rect = tester.getRect(find.byType(AlbumThumb));
      expect(rect.width, 390);
      expect(rect.height, closeTo(390 / 5, 0.5), reason: '4000:800 = 5:1');
    });

    testWidgets('多图高度取最高的那张：滑到别的照片画幅也不跳', (tester) async {
      // 3:4 = 520 高，16:9 = 219.4 高：舞台按 520 算。
      await pump(
        tester,
        _post([
          _photo(1),
          _photo(2, width: 1080, height: 1440),
        ]),
        widescreen: true,
      );

      final first = tester.getRect(find.byType(PageView));
      expect(first.height, closeTo(520, 0.5), reason: '取最高那张的高度');
      expect(first.width, 390);

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PageView)).height, closeTo(520, 0.5),
          reason: '换到 16:9 那页，舞台高度不变');
    });

    testWidgets('多图右上角是「第几张/共几张」，贴着舞台右上角', (tester) async {
      await pump(
        tester,
        _post([_photo(1), _photo(2), _photo(3)]),
        widescreen: true,
      );

      final counter = find.byKey(postMediaCounterKey);
      expect(counter, findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);

      final stage = tester.getRect(find.byType(PageView));
      final rect = tester.getRect(counter);
      expect(rect.right, closeTo(stage.right - 8, 0.5), reason: '贴右上角');
      expect(rect.top, closeTo(stage.top + 8, 0.5));

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget, reason: '滑一张页码跟着走');
    });

    testWidgets('单张不显示页码', (tester) async {
      await pump(tester, _post([_photo(1)]), widescreen: true);
      expect(find.byKey(postMediaCounterKey), findsNothing);
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

  group('舞台尺寸', () {
    test('高度取最高的一张，但不超过上限', () {
      expect(
        feedWideStageHeight([_photo(1)], 390, 600),
        closeTo(219.375, 0.01),
        reason: '单张就是它自己的高度',
      );
      expect(
        feedWideStageHeight([_photo(1, width: 1080, height: 2400)], 390, 600),
        600,
        reason: '超过上限就截到上限',
      );
      expect(
        feedWideStageHeight(
          [
            _photo(1),
            _photo(2, width: 1080, height: 1440),
          ],
          390,
          600,
        ),
        closeTo(520, 0.01),
        reason: '多张取最高的那张',
      );
      expect(feedWideStageHeight([], 390, 600), 0, reason: '没有媒体就没有舞台');
    });
  });
}
