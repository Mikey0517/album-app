import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/album_detail_page.dart';
import 'package:album_app/features/album/album_media_filter.dart';
import 'package:album_app/features/album/album_media_filter_bar.dart';
import 'package:album_app/features/album/album_timeline_layout.dart';
import 'package:album_app/features/album/photo_timeline_scrubber.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/widgets/app_bottom_tab_bar.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:album_app/widgets/app_segmented_bar.dart';
import 'package:album_app/widgets/selection_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer;
import 'package:shared_preferences/shared_preferences.dart';

// 三处「换玻璃」的控件：多选底栏、上传按钮、分类条。
//
// 它们和底部 footer 是**同一块材质**：同一个 [AppGlassSurface]、同一套档位与
// 光学参数（premium，28 / 1.38 / 0.10 / 3）、同样的 scrim 分支；几何上一律是
// 圆角 = 高度/2 的 pill。这里守四件事：
//   1. 多选底栏是浮动胶囊：左右 18、底部离安全区 8、四个操作等宽；
//   2. 上传按钮是 pill 玻璃，且整枚让开右侧 30 宽的时间轴轨道（矩形不相交）；
//   3. 分类条整条一枚胶囊，选中段只换文字颜色、**不加填充块**；
//   4. minimal / 无档位时三处都退成同形状的不透明表面（bgSurface + 1px 边），
//      不跳版、不白屏。

Media _media(
  int id, {
  bool video = false,
  bool live = false,
  int day = 1,
}) =>
    Media(
      id: id,
      type: video ? 'video' : 'image',
      thumbUrl: null,
      url: '',
      width: 1920,
      height: 1080,
      durationMs: video ? 62000 : null,
      takenAt: DateTime(2024, 5, day, 9, id % 60),
      createdAt: DateTime(2024, 5, day, 9, id % 60),
      postId: null,
      liveVideoUrl: live ? 'https://example.com/live/$id.mp4' : null,
    );

/// 三档玻璃都从 [AppGlassScope] 注入：测试不依赖跑测试那台机器的 shader 能力。
Widget _host(Widget child, {GlassQuality? quality = GlassQuality.premium}) {
  final app = MaterialApp(theme: buildAppTheme(), home: child);
  if (quality == null) return app;
  return AppGlassScope(quality: quality, child: app);
}

void _phone(WidgetTester tester, {double safeBottom = 0}) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = FakeViewPadding(bottom: safeBottom);
  tester.view.viewPadding = FakeViewPadding(bottom: safeBottom);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

/// 某个控件里第一层装饰（不透明退化分支就是这一层）。
BoxDecoration _firstDecorationUnder(WidgetTester tester, Finder frame) {
  final decorated = tester.widgetList<DecoratedBox>(
    find.descendant(of: frame, matching: find.byType(DecoratedBox)),
  );
  return decorated.first.decoration as BoxDecoration;
}

/// 四段都在、且每段只有一个玻璃表面的多选底栏。
List<SelectionFooterAction> _fourActions({VoidCallback? onTap}) => [
      SelectionFooterAction(
        icon: Icons.download_outlined,
        label: '下载',
        onTap: onTap ?? () {},
      ),
      SelectionFooterAction(
        icon: Icons.drive_file_move_outline,
        label: '移动',
        onTap: onTap ?? () {},
      ),
      SelectionFooterAction(
        icon: Icons.delete_outline,
        label: '删除',
        danger: true,
        onTap: onTap ?? () {},
      ),
      SelectionFooterAction(
        icon: Icons.ios_share,
        label: '分享',
        onTap: onTap ?? () {},
      ),
    ];

Media _albumMedia(int index) =>
    _media(index + 1, day: 1 + (index ~/ 10));

Future<void> _pumpAlbum(
  WidgetTester tester, {
  int count = 30,
  GlassQuality? quality = GlassQuality.premium,
}) async {
  _phone(tester);
  final items = [for (var i = 0; i < count; i++) _albumMedia(i)];
  final album = Album(
    id: 7,
    title: '夏天',
    coverThumb: null,
    mediaCount: items.length,
    createdAt: DateTime(2020, 5, 1),
  );
  await tester.pumpWidget(
    _host(
      AlbumDetailPage(
        album: album,
        loader: (id) async => AlbumDetail(album: album, items: items),
      ),
      quality: quality,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('多选底栏：与 footer 同款的浮动胶囊玻璃', () {
    testWidgets('几何 / 档位 / scrim 全部取自 footer 那一份，四个操作等宽', (tester) async {
      _phone(tester, safeBottom: 34);
      final tapped = <String>[];
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: SelectionFooter(
              safeArea: true,
              actions: [
                SelectionFooterAction(
                  icon: Icons.download_outlined,
                  label: '下载',
                  onTap: () => tapped.add('下载'),
                ),
                SelectionFooterAction(
                  icon: Icons.drive_file_move_outline,
                  label: '移动',
                  onTap: () => tapped.add('移动'),
                ),
                SelectionFooterAction(
                  icon: Icons.delete_outline,
                  label: '删除',
                  danger: true,
                  onTap: () => tapped.add('删除'),
                ),
                SelectionFooterAction(
                  icon: Icons.ios_share,
                  label: '分享',
                  onTap: () => tapped.add('分享'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // 参数只有一个来源：footer 的常量。这边改一个数，那边跟着走。
      expect(SelectionFooter.barHeight, AppBottomTabBar.barHeight);
      expect(SelectionFooter.sideInset, AppBottomTabBar.sideInset);
      expect(SelectionFooter.bottomGap, AppBottomTabBar.bottomGap);
      expect(SelectionFooter.radius, SelectionFooter.barHeight / 2);

      final surface =
          tester.widget<AppGlassSurface>(find.byType(AppGlassSurface));
      expect(surface.requestedQuality, AppBottomTabBar.preferredQuality);
      expect(surface.preferPremium, isTrue, reason: '静态 chrome 优先 premium');
      expect(surface.useOwnLayer, AppBottomTabBar.usesOwnLayer);
      expect(surface.scrim, isTrue, reason: '玻璃后面是滚动的照片，文字要有底衬');
      expect(surface.radius, SelectionFooter.barHeight / 2);
      // 真的在建玻璃：整条胶囊一块 GlassContainer，不是每一格各一块。
      expect(find.byType(GlassContainer), findsOneWidget);

      final barRect = tester.getRect(find.byType(SelectionFooter));
      final pillRect = tester.getRect(find.byType(AppGlassSurface));
      // 浮动胶囊：高度 = footer 的 56，左右各 18，底部离安全区再留 8。
      expect(pillRect.height, SelectionFooter.barHeight);
      expect(pillRect.left - barRect.left, SelectionFooter.sideInset);
      expect(barRect.right - pillRect.right, SelectionFooter.sideInset);
      expect(
        barRect.bottom - pillRect.bottom,
        SelectionFooter.bottomGap + 34,
        reason: '安全区自身不算在胶囊里',
      );

      // 四个操作等宽。
      final widths = [
        for (var i = 0; i < 4; i++)
          tester.getSize(find.byKey(SelectionFooter.actionKey(i))).width,
      ];
      expect(widths, hasLength(4));
      for (final width in widths) {
        expect(width, closeTo(pillRect.width / 4, 0.01));
      }

      // 图标 + 文字都在，且危险动作使用现有语义色。
      for (final label in ['下载', '移动', '删除', '分享']) {
        expect(
          find.descendant(
            of: find.byType(AppGlassSurface),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      expect(
        tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color,
        AppColors.danger,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.download_outlined)).color,
        appTabBarInactiveColor,
        reason: '普通操作与底部 tab 的未选中态同一档灰',
      );

      // 点得动（无涟漪，但命中区还在）。
      await tester.tap(find.text('分享'));
      await tester.pump();
      expect(tapped, ['分享']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('禁用的操作退成 textTertiary，仍然占一格', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: SelectionFooter(
              actions: [
                SelectionFooterAction(
                  icon: Icons.download_outlined,
                  label: '下载',
                  onTap: () {},
                ),
                const SelectionFooterAction(
                  icon: Icons.ios_share,
                  label: '分享',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final pillRect = tester.getRect(find.byType(AppGlassSurface));
      expect(
        tester.getSize(find.byKey(SelectionFooter.actionKey(1))).width,
        closeTo(pillRect.width / 2, 0.01),
        reason: '两格的时候一样等宽',
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.ios_share)).color,
        AppColors.textTertiary,
      );
    });

    testWidgets('minimal 档：退成同形状的不透明胶囊（bgSurface + 1px 边）', (tester) async {
      _phone(tester, safeBottom: 34);
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: SelectionFooter(
              safeArea: true,
              actions: _fourActions(),
            ),
          ),
          quality: GlassQuality.minimal,
        ),
      );
      await tester.pump();

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing, reason: 'minimal 不加模糊');
      expect(find.byKey(AppGlassSurface.strokeKey), findsNothing);
      expect(find.byKey(AppGlassSurface.highlightKey), findsNothing);

      final pillRect = tester.getRect(find.byType(AppGlassSurface));
      expect(pillRect.height, SelectionFooter.barHeight, reason: '布局不跳版');
      final decoration = _firstDecorationUnder(tester, find.byType(SelectionFooter));
      expect(decoration.color, AppColors.bgSurface);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(SelectionFooter.radius),
        reason: '退化也是同一枚胶囊，不退回通栏',
      );
      final border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.left.width, 1);
      expect(border.top.color, AppColors.divider);
      // 四个操作还在。
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(SelectionFooter.actionKey(i)), findsOneWidget);
      }
      expect(find.text('删除'), findsOneWidget);
    });

    testWidgets('没有任何档位来源时同样是不透明胶囊', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: SelectionFooter(actions: _fourActions()),
          ),
          quality: null,
        ),
      );
      await tester.pump();

      expect(find.byType(GlassContainer), findsNothing);
      final decoration = _firstDecorationUnder(tester, find.byType(SelectionFooter));
      expect(decoration.color, AppColors.bgSurface);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(SelectionFooter.radius),
      );
    });
  });

  group('分类条：整条一枚胶囊玻璃', () {
    AlbumMediaCounts counts() => AlbumMediaCounts.from([
          _media(1),
          _media(2),
          _media(3, live: true),
          _media(4, video: true),
        ]);

    Widget bar(AlbumMediaFilter selected, ValueChanged<AlbumMediaFilter> onChanged) {
      return AppSegmentedBarSurface(
        child: AlbumMediaFilterBar(
          counts: counts(),
          selected: selected,
          onChanged: onChanged,
        ),
      );
    }

    testWidgets('胶囊几何 + 选中只换文字颜色、不加填充块', (tester) async {
      _phone(tester);
      var selected = AlbumMediaFilter.all;
      late StateSetter setState;
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: StatefulBuilder(
                builder: (context, setter) {
                  setState = setter;
                  return bar(selected, (filter) {
                    setState(() => selected = filter);
                  });
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final capsule = find.byKey(AppSegmentedBar.surfaceKey);
      expect(capsule, findsOneWidget);
      final surface = tester.widget<AppGlassSurface>(capsule);
      expect(surface.requestedQuality, AppBottomTabBar.preferredQuality);
      expect(surface.preferPremium, isTrue);
      expect(surface.radius, kAppSegmentedBarPillRadius);

      final pill = tester.getRect(capsule);
      // 吸顶条 46 高、上下各 7：胶囊正好 32，圆角 = 高度/2。
      expect(pill.height, kAppSegmentedBarPillHeight);
      expect(pill.height, kAppSegmentedBarHeight - 14);
      expect(pill.height / 2, kAppSegmentedBarPillRadius);
      // 整条一枚：宽度铺满吸顶条内部（左右各 12）。
      expect(pill.width, 390 - 24);
      // 玻璃也只有一块：不是每一段各一块。
      expect(find.byType(GlassContainer), findsOneWidget);

      // 选中段 = 主题色文字，未选中 = 与底部 tab 同一档的中性灰。
      expect(tester.widget<Text>(find.text('全部')).style!.color, AppColors.primary);
      expect(
        tester.widget<Text>(find.text('照片')).style!.color,
        appTabBarInactiveColor,
      );

      // 四段里都没有填充块 / 水波纹：选中态只有文字颜色。
      for (var i = 0; i < 4; i++) {
        final segment = find.byKey(AppSegmentedBar.segmentKey(i));
        expect(segment, findsOneWidget);
        expect(
          find.descendant(of: segment, matching: find.byType(DecoratedBox)),
          findsNothing,
          reason: '第 $i 段加了底色/边框：选中态必须是纯文字颜色',
        );
        expect(
          find.descendant(of: segment, matching: find.byType(Container)),
          findsNothing,
        );
        expect(
          find.descendant(of: segment, matching: find.byType(Material)),
          findsNothing,
        );
      }

      // 切到「照片」：颜色换过去，胶囊尺寸一个像素都不动。
      await tester.tap(find.text('照片'));
      await tester.pumpAndSettle();
      expect(selected, AlbumMediaFilter.photos);
      expect(tester.widget<Text>(find.text('照片')).style!.color, AppColors.primary);
      expect(
        tester.widget<Text>(find.text('全部')).style!.color,
        appTabBarInactiveColor,
      );
      expect(tester.getRect(capsule), pill);
      expect(tester.takeException(), isNull);
    });

    testWidgets('minimal 档：整条退成同形状的不透明胶囊', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: bar(AlbumMediaFilter.all, (_) {}),
            ),
          ),
          quality: GlassQuality.minimal,
        ),
      );
      await tester.pump();

      final capsule = find.byKey(AppSegmentedBar.surfaceKey);
      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.getRect(capsule).height, kAppSegmentedBarPillHeight);

      final decoration = _firstDecorationUnder(tester, capsule);
      expect(decoration.color, AppColors.bgSurface);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(kAppSegmentedBarPillRadius),
      );
      final border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, AppColors.divider);
      // 四段文字与数量都还在（没有白屏）。
      for (final label in ['全部', '照片', '动态图片', '视频']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('上传按钮：玻璃 pill，让开时间轴轨道', () {
    testWidgets('是 pill 玻璃，且矩形与右侧轨道不相交', (tester) async {
      await _pumpAlbum(tester);

      final fab = find.byKey(AlbumUploadFab.surfaceKey);
      expect(fab, findsOneWidget);
      final surface = tester.widget<AppGlassSurface>(fab);
      expect(surface.requestedQuality, AppBottomTabBar.preferredQuality);
      expect(surface.preferPremium, isTrue);
      expect(surface.scrim, isTrue);
      expect(surface.radius, AlbumUploadFab.height / 2);
      expect(
        find.descendant(of: fab, matching: find.byType(GlassContainer)),
        findsOneWidget,
      );

      final fabRect = tester.getRect(fab);
      expect(fabRect.height, AlbumUploadFab.height);
      expect(fabRect.width, greaterThan(fabRect.height), reason: 'pill 不是圆钮');
      expect(
        find.descendant(of: fab, matching: find.text('上传照片')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: fab, matching: find.byIcon(Icons.add_a_photo_outlined)),
        findsOneWidget,
      );

      // 右侧时间轴轨道：30 宽的一条，从吸顶区下沿一直到底。
      final track = tester.getRect(find.byType(PhotoTimelineScrubber));
      expect(track.width, kTimelineTrackWidth);
      expect(
        fabRect.overlaps(track),
        isFalse,
        reason: '上传按钮压在轨道上：轨道下半段既拖不到也看不清',
      );
      expect(
        fabRect.right,
        lessThanOrEqualTo(track.left - AlbumUploadFab.trackGap + 0.01),
      );
      // 竖直方向确实和轨道同高——否则上面这条「不相交」是白测的。
      expect(fabRect.top, lessThan(track.bottom));
      expect(fabRect.bottom, greaterThan(track.top));
      // 仍然贴着右下角：底部只留一个 bottomGap。
      expect(844 - fabRect.bottom, AlbumUploadFab.bottomGap);
      expect(tester.takeException(), isNull);
    });

    testWidgets('minimal 档：退成同形状的不透明胶囊，仍然让开轨道', (tester) async {
      await _pumpAlbum(tester, quality: GlassQuality.minimal);

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);

      final fab = find.byKey(AlbumUploadFab.surfaceKey);
      expect(fab, findsOneWidget);
      final fabRect = tester.getRect(fab);
      expect(fabRect.height, AlbumUploadFab.height);

      final decoration = _firstDecorationUnder(tester, fab);
      expect(decoration.color, AppColors.bgSurface);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(AlbumUploadFab.radius),
      );
      final border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, AppColors.divider);
      expect(find.text('上传照片'), findsOneWidget);

      final track = tester.getRect(find.byType(PhotoTimelineScrubber));
      expect(fabRect.overlaps(track), isFalse, reason: '退化也不许压轨道');
    });
  });
}
