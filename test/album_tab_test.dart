import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_tab_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('相册页有三个 tab，默认停在家庭相册且不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey<AlbumTabPageState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AlbumTabPage(key: key),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('朋友圈相册'), findsOneWidget);
    expect(find.text('家庭相册'), findsOneWidget);
    expect(find.text('私人相册'), findsOneWidget);

    final segmented = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    expect(segmented.selected, {1}, reason: '默认打开家庭相册');
    expect(tester.takeException(), isNull);
  });
}
