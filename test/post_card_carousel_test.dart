import 'package:album_app/core/design/theme.dart';
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
      thumbUrl: null,
      url: 'https://example.test/$id.jpg',
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
  Future<void> pump(
    WidgetTester tester,
    Post post, {
    void Function(List<Media>, int)? onOpen,
  }) async {
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

  testWidgets('大图：不套卡片、没有边框，一张图铺满屏宽', (tester) async {
    await pump(tester, _post([_photo(1)]));

    expect(find.byType(AppGlassSurface), findsNothing,
        reason: '大图模式不套卡片');
    final thumb = tester.getRect(find.byType(AlbumThumb));
    expect(thumb.width, 390, reason: '铺满屏宽（没有卡片内边距）');
    expect(thumb.left, 0);
    expect(thumb.height, closeTo(390 * 9 / 16, 0.5), reason: '16:9 按比例出高度');
    expect(find.byType(PostPageDots), findsNothing, reason: '只有一张没有圆点');
  });

  testWidgets('长图/全景图被收在 4:5 ~ 1.91:1 之间', (tester) async {
    await pump(tester, _post([_photo(1, width: 1080, height: 2400)]));
    final tall = tester.getRect(find.byType(AlbumThumb));
    expect(tall.height, closeTo(tall.width * 5 / 4, 0.5), reason: '长截图收在 4:5');

    await pump(tester, _post([_photo(1, width: 4000, height: 800)]));
    final wide = tester.getRect(find.byType(AlbumThumb));
    expect(wide.height, closeTo(wide.width / 1.91, 0.5), reason: '全景图收在 1.91:1');
  });

  testWidgets('多图：一次一张，页码是底部居中的小圆点', (tester) async {
    await pump(tester, _post([_photo(1), _photo(2), _photo(3)]));

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
        reason: '圆点在底部居中，不在右上角');
    expect(dotsRect.bottom, closeTo(carousel.bottom - 10, 0.5),
        reason: '贴着图片底边 10');
    expect(find.text('1/3'), findsNothing, reason: '不再是 1/3 那种页码');

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<PostPageDots>(find.byType(PostPageDots)).index, 1,
        reason: '滑一张圆点跟着走');
  });

  testWidgets('右上角是模式切换图标：大图 ↔ 九宫格', (tester) async {
    await pump(tester, _post([_photo(1), _photo(2), _photo(3)]));

    final toggle = find.byKey(postMediaModeToggleKey);
    expect(toggle, findsOneWidget, reason: '右上角那枚切换图标必须画出来');
    final media = tester.getRect(find.byType(PageView));
    final rect = tester.getRect(toggle);
    expect(rect.right, closeTo(media.right - 8, 0.5), reason: '贴右上角');
    expect(rect.top, closeTo(media.top + 8, 0.5));
    expect(
      find.descendant(of: toggle, matching: find.byIcon(Icons.grid_view_rounded)),
      findsOneWidget,
      reason: '大图状态下图标表示「切成九宫格」',
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // 九宫格：卡片回来了，三张图一次全露出来。
    expect(find.byType(AppGlassSurface), findsOneWidget, reason: '九宫格仍然在卡片里');
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(PostPageDots), findsNothing);
    final tiles = tester.widgetList<AlbumThumb>(find.byType(AlbumThumb));
    expect(tiles, hasLength(3));
    final first = tester.getRect(find.byType(AlbumThumb).at(0));
    expect(first.width, closeTo((326 - 8) / 3, 0.5), reason: '卡片内容宽度 326 三列');
    expect(
      find.descendant(
        of: find.byKey(postMediaModeToggleKey),
        matching: find.byIcon(Icons.fullscreen_rounded),
      ),
      findsOneWidget,
      reason: '九宫格状态下图标表示「切成大图」',
    );

    await tester.tap(find.byKey(postMediaModeToggleKey));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget, reason: '点回去又是大图');
    expect(find.byType(AppGlassSurface), findsNothing);
  });

  testWidgets('文字在图片下面（Instagram 那样先图后文）', (tester) async {
    await pump(tester, _post([_photo(1)], content: '今天的晚饭'));
    final image = tester.getRect(find.byType(AlbumThumb));
    final text = tester.getRect(find.text('今天的晚饭'));
    expect(text.top, greaterThan(image.bottom), reason: '文字在图下面');
  });

  testWidgets('点当前这一张打开查看器，索引跟着滑动走', (tester) async {
    final opened = <int>[];
    List<Media>? openedList;
    await pump(
      tester,
      _post([_photo(1), _photo(2)]),
      onOpen: (medias, index) {
        openedList = medias;
        opened.add(index);
      },
    );

    final carousel = tester.getRect(find.byType(PageView));
    await tester.tapAt(carousel.center);
    await tester.pumpAndSettle();
    expect(opened, [0]);
    expect(openedList!.map((m) => m.id), [1, 2]);

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(carousel.center);
    await tester.pumpAndSettle();
    expect(opened, [0, 1], reason: '滑到第二张再点，打开的是第二张');
  });

  testWidgets('九宫格模式点格子也打开查看器，索引是格子自己的', (tester) async {
    final opened = <int>[];
    await pump(
      tester,
      _post([_photo(1), _photo(2), _photo(3)]),
      onOpen: (_, index) => opened.add(index),
    );
    await tester.tap(find.byKey(postMediaModeToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AlbumThumb).at(2));
    await tester.pumpAndSettle();
    expect(opened, [2]);
  });
}
