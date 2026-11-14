import 'dart:io';

import 'package:album_app/core/cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory tempDir;
  late Directory docsDir;
  late Directory uploadsDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('album_cache_test');
    tempDir = Directory('${tmp.path}/temp')..createSync();
    docsDir = Directory('${tmp.path}/docs')..createSync(recursive: true);
    uploadsDir = Directory('${docsDir.path}/picked_media')
      ..createSync(recursive: true);
    CacheService.dirsOverride = () async => CacheDirs(
          tempDir: tempDir.path,
          docsDir: docsDir.path,
        );
    // 默认不把程序本体算进去，各项断言只关心磁盘上的文件。
    CacheService.programBytesOverride = () => 0;
    CacheService.maxImageBytes = 1000;
    CacheService.keepImageBytes = 400;
    CacheService.updating = false;
  });

  tearDown(() {
    CacheService.dirsOverride = null;
    CacheService.programBytesOverride = null;
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
    expect(usage.pendingUploadCount, 1);
    expect(usage.clearableBytes, 3000);
  });

  test('四项之和就是 App 总占用（含 picked_media 与 other）', () async {
    writeFile('${tempDir.path}/album_image_cache/a.jpg', 1000);
    writeFile('${tempDir.path}/motion_photos/b.mp4', 2000);
    writeFile('${uploadsDir.path}/c.jpg', 3000);
    writeFile('${uploadsDir.path}/d.jpg', 500);
    // 私有目录里既不是缓存也不是副本的部分（数据库、配置等）。
    writeFile('${docsDir.path}/album.db', 4000);
    CacheService.programBytesOverride = () => 5000;

    final usage = await CacheService.measure();

    expect(usage.imageBytes, 1000);
    expect(usage.tempBytes, 2000);
    expect(usage.pendingUploadBytes, 3500);
    expect(usage.pendingUploadCount, 2);
    expect(usage.otherBytes, 4000 + 5000, reason: '其它私有文件 + 程序本体估算');
    expect(
      usage.appBytes,
      usage.imageBytes +
          usage.tempBytes +
          usage.pendingUploadBytes +
          usage.otherBytes,
      reason: '总占用必须是四项之和',
    );
    expect(usage.appBytes, 1000 + 2000 + 3500 + 9000);
    expect(usage.clearableBytes, 3000, reason: '待上传副本不计入可清理');
  });

  test('临时目录里的旧副本算待上传副本，不算临时文件', () async {
    writeFile('${tempDir.path}/picked_media/legacy.jpg', 700);
    writeFile('${tempDir.path}/motion_photos/b.mp4', 2000);

    final usage = await CacheService.measure();

    expect(usage.tempBytes, 2000);
    expect(usage.pendingUploadBytes, 700);
    expect(usage.pendingUploadCount, 1);
  });

  test('清理只删图片缓存和临时文件，保留待上传副本', () async {
    final image = writeFile('${tempDir.path}/album_image_cache/a.jpg', 1000);
    final temp = writeFile('${tempDir.path}/motion_photos/b.mp4', 2000);
    final upload = writeFile('${uploadsDir.path}/c.jpg', 3000);
    // 1.2.48 之前放在临时目录里的旧副本同样不能被清理。
    final legacy = writeFile('${tempDir.path}/picked_media/d.jpg', 800);

    final result = await CacheService.clear();

    expect(result.freedBytes, 3000);
    expect(image.existsSync(), isFalse);
    expect(temp.existsSync(), isFalse);
    expect(upload.existsSync(), isTrue, reason: '待上传副本不能被清理');
    expect(legacy.existsSync(), isTrue, reason: '旧副本也是待上传数据');
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
