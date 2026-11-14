import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_tab_page.dart';
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

  testWidgets('相册页有三个 tab，默认停在家庭相册且不溢出', (tester) async {
    await pumpTab(tester);

    expect(find.text('朋友圈相册'), findsOneWidget);
    expect(find.text('家庭相册'), findsOneWidget);
    expect(find.text('私人相册'), findsOneWidget);

    // tab 条与相册详情页的筛选条是同一个分段组件。
    final bar = tester.widget<AppSegmentedBar>(find.byType(AppSegmentedBar));
    expect(bar.items.map((item) => item.label).toList(),
        ['朋友圈相册', '家庭相册', '私人相册']);
    expect(bar.selectedIndex, 1, reason: '默认打开家庭相册');
    expect(tester.takeException(), isNull);
  });

  testWidgets('点 tab 或横向滑动都能切换，内容不重建', (tester) async {
    await pumpTab(tester);
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 1);

    await tester.tap(find.text('私人相册'));
    await tester.pump();
    expect(
      tester.widget<AppSegmentedBar>(find.byType(AppSegmentedBar)).selectedIndex,
      2,
    );

    // 右滑回到上一个 tab（不再重建整棵树，IndexedStack 保留各页状态）。
    await tester.fling(find.byType(IndexedStack), const Offset(300, 0), 1000);
    await tester.pump();
    expect(
      tester.widget<AppSegmentedBar>(find.byType(AppSegmentedBar)).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });
}
