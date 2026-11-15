import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/album/feed_gallery_page.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/models/paged.dart';
import 'package:album_app/widgets/album_thumb.dart';
import 'package:album_app/widgets/selection_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media _photo(int id, DateTime takenAt) => Media(
      id: id,
      type: 'image',
      thumbUrl: null,
      url: '',
      width: 1920,
      height: 1080,
      durationMs: null,
      takenAt: takenAt,
      createdAt: takenAt,
      postId: null,
    );

/// 48 张照片、6 个日期分组、每天 8 张（正好两整行）：列表够长（滚得动），
/// 每一行也是满的（能横着划过三格）。
List<Media> _grid() => [
      for (var i = 0; i < 48; i++)
        _photo(1 + i, DateTime(2020, 5, 1 + i ~/ 8, 9, i % 8)),
    ];

Album _album({int mediaCount = 48}) => Album(
      id: 7,
      title: '夏天',
      coverThumb: null,
      mediaCount: mediaCount,
      createdAt: DateTime(2020, 5, 1),
    );

Future<void> _pumpDetail(WidgetTester tester, List<Media> items) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final album = _album(mediaCount: items.length);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: AlbumDetailPage(
        album: album,
        loader: (id) async => AlbumDetail(album: album, items: items),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpFeed(
  WidgetTester tester,
  List<Media> items, {
  void Function(bool selecting, int selected, int total)? onSelectionChanged,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: FeedGalleryPage(
          onSelectionChanged: onSelectionChanged,
          loader: (cursor) async => Paged(
            items: cursor == null ? items : const <Media>[],
            nextCursor: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 屏幕上完整可见的一行里，从左到右连续三格的矩形。
///
/// 拖拽连选靠的是真实几何（命中检测读 render box），所以测试也照真实几何来：
/// 取同一行（top 相同）的三格，坐标才落在同一次水平拖拽上。吸顶区（筛选条 +
/// 日期头）下面的那几行要排掉——手指落在那儿命中的是吸顶条，不是格子。
List<Rect> _firstRowOfThree(WidgetTester tester) {
  final thumbs = find.byType(AlbumThumb);
  final rows = <int, List<Rect>>{};
  for (var i = 0; i < thumbs.evaluate().length; i++) {
    final rect = tester.getRect(thumbs.at(i));
    if (rect.top < 200 || rect.bottom > 800) continue;
    rows.putIfAbsent(rect.top.round(), () => <Rect>[]).add(rect);
  }
  final tops = rows.keys.toList()..sort();
  for (final top in tops) {
    final row = rows[top]!..sort((a, b) => a.left.compareTo(b.left));
    if (row.length >= 3) return row.take(3).toList();
  }
  fail('没有一行能看到连续三格');
}

/// 离屏幕坐标点最近的那一行格子（top 相同的算一行），从左到右排序。
///
/// 长按进入多选时页头会收成工具栏，格子整体挪一下：手指还停在原处，但底下
/// 已经换成另一格（也可能正好落在行距上）。之后要往哪儿拖，得看手指**现在**
/// 离哪一行最近。
List<Rect> _rowNear(WidgetTester tester, Offset point) {
  final thumbs = find.byType(AlbumThumb);
  final rects = <Rect>[];
  for (var i = 0; i < thumbs.evaluate().length; i++) {
    final rect = tester.getRect(thumbs.at(i));
    if (rect.bottom < 0 || rect.top > 844) continue;
    rects.add(rect);
  }
  if (rects.isEmpty) fail('屏幕上没有格子');
  // 每行的 top 都不同，取「行的竖直中心离手指最近」的那一行。
  final rowTop = rects
      .map((rect) => rect.top)
      .reduce((a, b) => (a + 45 - point.dy).abs() <= (b + 45 - point.dy).abs()
          ? a
          : b);
  final row = [
    for (final rect in rects)
      if ((rect.top - rowTop).abs() < 0.5) rect,
  ]..sort((a, b) => a.left.compareTo(b.left));
  return row;
}

/// 这一格里现在有没有选中态：勾选角标画在格子里面。
bool _tileSelected(WidgetTester tester, Rect tile) {
  final checks = find.byIcon(Icons.check);
  for (var i = 0; i < checks.evaluate().length; i++) {
    if (tile.contains(tester.getRect(checks.at(i)).center)) return true;
  }
  return false;
}

int _selectedCount(WidgetTester tester) =>
    find.byIcon(Icons.check).evaluate().length;

/// 一次水平拖拽：在 from 按下，划到 to，松手。
Future<void> _dragAcross(
  WidgetTester tester,
  Offset from,
  Offset to,
) async {
  final gesture = await tester.startGesture(from);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('相册详情页：长按进入多选后不松手继续拖，划过的格子连续选中', (tester) async {
    await _pumpDetail(tester, _grid());
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    final start = _firstRowOfThree(tester).first;
    final finger = start.center;
    final gesture = await tester.startGesture(finger);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget, reason: '长按这一下就进了多选');

    // 手指没抬起来，继续往右划：目标是手指**现在**压着那一行右边的格子
    // （多选态页头收成工具栏，格子整体挪了一下）。
    final targets = [
      for (final rect in _rowNear(tester, finger))
        if (rect.center.dx > finger.dx) rect,
    ];
    expect(targets, isNotEmpty, reason: '手指那一行的右边得还有格子');

    for (final rect in targets) {
      await gesture.moveTo(rect.center);
      await tester.pump();
    }
    for (final rect in targets) {
      expect(
        _tileSelected(tester, rect),
        isTrue,
        reason: '手没松开，划过的格子跟着选中',
      );
    }
    expect(_selectedCount(tester), greaterThanOrEqualTo(2), reason: '一次拖拽选中多个');

    await gesture.up();
    await tester.pumpAndSettle();
    // 松手后选择留在原地：这是真选择，不是拖一下就散的预览。
    expect(_tileSelected(tester, targets.last), isTrue);
    expect(find.byType(SelectionFooter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('相册详情页：多选态直接横划连选，从已选中项起手则反向取消', (tester) async {
    await _pumpDetail(tester, _grid());
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    // 长按一行可见的格子（第一张缩略图可能滚到屏幕外了，命不中）。
    await tester.longPressAt(_firstRowOfThree(tester).first.center);
    await tester.pumpAndSettle();
    // 多选态下先把选择清空：之后每一格的状态都是这次拖拽造成的，数量才对得上。
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);

    final row = _firstRowOfThree(tester);
    // 没经过长按，直接横着划过三格 = 连续选中。
    await _dragAcross(tester, row[0].center, row[2].center);
    expect(_selectedCount(tester), 3, reason: '划过的三格都被选中');
    expect(_tileSelected(tester, row[0]), isTrue);
    expect(_tileSelected(tester, row[2]), isTrue);

    // 从已选中的第一格起手，横着划回来 = 连续取消。
    await _dragAcross(tester, row[0].center, row[2].center);
    expect(_selectedCount(tester), 0, reason: '方向反了就一路取消');
    expect(_tileSelected(tester, row[0]), isFalse);
    expect(find.byType(SelectionFooter), findsNothing);
  });

  testWidgets('相册详情页：多选态竖着拖只滚动列表，不会误选', (tester) async {
    await _pumpDetail(tester, _grid());
    await tester.longPress(find.byType(AlbumThumb).first);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final before = position.pixels;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(before + 100), reason: '列表照样能滚');
    expect(find.text('已选 1 项'), findsOneWidget, reason: '竖向拖拽不选任何东西');
  });

  testWidgets('朋友圈相册：同一个手势实现，长按后接着拖也是连续选中', (tester) async {
    final reports = <List<int>>[];
    final items = _grid();
    await _pumpFeed(
      tester,
      items,
      onSelectionChanged: (selecting, selected, total) =>
          reports.add([selected, total]),
    );

    final row = _firstRowOfThree(tester);
    // 朋友圈相册没有会折叠的页头：多选态不挪格子，按下点一直落在同一格上。
    final gesture = await tester.startGesture(row[0].center);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(reports.last, [1, items.length]);

    await gesture.moveTo(row[1].center);
    await tester.pump();
    await gesture.moveTo(row[2].center);
    await tester.pump();
    expect(reports.last, [3, items.length], reason: '两格一路选上，数量也报给父级');
    await gesture.up();
    await tester.pumpAndSettle();

    // 再从已选中的格子起手拖：反向取消，而不是继续加。
    final back = await tester.startGesture(row[2].center);
    await tester.pump();
    await back.moveTo(row[0].center);
    await tester.pump();
    expect(reports.last, [0, items.length]);
    await back.up();
    await tester.pumpAndSettle();

    // 多选态竖着拖：只滚动，不选。
    await tester.longPress(find.byType(AlbumThumb).first);
    await tester.pumpAndSettle();
    expect(reports.last, [1, items.length]);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final before = position.pixels;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(before + 100));
    expect(reports.last, [1, items.length], reason: '竖向拖拽不选任何东西');
    expect(tester.takeException(), isNull);
  });

  testWidgets('多选态单击照旧：点一下只翻一格', (tester) async {
    await _pumpDetail(tester, _grid());
    await tester.longPress(find.byType(AlbumThumb).first);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.byType(AlbumThumb).at(1));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.byType(AlbumThumb).at(1));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
  });
}
