import 'dart:io';

import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/upload_manager.dart';
import 'package:album_app/widgets/upload_status_overlay.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

DioException _networkError() => DioException(
      requestOptions: RequestOptions(path: '/api/albums/1/media'),
      type: DioExceptionType.connectionError,
    );

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('等待超时');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final manager = UploadManager.instance;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('upload_sheet_test');
    manager.resetForTest();
  });

  tearDown(() {
    manager.resetForTest();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // 忽略临时目录清理失败。
    }
  });

  testWidgets('勾选仅显示失败后可以直接一键全部重试', (tester) async {
    // 用 .mp4 避免测试环境解码真实图片。
    final a = File('${tmp.path}/a.mp4')..writeAsBytesSync([1, 2, 3]);
    final b = File('${tmp.path}/b.mp4')..writeAsBytesSync([1, 2, 3]);
    var calls = 0;
    UploadManager.uploader =
        (albumId, files, {onSendProgress, cancelToken}) async {
      calls++;
      if (calls <= 2) throw _networkError();
      return const [];
    };

    await tester.runAsync(() async {
      manager.enqueue(albumId: 1, files: [
        XFile(a.path, name: 'a.mp4'),
        XFile(b.path, name: 'b.mp4'),
      ]);
      await _waitUntil(() => manager.items.every((item) => item.failed));
    });

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showUploadListSheet(context, navigatorKey),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('全部重试'), findsOneWidget);
    expect(find.text('重试'), findsNWidgets(2));

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // 勾选“仅显示失败”后仍保留一键重试入口，并且能一次重试全部失败项。
    expect(find.text('全部重试'), findsOneWidget);
    expect(find.text('重试'), findsNWidgets(2));

    await tester.runAsync(() async {
      await tester.tap(find.text('全部重试'));
      await _waitUntil(
        () => manager.items.every((item) => item.done) && !manager.isUploading,
      );
    });
    await tester.pumpAndSettle();

    expect(calls, 4);
    expect(manager.failedCount, 0);
    expect(find.text('没有失败项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
