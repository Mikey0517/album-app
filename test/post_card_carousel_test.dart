import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/models/post.dart';
import 'package:album_app/widgets/album_thumb.dart';
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

  /// 卡片内容区（玻璃内的那一列）：大图必须和它一样宽。
  Rect contentRect(WidgetTester tester) => tester.getRect(
        find
            .descendant(
              of: find.byType(PostCard),
              matching: find.byType(Column),
            )
            .first,
      );

  testWidgets('单图：占满卡片宽度，按 16:9 出图，不套轮播也没有页码', (tester) async {
    await pump(tester, _post([_photo(1)]));

    final thumb = tester.getRect(find.byType(AlbumThumb));
    final content = contentRect(tester);
    expect(thumb.width, content.width, reason: '一张图占满宽度');
    expect(thumb.width, 326, reason: '390 - 卡片外边距 16×2 - 卡片内边距 16×2');
    expect(thumb.height, closeTo(326 * 9 / 16, 0.5), reason: '16:9 的图按比例出高度');
    expect(find.byType(PageView), findsNothing, reason: '一张图不该套轮播');
    expect(find.text('1/1'), findsNothing, reason: '只有一张时不显示页码');
  });

  testWidgets('长图/全景图被收在 4:5 ~ 1.91:1 之间', (tester) async {
    await pump(tester, _post([_photo(1, width: 1080, height: 2400)]));
    final tall = tester.getRect(find.byType(AlbumThumb));
    expect(tall.height, closeTo(tall.width * 5 / 4, 0.5), reason: '长截图收在 4:5');

    await pump(tester, _post([_photo(1, width: 4000, height: 800)]));
    final wide = tester.getRect(find.byType(AlbumThumb));
    expect(wide.height, closeTo(wide.width / 1.91, 0.5), reason: '全景图收在 1.91:1');
  });

  testWidgets('多图：一次一张、左右滑动切换，页码在右上角', (tester) async {
    await pump(tester, _post([_photo(1), _photo(2), _photo(3)]));

    final content = contentRect(tester);
    final carousel = tester.getRect(find.byType(PageView));
    expect(carousel.width, content.width);
    // 一次只建一页：相邻的照片在屏外，没滑过去就不建，也就不会同时露出两张。
    expect(
      find.descendant(
        of: find.byType(PageView),
        matching: find.byType(AlbumThumb),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byType(AlbumThumb)),
      carousel,
      reason: '当前这一张正好铺满轮播区',
    );

    expect(find.text('1/3'), findsOneWidget);
    final counter = tester.getRect(find.text('1/3'));
    expect(counter.right, closeTo(carousel.right - 10 - 8, 0.5));
    expect(counter.top, closeTo(carousel.top + 10 + 3, 0.5));

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget, reason: '滑一张页码跟着变');
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);
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
}
