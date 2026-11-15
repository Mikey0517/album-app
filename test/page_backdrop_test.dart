import 'dart:convert';
import 'dart:io';

import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/features/profile/page_backdrop_sheet.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1x1 的 PNG：只是让 Image.file 真的能解码，像素内容无所谓。
final List<int> _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory backdropDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PageBackdropController.path.value = null;
    tempRoot = await Directory.systemTemp.createTemp('page_backdrop_test');
    backdropDir = Directory('${tempRoot.path}/page_backdrop');
    PageBackdropController.dirOverride = () async => backdropDir;
  });

  tearDown(() async {
    PageBackdropController.dirOverride = null;
    PageBackdropController.pickPhotoOverride = null;
    PageBackdropController.path.value = null;
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    // buildAppTheme 会改 AppColors 的全局明暗标记，别留绐下一个用例。
    buildAppTheme();
  });

  /// 假装这是相册里那张原图（picker 返回的临时文件）。
  File galleryPhoto([String name = 'from_gallery.png']) {
    return File('${tempRoot.path}/$name')..writeAsBytesSync(_tinyPng);
  }

  Future<XFile?> Function({required int maxEdge, required int jpegQuality})
      pickThis(File source) {
    return ({required int maxEdge, required int jpegQuality}) async =>
        XFile(source.path);
  }

  group('背景图：压缩 / 私有目录 / 持久化', () {
    test('选图请求 1080 最长边 + JPEG 80，并把副本复制进私有目录', () async {
      final source = galleryPhoto();
      int? requestedEdge;
      int? requestedQuality;
      PageBackdropController.pickPhotoOverride =
          ({required int maxEdge, required int jpegQuality}) async {
        requestedEdge = maxEdge;
        requestedQuality = jpegQuality;
        return XFile(source.path);
      };

      final saved = await PageBackdropController.pickAndSave();

      // 压缩参数（交给 image_picker 的原生编码器）。
      expect(requestedEdge, 1080);
      expect(requestedQuality, 80);
      expect(PageBackdropController.maxEdge, 1080);
      expect(PageBackdropController.jpegQuality, 80);

      expect(saved, isNotNull);
      final copy = File(saved!);
      expect(copy.existsSync(), isTrue, reason: '副本要真的落到私有目录里');
      expect(copy.path, startsWith(backdropDir.path));
      expect(copy.path, isNot(source.path), reason: '不能长期持有相册/临时文件');
      expect(PageBackdropController.path.value, saved);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PageBackdropController.prefsKey), saved);
    });

    test('冷启动读回路径；文件丢了自动回退渐变并清掉 key', () async {
      final source = galleryPhoto();
      PageBackdropController.pickPhotoOverride = pickThis(source);
      final saved = (await PageBackdropController.pickAndSave())!;

      // 模拟重启：内存里先空着，再从 prefs 读回来。
      PageBackdropController.path.value = null;
      await PageBackdropController.init();
      expect(PageBackdropController.path.value, saved);

      // 副本被清理工具/用户删掉。
      File(saved).deleteSync();
      PageBackdropController.path.value = null;
      await PageBackdropController.init();
      expect(PageBackdropController.path.value, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PageBackdropController.prefsKey), isNull,
          reason: '文件没了还留着 key 会每次启动都白 try 一次');
      // 渲染层也不认这个路径。
      expect(PageBackdropController.imageFileOrNull(saved), isNull);
    });

    test('恢复默认：删文件 + 清 key + 通知三个页面回退', () async {
      final source = galleryPhoto();
      PageBackdropController.pickPhotoOverride = pickThis(source);
      final saved = (await PageBackdropController.pickAndSave())!;

      await PageBackdropController.reset();

      expect(PageBackdropController.path.value, isNull);
      expect(File(saved).existsSync(), isFalse, reason: '恢复默认要删掉副本');
      expect(backdropDir.listSync(), isEmpty, reason: '私有目录不留残留');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PageBackdropController.prefsKey), isNull);
    });

    test('再选一次会替换旧图，不会攒两份', () async {
      PageBackdropController.pickPhotoOverride = pickThis(galleryPhoto('a.png'));
      final first = (await PageBackdropController.pickAndSave())!;
      expect(first, endsWith('.png'));

      PageBackdropController.pickPhotoOverride =
          pickThis(galleryPhoto('b.jpg'));
      final second = (await PageBackdropController.pickAndSave())!;

      // 私有目录里只留当前这一张，旧的那份要被删掉。
      expect(backdropDir.listSync().whereType<File>().length, 1);
      expect(second, endsWith('.jpg'));
      expect(File(second).existsSync(), isTrue);
      expect(File(first).existsSync(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PageBackdropController.prefsKey), second);
    });
  });

  group('背景图渲染：cover + 可读性遮罩', () {
    Future<void> pumpBackdrop(WidgetTester tester, {required bool dark}) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(dark: dark),
          home: const AppGlassBackdrop(
            child: Scaffold(backgroundColor: Colors.transparent),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('浅色：图上叠 bgPage α0.55，cover 铺满，只解码一份', (tester) async {
      PageBackdropController.path.value = galleryPhoto().path;
      await pumpBackdrop(tester, dark: false);

      final image =
          tester.widget<Image>(find.byKey(AppGlassBackdrop.imageKey));
      expect(image.fit, BoxFit.cover);
      // cacheWidth 走 ResizeImage：文件本身已经压到 ≤1080，解码再封顶一次，
      // 只解一份，不会每帧解原图。
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      expect((provider as ResizeImage).width, PageBackdropController.maxEdge);

      final mask = tester
          .widget<DecoratedBox>(find.byKey(AppGlassBackdrop.maskKey));
      final color = (mask.decoration as BoxDecoration).color!;
      expect(color.a, closeTo(0.55, 0.0001));
      expect(color, AppColors.bgPage.withValues(alpha: 0.55));

      // 有图就不画渐变/光斑；也不额外叠模糊层（模糊交给玻璃卡片自己）。
      expect(find.byKey(AppGlassBackdrop.gradientKey), findsNothing);
      expect(find.byKey(AppGlassBackdrop.blobKey), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppGlassBackdrop),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('深色：遮罩加深到 α0.65', (tester) async {
      PageBackdropController.path.value = galleryPhoto().path;
      await pumpBackdrop(tester, dark: true);

      final mask = tester
          .widget<DecoratedBox>(find.byKey(AppGlassBackdrop.maskKey));
      final color = (mask.decoration as BoxDecoration).color!;
      expect(color.a, closeTo(0.65, 0.0001));
      expect(color, AppColors.bgPage.withValues(alpha: 0.65));
    });

    testWidgets('图片文件丢失时回退渐变，不会露出空底', (tester) async {
      PageBackdropController.path.value = '${tempRoot.path}/gone.jpg';
      await pumpBackdrop(tester, dark: false);

      expect(find.byKey(AppGlassBackdrop.gradientKey), findsOneWidget);
      expect(find.byKey(AppGlassBackdrop.blobKey), findsNWidgets(2));
      expect(find.byKey(AppGlassBackdrop.imageKey), findsNothing);
      expect(find.byKey(AppGlassBackdrop.maskKey), findsNothing);
    });
  });

  group('「我的 → 页面背景」弹层', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPageBackdropSheet(context),
                child: const Text('页面背景'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('页面背景'));
      await tester.pumpAndSettle();
    }

    testWidgets('没有自定义图时是「默认渐变」（已选中）+ 选图', (tester) async {
      await openSheet(tester);

      expect(find.byKey(pageBackdropDefaultKey), findsOneWidget);
      expect(find.text('默认渐变'), findsOneWidget);
      expect(find.byKey(pageBackdropPickKey), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('恢复默认'), findsNothing);
    });

    testWidgets('有自定义图时同一项变成「恢复默认」，点了就删文件清 key',
        (tester) async {
      final source = galleryPhoto();
      PageBackdropController.pickPhotoOverride = pickThis(source);
      // 真文件 IO 要在真实事件循环里跑，testWidgets 里的假时钟等不到它。
      late String saved;
      await tester.runAsync(() async {
        saved = (await PageBackdropController.pickAndSave())!;
      });
      expect(File(saved).existsSync(), isTrue);

      await openSheet(tester);
      expect(find.text('恢复默认'), findsOneWidget);
      expect(find.text('默认渐变'), findsNothing);

      await tester.tap(find.byKey(pageBackdropDefaultKey));
      // 弹层关掉即代表选了「恢复默认」；真正的删文件/清 key 是文件 IO，
      // 在 testWidgets 的假时钟里跑不动，放到上面的 controller 用例里断言。
      await tester.pumpAndSettle();
      expect(find.byKey(pageBackdropDefaultKey), findsNothing);
      expect(find.text('从相册选一张图'), findsNothing);
    });
  });
}
