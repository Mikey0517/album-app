import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/widgets/app_category_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpMenuHost(
    WidgetTester tester, {
    required List<AppCategoryItem> items,
    int selected = 0,
    ValueChanged<int>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          appBar: AppBar(
            title: AppCategoryMenu(
              items: items,
              selectedIndex: selected,
              onChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('标题是当前分类 + caret，菜单项是分类名 + 数量', (tester) async {
    final picked = <int>[];
    await pumpMenuHost(
      tester,
      items: const [
        AppCategoryItem('朋友圈相册', count: 3),
        AppCategoryItem('家庭相册', count: 12000),
        AppCategoryItem('私人相册'),
      ],
      onChanged: picked.add,
    );

    expect(find.text('朋友圈相册'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    expect(picked, isEmpty);

    await tester.tap(find.byType(AppCategoryMenu));
    await tester.pumpAndSettle();

    // 每个分类一行：名称在左，数量靠右；数量没加载完就不摆数字。
    expect(find.byType(PopupMenuItem<int>), findsNWidgets(3));
    expect(find.text('家庭相册'), findsOneWidget);
    expect(find.text('私人相册'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1.2 万'), findsOneWidget);
    expect(find.text('0'), findsNothing);

    // 数量靠右对齐：不同宽度分类名下，数字的右边缘在同一条线上。
    expect(
      tester.getRect(find.text('3')).right,
      closeTo(tester.getRect(find.text('1.2 万')).right, 0.5),
    );

    await tester.tap(find.text('私人相册'));
    await tester.pumpAndSettle();
    expect(picked, [2]);
  });

  testWidgets('点标题弹出菜单，选当前分类也照常回报下标', (tester) async {
    final picked = <int>[];
    await pumpMenuHost(
      tester,
      items: const [AppCategoryItem('家庭相册', count: 4)],
      onChanged: picked.add,
    );

    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<int>), findsOneWidget);

    await tester.tap(find.text('家庭相册').last);
    await tester.pumpAndSettle();
    expect(picked, [0]);
    // 菜单底色统一走主题，不额外铺第二层。
    expect(find.byType(AppCategoryMenu), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(AppCategoryMenu))).popupMenuTheme.color,
      AppColors.bgSurface,
    );
  });
}
