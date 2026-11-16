import 'dart:convert';
import 'dart:io';

import 'package:album_app/core/design/colors.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/page_backdrop_controller.dart';
import 'package:album_app/core/page_backdrop_spec.dart';
import 'package:album_app/features/profile/page_backdrop_sheet.dart';
import 'package:album_app/features/profile/theme_accent_picker_page.dart';
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
    PageBackdropController.spec.value =
        const PageBackdropSpec.defaultGradient();
    tempRoot = await Directory.systemTemp.createTemp('page_backdrop_test');
    backdropDir = Directory('${tempRoot.path}/page_backdrop');
    PageBackdropController.dirOverride = () async => backdropDir;
  });

  tearDown(() async {
    PageBackdropController.dirOverride = null;
    PageBackdropController.pickPhotoOverride = null;
    PageBackdropController.spec.value =
        const PageBackdropSpec.defaultGradient();
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

  /// 弹层里的动作会做真文件 IO（复制/删除/prefs），假时钟等不到它。
  ///
  /// 每一步 IO 完成后，它的 await 续体排在**假时钟**的微任务队列里；所以
  /// 要在「真实事件循环跑一会儿」和「pump 一次把续体放出来」之间来回交替
  /// ——只 runAsync 一次只够走完第一个 await，链子就停在那儿。
  Future<void> settleRealIo(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  group('spec：四类形态的模型与持久化格式', () {
    test('四种形态都能 JSON 往返，存的是 spec 而不是裸路径', () {
      const specs = <PageBackdropSpec>[
        PageBackdropSpec.defaultGradient(),
        PageBackdropSpec.solid(Color(0xFF123456)),
        PageBackdropSpec.gradient(
          start: Color(0xFF112233),
          end: Color(0xFFAABBCC),
        ),
        PageBackdropSpec.image('/data/app/page_backdrop/page_backdrop.jpg'),
      ];
      for (final spec in specs) {
        final decoded = PageBackdropSpec.decode(spec.encode());
        expect(decoded, spec, reason: '${spec.type} 往返后要一模一样');
        expect(decoded!.type, spec.type);
      }
      expect(
        jsonDecode(const PageBackdropSpec.solid(Color(0xFF123456)).encode()),
        {'type': 'color', 'color': 0xFF123456},
      );
      expect(
        jsonDecode(const PageBackdropSpec.gradient(
          start: Color(0xFF000001),
          end: Color(0xFF000002),
        ).encode()),
        {'type': 'gradient', 'start': 0xFF000001, 'end': 0xFF000002},
      );
    });

    test('坏数据 / 缺字段一律 null，调用点回退默认渐变', () {
      expect(PageBackdropSpec.decode(null), isNull);
      expect(PageBackdropSpec.decode(''), isNull);
      expect(PageBackdropSpec.decode('not json'), isNull);
      expect(PageBackdropSpec.decode('[]'), isNull);
      expect(PageBackdropSpec.decode('{"type":"color"}'), isNull);
      expect(PageBackdropSpec.decode('{"type":"gradient","start":1}'),
          isNull);
      expect(PageBackdropSpec.decode('{"type":"image"}'), isNull);
      expect(PageBackdropSpec.decode('{"type":"nope"}'), isNull);
      expect(PageBackdropSpec.decode('{"type":"default"}'),
          const PageBackdropSpec.defaultGradient());
    });

    test('设置页文案跟着形态走', () {
      expect(const PageBackdropSpec.defaultGradient().label, '默认渐变');
      expect(const PageBackdropSpec.solid(Color(0xFF00FF00)).label, '纯色');
      expect(
        const PageBackdropSpec.gradient(
          start: Color(0xFF000000),
          end: Color(0xFFFFFFFF),
        ).label,
        '渐变',
      );
      expect(const PageBackdropSpec.image('/x.jpg').label, '自定义');
    });
  });

  group('背景图：压缩 / 私有目录 / 持久化', () {
    test('选图请求 2048 最长边 + JPEG 80，并把副本复制进私有目录', () async {
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
      // 上限与解码上限同一个数（2K 屏宽）：副本比解码尺寸小就会被放大、放大
      // 就是糊，所以这里不能还停在 1080。
      expect(requestedEdge, 2048);
      expect(requestedQuality, 80);
      expect(PageBackdropController.maxEdge, 2048);
      expect(PageBackdropController.jpegQuality, 80);
      expect(PageBackdropController.maxEdge, appBackdropDecodeMaxWidth);

      expect(saved, isNotNull);
      final copy = File(saved!);
      expect(copy.existsSync(), isTrue, reason: '副本要真的落到私有目录里');
      expect(copy.path, startsWith(backdropDir.path));
      expect(copy.path, isNot(source.path), reason: '不能长期持有相册/临时文件');

      final spec = PageBackdropController.spec.value;
      expect(spec.type, PageBackdropType.image);
      expect(spec.imagePath, saved);
      // 落盘的是一段 spec JSON，不再只是路径。
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(PageBackdropController.prefsKey)!;
      expect(stored, isNot(saved));
      expect(PageBackdropSpec.decode(stored), spec);
    });

    test('冷启动读回 spec；文件丢了自动回退默认并清掉 key', () async {
      PageBackdropController.pickPhotoOverride = pickThis(galleryPhoto());
      final saved = (await PageBackdropController.pickAndSave())!;

      // 模拟重启：内存里先回到默认，再从 prefs 读回来。
      PageBackdropController.spec.value =
          const PageBackdropSpec.defaultGradient();
      await PageBackdropController.init();
      expect(PageBackdropController.spec.value.imagePath, saved);

      // 副本被清理工具/用户删掉。
      File(saved).deleteSync();
      PageBackdropController.spec.value =
          const PageBackdropSpec.defaultGradient();
      await PageBackdropController.init();
      expect(PageBackdropController.spec.value.isDefault, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PageBackdropController.prefsKey), isNull,
          reason: '文件没了还留着 key 会每次启动都白 try 一次');
      // 渲染层也不认这个路径。
      expect(PageBackdropController.imageFileOrNull(saved), isNull);
    });

    test('恢复默认：删文件 + 清 key + 通知三个页面回退', () async {
      PageBackdropController.pickPhotoOverride = pickThis(galleryPhoto());
      final saved = (await PageBackdropController.pickAndSave())!;

      await PageBackdropController.reset();

      expect(PageBackdropController.spec.value.isDefault, isTrue);
      expect(File(saved).existsSync(), isFalse, reason: '恢复默认要删掉副本');
      expect(backdropDir.listSync(), isEmpty, reason: '私有目录不留残留');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PageBackdropController.prefsKey), isNull);
      expect(prefs.getString(PageBackdropController.legacyPrefsKey), isNull);
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
      expect(PageBackdropController.spec.value.imagePath, second);
    });

    test('切成纯色：spec 落盘成 JSON，旧图片副本不再留着', () async {
      PageBackdropController.pickPhotoOverride = pickThis(galleryPhoto());
      final saved = (await PageBackdropController.pickAndSave())!;
      expect(File(saved).existsSync(), isTrue);

      await PageBackdropController.setColor(const Color(0xFF336699));

      final spec = PageBackdropController.spec.value;
      expect(spec.type, PageBackdropType.color);
      expect(spec.color, const Color(0xFF336699));
      final prefs = await SharedPreferences.getInstance();
      expect(
        PageBackdropSpec.decode(
          prefs.getString(PageBackdropController.prefsKey),
        ),
        const PageBackdropSpec.solid(Color(0xFF336699)),
      );
      // 副本已经不被引用：删掉（_commit 里是 fire-and-forget，等它跑完）。
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(File(saved).existsSync(), isFalse);
    });

    test('双色渐变也能落盘 / 读回', () async {
      await PageBackdropController.setGradient(
        const Color(0xFF102030),
        const Color(0xFFE0D0C0),
      );
      const expected = PageBackdropSpec.gradient(
        start: Color(0xFF102030),
        end: Color(0xFFE0D0C0),
      );
      expect(PageBackdropController.spec.value, expected);

      PageBackdropController.spec.value =
          const PageBackdropSpec.defaultGradient();
      await PageBackdropController.init();
      expect(PageBackdropController.spec.value, expected);
    });
  });

  group('旧 key（只存图片路径）迁移', () {
    test('旧 key 有值且文件还在：迁移成 image spec，旧 key 删掉', () async {
      final file = galleryPhoto();
      SharedPreferences.setMockInitialValues({
        PageBackdropController.legacyPrefsKey: file.path,
      });

      await PageBackdropController.init();

      final spec = PageBackdropController.spec.value;
      expect(spec.type, PageBackdropType.image);
      expect(spec.imagePath, file.path);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PageBackdropController.legacyPrefsKey), isNull,
          reason: '迁移完不留旧 key，否则就是第二份真相');
      expect(
        PageBackdropSpec.decode(
          prefs.getString(PageBackdropController.prefsKey),
        ),
        spec,
      );
    });

    test('旧 key 指向的文件已经没了：回退默认，两个 key 都清掉', () async {
      SharedPreferences.setMockInitialValues({
        PageBackdropController.legacyPrefsKey: '${tempRoot.path}/gone.jpg',
      });

      await PageBackdropController.init();

      expect(PageBackdropController.spec.value.isDefault, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PageBackdropController.legacyPrefsKey), isNull);
      expect(prefs.getString(PageBackdropController.prefsKey), isNull);
    });

    test('新 key 已经在时以新 key 为准，顺手清掉旧 key', () async {
      final file = galleryPhoto();
      SharedPreferences.setMockInitialValues({
        PageBackdropController.prefsKey:
            const PageBackdropSpec.solid(Color(0xFFFF0000)).encode(),
        PageBackdropController.legacyPrefsKey: file.path,
      });

      await PageBackdropController.init();

      expect(
        PageBackdropController.spec.value,
        const PageBackdropSpec.solid(Color(0xFFFF0000)),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PageBackdropController.legacyPrefsKey), isNull);
    });
  });

  group('背景渲染：四种形态', () {
    Future<void> pumpBackdrop(
      WidgetTester tester, {
      bool dark = false,
      Size physicalSize = const Size(400, 900),
      double devicePixelRatio = 1.0,
    }) async {
      tester.view.physicalSize = physicalSize;
      tester.view.devicePixelRatio = devicePixelRatio;
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

    testWidgets('默认：品牌渐变 + 两团光斑', (tester) async {
      await pumpBackdrop(tester);

      expect(find.byKey(AppGlassBackdrop.gradientKey), findsOneWidget);
      expect(find.byKey(AppGlassBackdrop.blobKey), findsNWidgets(2));
      expect(find.byKey(AppGlassBackdrop.colorKey), findsNothing);
      expect(find.byKey(AppGlassBackdrop.customGradientKey), findsNothing);
      expect(find.byKey(AppGlassBackdrop.maskKey), findsNothing);
    });

    testWidgets('纯色：一块 Color，且不套遮罩', (tester) async {
      PageBackdropController.spec.value =
          const PageBackdropSpec.solid(Color(0xFF234567));
      await pumpBackdrop(tester);

      final layer = tester.widget<DecoratedBox>(
        find.byKey(AppGlassBackdrop.colorKey),
      );
      expect(
        (layer.decoration as BoxDecoration).color,
        const Color(0xFF234567),
      );
      // 遮罩只为「图上的文字读得清」而存在：纯色不套。
      expect(find.byKey(AppGlassBackdrop.maskKey), findsNothing,
          reason: '纯色是用户挑的底，套遮罩等于改他的颜色');
      expect(find.byKey(AppGlassBackdrop.gradientKey), findsNothing);
      expect(find.byKey(AppGlassBackdrop.blobKey), findsNothing);
      expect(find.byKey(AppGlassBackdrop.imageKey), findsNothing);
      // 不透明页面底色还在，纯色层画在它上面。
      final base = tester.widget<DecoratedBox>(
        find.byKey(AppGlassBackdrop.baseKey),
      );
      expect((base.decoration as BoxDecoration).color, AppColors.bgPage);
      expect(tester.takeException(), isNull);
    });

    testWidgets('双色渐变：左上→右下两个色标，且不套遮罩', (tester) async {
      PageBackdropController.spec.value = const PageBackdropSpec.gradient(
        start: Color(0xFF0A1B2C),
        end: Color(0xFFDDEEFF),
      );
      await pumpBackdrop(tester);

      final layer = tester.widget<DecoratedBox>(
        find.byKey(AppGlassBackdrop.customGradientKey),
      );
      final gradient =
          (layer.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.begin, Alignment.topLeft);
      expect(gradient.end, Alignment.bottomRight);
      expect(
        gradient.colors,
        const [Color(0xFF0A1B2C), Color(0xFFDDEEFF)],
      );
      expect(gradient.stops, isNull, reason: '就两个色标，0 与 1，不需要 stops');
      expect(find.byKey(AppGlassBackdrop.maskKey), findsNothing,
          reason: '渐变和纯色一样不压遮罩');
      expect(find.byKey(AppGlassBackdrop.gradientKey), findsNothing);
      expect(find.byKey(AppGlassBackdrop.blobKey), findsNothing);
      expect(find.byKey(AppGlassBackdrop.imageKey), findsNothing);
    });

    testWidgets('图片：cover 铺满 + 遮罩 α0.35（浅色）', (tester) async {
      PageBackdropController.spec.value =
          PageBackdropSpec.image(galleryPhoto().path);
      await pumpBackdrop(tester);

      final image =
          tester.widget<Image>(find.byKey(AppGlassBackdrop.imageKey));
      expect(image.fit, BoxFit.cover);
      expect(image.filterQuality, FilterQuality.medium,
          reason: '背景图不许被降成 low：低质量过滤本身就是「糊」的一种来源');
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      expect((provider as ResizeImage).width, 400);
      expect(
        provider.width,
        appBackdropDecodeWidth(
          tester.element(find.byType(AppGlassBackdrop)),
        ),
      );

      final mask = tester
          .widget<DecoratedBox>(find.byKey(AppGlassBackdrop.maskKey));
      final color = (mask.decoration as BoxDecoration).color!;
      expect(color.a, closeTo(0.35, 0.0001));
      expect(color, AppColors.bgPage.withValues(alpha: 0.35));

      // 有图就不画渐变/光斑/纯色层；也不额外叠模糊层。
      expect(find.byKey(AppGlassBackdrop.gradientKey), findsNothing);
      expect(find.byKey(AppGlassBackdrop.blobKey), findsNothing);
      expect(find.byKey(AppGlassBackdrop.colorKey), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppGlassBackdrop),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('深色：遮罩加深到 α0.45', (tester) async {
      PageBackdropController.spec.value =
          PageBackdropSpec.image(galleryPhoto().path);
      await pumpBackdrop(tester, dark: true);

      final mask = tester
          .widget<DecoratedBox>(find.byKey(AppGlassBackdrop.maskKey));
      final color = (mask.decoration as BoxDecoration).color!;
      expect(color.a, closeTo(0.45, 0.0001));
      expect(color, AppColors.bgPage.withValues(alpha: 0.45));
    });

    testWidgets('解码宽度跟着屏幕走：3x 的 1200px 屏解 1200，不是写死的 1080',
        (tester) async {
      PageBackdropController.spec.value =
          PageBackdropSpec.image(galleryPhoto().path);
      await pumpBackdrop(
        tester,
        physicalSize: const Size(1200, 2600),
        devicePixelRatio: 3.0,
      );

      final image =
          tester.widget<Image>(find.byKey(AppGlassBackdrop.imageKey));
      expect((image.image as ResizeImage).width, 1200);
      expect((image.image as ResizeImage).width, greaterThan(1080),
          reason: '2K/高 dpi 屏上 1080 会被放大，放大就是糊');
    });

    testWidgets('解码宽度封顶 2048：超宽屏不无限往上堆', (tester) async {
      PageBackdropController.spec.value =
          PageBackdropSpec.image(galleryPhoto().path);
      await pumpBackdrop(
        tester,
        physicalSize: const Size(2800, 2000),
      );

      final image =
          tester.widget<Image>(find.byKey(AppGlassBackdrop.imageKey));
      expect((image.image as ResizeImage).width, appBackdropDecodeMaxWidth);
      expect(appBackdropDecodeMaxWidth, 2048);
    });

    testWidgets('图片文件丢失时回退默认渐变，不会露出空底', (tester) async {
      PageBackdropController.spec.value =
          PageBackdropSpec.image('${tempRoot.path}/gone.jpg');
      await pumpBackdrop(tester);

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

    testWidgets('四类选项都在：默认 / 纯色 / 双色渐变 / 图片', (tester) async {
      await openSheet(tester);

      expect(find.byKey(pageBackdropDefaultKey), findsOneWidget);
      expect(find.byKey(pageBackdropColorKey), findsOneWidget);
      expect(find.byKey(pageBackdropGradientKey), findsOneWidget);
      expect(find.byKey(pageBackdropPickKey), findsOneWidget);
      for (final label in ['默认（品牌渐变）', '纯色', '双色渐变', '从相册选一张图']) {
        expect(find.text(label), findsOneWidget, reason: '缺了「$label」这一项');
      }
      // 当前是默认：只有那一行打勾。
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('恢复默认'), findsNothing);
    });

    testWidgets('纯色：复用主题色的 HSV 取色器，保存后 spec 变纯色', (tester) async {
      await openSheet(tester);

      await tester.tap(find.byKey(pageBackdropColorKey));
      await tester.pumpAndSettle();

      // 同一个取色器：三条 Slider + 保存，不另写一个。
      expect(find.byType(HsvColorPickerPage), findsOneWidget);
      expect(find.text('纯色背景'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(3));

      // 取色器上显示的那个十六进制，就是保存下去的颜色。
      final hexText = tester.widget<Text>(
        find.textContaining(RegExp(r'^#[0-9A-F]{6}$')),
      );
      final expected = 0xFF000000 |
          int.parse(hexText.data!.substring(1), radix: 16);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final spec = PageBackdropController.spec.value;
      expect(spec.type, PageBackdropType.color);
      expect(spec.color!.toARGB32(), expected);
    });

    testWidgets('双色渐变：两个色标可分别取色，保存后 spec 变渐变', (tester) async {
      await openSheet(tester);

      await tester.tap(find.byKey(pageBackdropGradientKey));
      await tester.pumpAndSettle();

      expect(find.byKey(pageBackdropGradientPreviewKey), findsOneWidget);
      expect(find.byKey(pageBackdropGradientStartKey), findsOneWidget);
      expect(find.byKey(pageBackdropGradientEndKey), findsOneWidget);

      // 预览就是渲染层那个方向：左上 → 右下，两个色标。
      final preview = tester.widget<Container>(
        find.byKey(pageBackdropGradientPreviewKey),
      );
      final previewGradient =
          (preview.decoration! as BoxDecoration).gradient! as LinearGradient;
      expect(previewGradient.begin, Alignment.topLeft);
      expect(previewGradient.end, Alignment.bottomRight);
      expect(previewGradient.colors.length, 2);

      // 点起始色进的是同一个 HSV 取色器；取完回来还在这层。
      await tester.tap(find.byKey(pageBackdropGradientStartKey));
      await tester.pumpAndSettle();
      expect(find.byType(HsvColorPickerPage), findsOneWidget);
      expect(find.text('起始色（左上）'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(pageBackdropGradientPreviewKey), findsOneWidget);

      await tester.tap(find.byKey(pageBackdropGradientSaveKey));
      await tester.pumpAndSettle();

      final spec = PageBackdropController.spec.value;
      expect(spec.type, PageBackdropType.gradient);
      // 没动取色器时两端就是进来时的默认：主题色提亮一档 / 主题色。
      expect(
        spec.gradientStart,
        Color.lerp(AppColors.primary, Colors.white, 0.35),
      );
      expect(spec.gradientEnd, AppColors.primary);
    });

    testWidgets('有自定义图时「默认」就是恢复默认：删文件 + 清 key', (tester) async {
      PageBackdropController.pickPhotoOverride = pickThis(galleryPhoto());
      late String saved;
      await tester.runAsync(() async {
        saved = (await PageBackdropController.pickAndSave())!;
      });
      expect(File(saved).existsSync(), isTrue);

      await openSheet(tester);
      expect(find.text('默认（品牌渐变）'), findsOneWidget);
      // 图片那一行是勾选态。
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.tap(find.byKey(pageBackdropDefaultKey));
      await tester.pump();
      await settleRealIo(tester);

      expect(PageBackdropController.spec.value.isDefault, isTrue);
      expect(File(saved).existsSync(), isFalse, reason: '恢复默认要删掉副本');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('选图成功后不弹任何提示：背景本身就是反馈', (tester) async {
      PageBackdropController.pickPhotoOverride = pickThis(galleryPhoto());
      await openSheet(tester);

      await tester.tap(find.byKey(pageBackdropPickKey));
      await tester.pump();
      await settleRealIo(tester);

      expect(PageBackdropController.spec.value.isImage, isTrue);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('背景已更新'), findsNothing);
      expect(find.textContaining('已恢复'), findsNothing);
    });

    testWidgets('选图失败只提示失败：页面看起来没反应时必须说话', (tester) async {
      PageBackdropController.pickPhotoOverride =
          ({required int maxEdge, required int jpegQuality}) async =>
              throw StateError('相册不可用');
      await openSheet(tester);

      await tester.tap(find.byKey(pageBackdropPickKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('设置失败'), findsOneWidget);
      expect(PageBackdropController.spec.value.isDefault, isTrue);
    });
  });
}
