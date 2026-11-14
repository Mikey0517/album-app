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

  /// 模拟 Android 的目录布局：文档目录是 `<应用数据>/app_flutter`，
  /// 应用数据里有 databases / shared_prefs / files，supportDir 指向 files。
  ({Directory root, Directory docs, Directory files}) androidLayout() {
    final root = Directory('${tmp.path}/data')..createSync();
    final docs = Directory('${root.path}/app_flutter')..createSync();
    final files = Directory('${root.path}/files')..createSync();
    CacheService.dirsOverride = () async => CacheDirs(
          tempDir: tempDir.path,
          docsDir: docs.path,
          supportDir: files.path,
        );
    return (root: root, docs: docs, files: files);
  }

  /// 独立实测：把整套私有目录从头到尾走一遍（不经过 CacheService），
  /// 得到磁盘上的真实字节数，用来验证「分项之和 == 实测总量」。
  int actualPrivateBytes(Iterable<Directory> roots) {
    var total = 0;
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is File) total += entity.lengthSync();
      }
    }
    return total;
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

  test('五类子项各有各的数字，求和等于总计', () async {
    final layout = androidLayout();
    writeFile('${layout.root.path}/databases/album.db', 700);
    writeFile('${layout.root.path}/shared_prefs/FlutterSharedPreferences.xml', 300);
    writeFile('${layout.files.path}/support.bin', 900);
    writeFile('${tempDir.path}/album_image_cache/a.jpg', 1000);
    writeFile('${tempDir.path}/motion_photos/b.mp4', 2000);
    writeFile('${tempDir.path}/album_updates/app.apk', 400);
    writeFile('${tempDir.path}/album_share_1/c.jpg', 500);
    writeFile('${tempDir.path}/familyalbum_9_9.jpg', 600);
    writeFile('${layout.docs.path}/picked_media/e.jpg', 3000);
    writeFile('${layout.docs.path}/leftover.bin', 250);
    CacheService.programBytesOverride = () => 5000;

    final usage = await CacheService.measure();

    expect(usage.imageBytes, 1000);
    expect(usage.tempBytes, 2000, reason: '动图临时文件仍算临时文件');
    expect(usage.updateBytes, 400);
    expect(usage.shareBytes, 500 + 600, reason: '分享目录 + 保存到相册的中间文件');
    expect(usage.pendingUploadBytes, 3000);
    expect(
      usage.appDataBytes,
      700 + 300 + 900,
      reason: 'databases + shared_prefs + files，且 files 不能与私有目录重复统计',
    );
    expect(usage.programBytes, 5000);
    expect(usage.residueBytes, 250, reason: 'app_flutter 里对不上的剩余部分');
    expect(
      usage.otherBytes,
      400 + 1100 + 1900 + 5000 + 250,
      reason: '其它 = 五类子项之和',
    );
    expect(
      usage.updateBytes +
          usage.shareBytes +
          usage.appDataBytes +
          usage.programBytes +
          usage.residueBytes,
      usage.otherBytes,
    );
    expect(
      usage.appBytes,
      usage.imageBytes +
          usage.tempBytes +
          usage.pendingUploadBytes +
          usage.otherBytes,
      reason: '总占用必须是所有分项之和',
    );
    expect(usage.appBytes, 1000 + 2000 + 3000 + 8650);
    expect(
      usage.clearableBytes,
      1000 + 2000 + 400 + 1100 + 250,
      reason: '可清理 = 图片缓存 + 临时文件 + 更新包 + 分享/导出 + 其它残留',
    );
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
    expect(usage.residueBytes, 4000, reason: '对不上已知分项的剩余部分');
    expect(usage.otherBytes, 4000 + 5000, reason: '其它残留 + 程序本体估算');
    expect(
      usage.appBytes,
      usage.imageBytes +
          usage.tempBytes +
          usage.pendingUploadBytes +
          usage.otherBytes,
      reason: '总占用必须是四项之和',
    );
    expect(usage.appBytes, 1000 + 2000 + 3500 + 9000);
    expect(usage.clearableBytes, 3000 + 4000, reason: '待上传副本不计入可清理');
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

  test('主按钮清理删更新包与分享/导出，保留待上传副本、应用数据和程序本体', () async {
    final layout = androidLayout();
    final image = writeFile('${tempDir.path}/album_image_cache/a.jpg', 1000);
    final temp = writeFile('${tempDir.path}/motion_photos/b.mp4', 2000);
    final apk = writeFile('${tempDir.path}/album_updates/app.apk', 400);
    final shareDir = writeFile('${tempDir.path}/album_share_1/c.jpg', 500);
    final download = writeFile('${tempDir.path}/familyalbum_9_9.jpg', 600);
    final pending = writeFile('${layout.docs.path}/picked_media/e.jpg', 3000);
    // 残留在 app_flutter 里的分享/导出目录同样是可再生的。
    final shareResidue = writeFile('${layout.docs.path}/album_share_9/f.jpg', 300);
    final residue = writeFile('${layout.docs.path}/leftover.bin', 250);
    final db = writeFile('${layout.root.path}/databases/album.db', 700);
    final prefs =
        writeFile('${layout.root.path}/shared_prefs/prefs.xml', 300);
    final support = writeFile('${layout.files.path}/support.bin', 900);
    CacheService.programBytesOverride = () => 5000;

    final result = await CacheService.clear();

    expect(result.freedBytes, 1000 + 2000 + 400 + 500 + 600 + 300);
    expect(image.existsSync(), isFalse);
    expect(temp.existsSync(), isFalse);
    expect(apk.existsSync(), isFalse, reason: '更新包可清理');
    expect(shareDir.existsSync(), isFalse, reason: '分享临时目录可清理');
    expect(download.existsSync(), isFalse, reason: '保存到相册的中间文件可清理');
    expect(shareResidue.existsSync(), isFalse, reason: '残留里的分享目录也可再生');
    expect(pending.existsSync(), isTrue, reason: '待上传副本不能被清理');
    expect(db.existsSync(), isTrue, reason: '应用数据不可清理');
    expect(prefs.existsSync(), isTrue, reason: '应用数据不可清理');
    expect(support.existsSync(), isTrue, reason: 'files 属于应用数据');
    expect(residue.existsSync(), isTrue, reason: '拿不准的残留宁可留着');
  });

  test('应用数据不吞掉 files/picked_media：每个字节只归一类', () async {
    final layout = androidLayout();
    // 原生端（MainActivity）把待上传副本写进 filesDir/picked_media：
    // 一个「很大」的副本 + 一个小的普通文件。
    final big = writeFile(
      '${layout.files.path}/picked_media/big.mp4',
      4 * 1024 * 1024,
    );
    writeFile('${layout.files.path}/small.bin', 120);
    writeFile('${layout.root.path}/databases/album.db', 700);
    writeFile('${layout.root.path}/shared_prefs/prefs.xml', 300);
    // 文档目录里的副本（老布局）同样只算待上传副本。
    writeFile('${layout.docs.path}/picked_media/doc.jpg', 900);
    // 文档目录里对不上的残留。
    writeFile('${layout.docs.path}/leftover.bin', 60);
    writeFile('${tempDir.path}/album_image_cache/a.jpg', 1000);
    writeFile('${tempDir.path}/motion_photos/b.mp4', 2000);
    CacheService.programBytesOverride = () => 5000;

    final usage = await CacheService.measure();

    expect(
      usage.appDataBytes,
      700 + 300 + 120,
      reason: '应用数据 = databases + shared_prefs + files 里非 picked_media 的部分',
    );
    expect(
      usage.pendingUploadBytes,
      big.lengthSync() + 900,
      reason: '待上传副本 = files/picked_media + app_flutter/picked_media',
    );
    expect(usage.pendingUploadCount, 2);
    // files 里的字节只能算一次：应用数据里 files 那一份 + 副本 == files 实测总量。
    expect(
      usage.appDataBytes - (700 + 300) + big.lengthSync(),
      actualPrivateBytes([layout.files]),
      reason: 'files 里的字节不能两边都算',
    );
    expect(usage.residueBytes, 60);
    expect(
      usage.appBytes,
      actualPrivateBytes([layout.root, tempDir]) + 5000,
      reason: '所有分项之和 == 各私有根实测总量 + 程序本体',
    );
  });

  test('不变式：分项之和 == 私有根实测总量 + 程序本体', () async {
    final layout = androidLayout();
    writeFile('${layout.files.path}/picked_media/huge.bin', 3 * 1024 * 1024);
    writeFile('${layout.files.path}/keep.bin', 77);
    writeFile('${layout.files.path}/unknown_dir/x.bin', 33);
    writeFile('${layout.root.path}/databases/album.db', 512);
    writeFile('${layout.root.path}/shared_prefs/p.xml', 64);
    writeFile('${layout.docs.path}/picked_media/a.jpg', 800);
    writeFile('${layout.docs.path}/album.db', 4096);
    writeFile('${layout.docs.path}/nested/deep.bin', 12);
    writeFile('${tempDir.path}/album_image_cache/a.jpg', 256);
    writeFile('${tempDir.path}/album_updates/u.apk', 300);
    writeFile('${tempDir.path}/album_share_1/s.jpg', 128);
    writeFile('${tempDir.path}/familyalbum_1.jpg', 96);
    writeFile('${tempDir.path}/picked_media/legacy.jpg', 700);
    writeFile('${tempDir.path}/motion_photos/m.mp4', 2048);
    CacheService.programBytesOverride = () => 999;

    final usage = await CacheService.measure();
    final actual = actualPrivateBytes([layout.root, tempDir]);
    final sum = usage.imageBytes +
        usage.tempBytes +
        usage.pendingUploadBytes +
        usage.updateBytes +
        usage.shareBytes +
        usage.appDataBytes +
        usage.residueBytes;

    expect(
      sum,
      actual,
      reason: '任何一项吞掉别的项都会让和偏大，漏算则会偏小',
    );
    expect(usage.appBytes, actual + 999);
    expect(usage.appDataBytes, 512 + 64 + 77 + 33, reason: 'files 整体算应用数据（副本除外）');
    expect(usage.pendingUploadBytes, 3 * 1024 * 1024 + 800 + 700);
    expect(usage.residueBytes, 4096 + 12, reason: '残留逐目录实算，不靠总量减已知项');
  });

  test('其它残留只删传入的可再生路径，未知文件保留', () async {
    final shareDir = writeFile('${docsDir.path}/album_share_7/a.jpg', 300);
    final motion = writeFile('${docsDir.path}/motion_photos/x.mp4', 200);
    final unknown = writeFile('${docsDir.path}/album.db', 400);
    final emptyDir = Directory('${docsDir.path}/empty_leftover')..createSync();
    final unknownDir = writeFile('${docsDir.path}/unknown_dir/keep.bin', 50);
    final untouched = writeFile('${docsDir.path}/not_passed.bin', 80);
    final pending = writeFile('${uploadsDir.path}/c.jpg', 900);

    final freed = await CacheService.clearResidue([
      '${docsDir.path}/album_share_7',
      '${docsDir.path}/motion_photos',
      '${docsDir.path}/album.db',
      '${docsDir.path}/empty_leftover',
      '${docsDir.path}/unknown_dir',
      uploadsDir.path,
    ]);

    expect(freed, 500);
    expect(shareDir.existsSync(), isFalse);
    expect(motion.existsSync(), isFalse);
    expect(unknown.existsSync(), isTrue, reason: '未知文件不能删');
    expect(emptyDir.existsSync(), isFalse, reason: '空目录直接删');
    expect(unknownDir.existsSync(), isTrue, reason: '非空且名字不认识，留着');
    expect(untouched.existsSync(), isTrue, reason: '没传进来的残留不动');
    expect(pending.existsSync(), isTrue, reason: '待上传副本有自己的入口');
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
