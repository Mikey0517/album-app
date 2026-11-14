import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_tab_page.dart';
import 'package:album_app/widgets/app_category_menu.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const AlbumTabPage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 子页有加载动画，pumpAndSettle 会被转圈卡住，弹层用定长 pump 推开/收起。
  Future<void> pumpMenu(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder menuItem(String label) =>
      find.widgetWithText(PopupMenuItem<int>, label);

  testWidgets('分类用标题 + caret 表达，默认家庭相册，顶部没有 46 高的分段条',
      (tester) async {
    await pumpTab(tester);

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    // 原来那种 AppBar.bottom 分段条带子必须消失：顶部只留一行标题。
    expect(appBar.bottom, isNull);
    expect(find.byType(AppSegmentedBar), findsNothing);
    expect(find.byType(AppSegmentedBarSurface), findsNothing);
    expect(appBar.toolbarHeight, 48, reason: '紧凑高度，比原来 56 + 46 矮一截');
    expect(appBar.preferredSize.height, 48);
    expect(appBar.title, isA<AppCategoryMenu>());

    // 标题 = 当前分类名 + caret。
    expect(find.text('家庭相册'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    expect(
      tester.widget<AppCategoryMenu>(find.byType(AppCategoryMenu)).selectedIndex,
      1,
      reason: '默认打开家庭相册',
    );

    // 三分类仍在，只是搬进下拉菜单里。
    await tester.tap(find.byType(AppCategoryMenu));
    await pumpMenu(tester);
    expect(menuItem('朋友圈相册'), findsOneWidget);
    expect(menuItem('家庭相册'), findsOneWidget);
    expect(menuItem('私人相册'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('点标题开菜单能切分类，标题与内容跟着走', (tester) async {
    await pumpTab(tester);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);

    await tester.tap(find.byType(AppCategoryMenu));
    await pumpMenu(tester);
    await tester.tap(menuItem('私人相册'));
    await pumpMenu(tester);

    expect(find.text('私人相册'), findsOneWidget, reason: '标题跟随当前分类');
    expect(
      tester.widget<AppCategoryMenu>(find.byType(AppCategoryMenu)).selectedIndex,
      2,
    );
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横向滑动切换分类，标题与下拉状态双向同步', (tester) async {
    await pumpTab(tester);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);

    // 左滑到下一个分类：标题、下拉、内容索引三者一致。
    await tester.fling(find.byType(IndexedStack), const Offset(-300, 0), 1000);
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);
    expect(
      tester.widget<AppCategoryMenu>(find.byType(AppCategoryMenu)).selectedIndex,
      2,
    );
    expect(find.text('私人相册'), findsOneWidget);

    // 右滑回上一个：状态同样跟着回退，页面仍是同一棵 IndexedStack（不重建）。
    await tester.fling(find.byType(IndexedStack), const Offset(300, 0), 1000);
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    expect(find.text('家庭相册'), findsOneWidget);
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).children.length,
      3,
    );
    expect(tester.takeException(), isNull);
  });
}
