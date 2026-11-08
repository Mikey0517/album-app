import 'dart:io';

import 'package:album_app/core/cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory tempDir;
  late Directory uploadsDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('album_cache_test');
    tempDir = Directory('${tmp.path}/temp')..createSync();
    uploadsDir = Directory('${tmp.path}/docs/picked_media')
      ..createSync(recursive: true);
    CacheService.dirsOverride = () async => CacheDirs(
          tempDir: tempDir.path,
          uploadsDir: uploadsDir.path,
        );
    CacheService.maxImageBytes = 1000;
    CacheService.keepImageBytes = 400;
    CacheService.updating = false;
  });

  tearDown(() {
    CacheService.dirsOverride = null;
    CacheService.maxImageBytes = 320 * 1024 * 1024;
    CacheService.keepImageBytes = 240 * 1024 * 1024;
    CacheService.updating = false;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // 忽略清理失败。
    }
  });

  File writeFile(String path, int bytes, {DateTime? modified}) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(bytes, 7));
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  test('统计分别算图片缓存、临时文件和待上传副本', () async {
    writeFile('${tempDir.path}/album_image_cache/a.jpg', 1000);
    writeFile('${tempDir.path}/motion_photos/b.mp4', 2000);
    writeFile('${uploadsDir.path}/c.jpg', 3000);

    final usage = await CacheService.measure();

    expect(usage.imageBytes, 1000);
    expect(usage.tempBytes, 2000);
    expect(usage.pendingUploadBytes, 3000);
    expect(usage.clearableBytes, 3000);
  });

  test('清理只删图片缓存和临时文件，保留待上传副本', () async {
    final image = writeFile('${tempDir.path}/album_image_cache/a.jpg', 1000);
    final temp = writeFile('${tempDir.path}/motion_photos/b.mp4', 2000);
    final upload = writeFile('${uploadsDir.path}/c.jpg', 3000);

    final result = await CacheService.clear();

    expect(result.freedBytes, 3000);
    expect(image.existsSync(), isFalse);
    expect(temp.existsSync(), isFalse);
    expect(upload.existsSync(), isTrue, reason: '待上传副本不能被清理');
    expect((await CacheService.measure()).clearableBytes, 0);
  });

  test('更新包下载中时跳过 album_updates', () async {
    final apk = writeFile('${tempDir.path}/album_updates/app.apk', 500);
    CacheService.updating = true;

    await CacheService.clear();

    expect(apk.existsSync(), isTrue);

    CacheService.updating = false;
    await CacheService.clear();
    expect(apk.existsSync(), isFalse);
  });

  test('超过预算时按最旧的先删，裁到保留线以下', () async {
    final old = writeFile(
      '${tempDir.path}/album_image_cache/old.jpg',
      400,
      modified: DateTime.now().subtract(const Duration(days: 10)),
    );
    final mid = writeFile(
      '${tempDir.path}/album_image_cache/mid.jpg',
      400,
      modified: DateTime.now().subtract(const Duration(days: 5)),
    );
    final fresh = writeFile('${tempDir.path}/album_image_cache/new.jpg', 400);

    // 3 × 400 = 1200 > 上限 1000，裁到 600 以下：删掉最旧的两张。
    await CacheService.trimIfNeeded();

    expect(old.existsSync(), isFalse);
    expect(mid.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
  });

  test('启动时清掉过期临时文件，保留新文件', () async {
    final stale = writeFile(
      '${tempDir.path}/album_share_1/a.jpg',
      100,
      modified: DateTime.now().subtract(const Duration(days: 8)),
    );
    final recent = writeFile('${tempDir.path}/album_share_2/b.jpg', 100);

    await CacheService.trimIfNeeded();

    expect(stale.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
  });
}