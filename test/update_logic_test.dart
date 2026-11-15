import 'dart:async';

import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/update/download_progress.dart';
import 'package:album_app/features/update/force_update_dialog.dart';
import 'package:album_app/features/update/update_action_button.dart';
import 'package:album_app/models/app_release.dart';
import 'package:album_app/widgets/app_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality;

const _release = AppRelease(
  versionCode: 2,
  versionName: '1.1.0',
  filename: 'app-v1.1.0.apk',
  fileSize: 10 * 1024 * 1024,
  sha256: '',
  releaseNotes: '修复问题\n优化体验',
  publishedAt: '2026-10-25T05:00:00Z',
);

void main() {
  group('DownloadProgress', () {
    test('calculates percent, labels and eta', () {
      const progress = DownloadProgress(
        received: 5 * 1024 * 1024,
        total: 10 * 1024 * 1024,
        bytesPerSecond: 2 * 1024 * 1024,
      );

      expect(progress.percent, closeTo(0.5, 0.0001));
      expect(progress.receivedLabel, '5.0 MB');
      expect(progress.totalLabel, '10.0 MB');
      expect(progress.speedLabel, '2.0 MB/s');
      expect(progress.eta.inSeconds, 3);
      expect(progress.etaLabel, contains('3 秒'));
    });

    test('unknown total and zero speed are safe', () {
      const progress = DownloadProgress(
        received: 0,
        total: 0,
        bytesPerSecond: 0,
      );
      expect(progress.percent, 0);
      expect(progress.totalLabel, '未知');
      expect(progress.speedLabel, '0 KB/s');
      expect(progress.etaLabel, '正在计算剩余时间…');
    });
  });

  group('AppRelease', () {
    test('parses camelCase update API fields', () {
      final release = AppRelease.fromJson({
        'versionCode': 3,
        'versionName': '1.2.0',
        'filename': 'app-v1.2.0.apk',
        'fileSize': 29360128,
        'sha256': 'abc',
        'releaseNotes': '更新内容',
        'publishedAt': '2026-10-25T05:00:00Z',
      });
      expect(release.versionCode, 3);
      expect(release.versionName, '1.2.0');
      expect(release.fileSize, 29360128);
      expect(release.sizeLabel, '28.0 MB');
    });

    test('also tolerates snake_case while old servers are mixed', () {
      final release = AppRelease.fromJson({
        'version_code': 2,
        'version_name': '1.1.0',
        'filename': 'app-v1.1.0.apk',
        'file_size': 1024,
        'sha256': '',
        'release_notes': 'notes',
        'published_at': '2026-10-25T05:00:00Z',
      });
      expect(release.versionCode, 2);
      expect(release.versionName, '1.1.0');
      expect(release.fileSize, 1024);
    });
  });

  group('强制更新弹窗', () {
    /// 打开弹窗；下载/安装注入假实现，测试不碰网络也不碰系统安装器。
    Future<void> pumpDialog(
      WidgetTester tester, {
      UpdateDownload? download,
      UpdateInstall? install,
      GlassQuality? quality,
    }) async {
      final app = MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showForceUpdateDialog(
                  context,
                  _release,
                  download: download,
                  install: install,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        quality == null ? app : AppGlassScope(quality: quality, child: app),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('没有取消入口，点外面和返回键都关不掉', (tester) async {
      await pumpDialog(tester);

      expect(find.text('版本更新'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      // 一行版本信息：版本号 + 包大小，没有「安装包大小：」这种第二行标签。
      expect(find.text('v1.1.0 · 10.0 MB'), findsOneWidget);
      expect(find.text('稍后'), findsNothing);
      expect(find.text('取消'), findsNothing);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('版本更新'), findsOneWidget, reason: '点遮罩不能关');

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('版本更新'), findsOneWidget, reason: '返回键无效');
    });

    testWidgets('下载中：进度长在按钮里，弹窗里没有独立进度条', (tester) async {
      final gate = Completer<void>();
      var started = 0;
      Future<String> download(
        AppRelease release, {
        required void Function(DownloadProgress) onProgress,
      }) async {
        started++;
        onProgress(const DownloadProgress(
          received: 42 * 1024 * 1024,
          total: 100 * 1024 * 1024,
          bytesPerSecond: 0,
        ));
        await gate.future;
        return '/tmp/app-v1.1.0.apk';
      }

      await pumpDialog(tester, download: download, install: (_) async => true);

      await tester.tap(find.text('立即更新'));
      await tester.pump();
      expect(started, 1);

      // 百分比只在按钮文字里出现一次。
      expect(find.text('下载中 42%'), findsOneWidget);
      expect(find.textContaining('42%'), findsOneWidget);

      // 旧版那套独立进度条 + 速度/剩余时间的仪表盘已经删掉。
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // 填充按 220ms 补间走完，宽度就是 42%。
      await tester.pump(const Duration(milliseconds: 260));
      final fillWidth =
          tester.getSize(find.byKey(UpdateActionButton.fillKey)).width;
      final buttonWidth = tester.getSize(find.byType(UpdateActionButton)).width;
      expect(fillWidth / buttonWidth, closeTo(0.42, 0.02));

      // 下载中再点也不会重复下载。
      await tester.tap(find.byType(UpdateActionButton));
      await tester.pump();
      expect(started, 1);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('下载完成：按钮换成下一步文案并闪一下', (tester) async {
      Future<String> download(
        AppRelease release, {
        required void Function(DownloadProgress) onProgress,
      }) async {
        onProgress(const DownloadProgress(
          received: 100 * 1024 * 1024,
          total: 100 * 1024 * 1024,
          bytesPerSecond: 0,
        ));
        return '/tmp/app-v1.1.0.apk';
      }

      await pumpDialog(tester, download: download, install: (_) async => true);

      await tester.tap(find.text('立即更新'));
      await tester.pump();
      // 完成反馈：高亮叠层在这一帧之后开始，100ms 时亮度还没回到 0。
      await tester.pump(const Duration(milliseconds: 100));
      final flash = tester.widget<DecoratedBox>(
        find.byKey(UpdateActionButton.flashKey),
      );
      expect(
        (flash.decoration as BoxDecoration).color!.a,
        greaterThan(0),
        reason: '下载完成要闪一次高亮，不是静默换文案',
      );

      await tester.pumpAndSettle();
      expect(find.text('重新打开安装器'), findsOneWidget,
          reason: '下载 + 安装器都完成后按钮换成可点的下一步');
      expect(find.text('下载中 100%'), findsNothing);
    });

    testWidgets('玻璃可用时弹窗背景是玻璃', (tester) async {
      await pumpDialog(tester, quality: GlassQuality.standard);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(GlassContainer),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('minimal 档：弹窗退回不透明表面，没有模糊', (tester) async {
      await pumpDialog(tester, quality: GlassQuality.minimal);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(GlassContainer),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(find.text('版本更新'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
