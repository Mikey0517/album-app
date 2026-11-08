import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/update/download_progress.dart';
import 'package:album_app/features/update/force_update_dialog.dart';
import 'package:album_app/models/app_release.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('force update dialog has no cancel and blocks back',
      (tester) async {
    const release = AppRelease(
      versionCode: 2,
      versionName: '1.1.0',
      filename: 'app-v1.1.0.apk',
      fileSize: 10 * 1024 * 1024,
      sha256: '',
      releaseNotes: '修复问题\n优化体验',
      publishedAt: '2026-10-25T05:00:00Z',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showForceUpdateDialog(context, release),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('版本更新'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('必须更新'), findsOneWidget);
    expect(find.text('稍后'), findsNothing);
    expect(find.text('取消'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('版本更新'), findsOneWidget);
  });
}
