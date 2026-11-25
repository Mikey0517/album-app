import 'dart:io';

import 'package:album_app/core/hidden_space/hidden_space_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hidden_space_test_');
    HiddenSpaceStore.overrideDirectory = tempDir;
  });

  tearDown(() async {
    HiddenSpaceStore.overrideDirectory = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<File> write(String name, List<int> bytes) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('没有索引时按目录重建，并按扩展名认出图片/视频', () async {
    await write('照片.jpg', [1, 2, 3]);
    await write('clip.mp4', [4, 5]);
    await write('report.pdf', [6]);

    final files = await HiddenSpaceStore.load();
    expect(files, hasLength(3));
    final byName = {for (final f in files) f.name: f};
    expect(byName['照片.jpg']!.isImage, isTrue);
    expect(byName['clip.mp4']!.isVideo, isTrue);
    expect(byName['report.pdf']!.canOpen, isFalse);
  });

  test('索引写回后能再读出来', () async {
    await write('a.png', [1, 2]);
    final first = await HiddenSpaceStore.load();
    await HiddenSpaceStore.saveIndex(first);
    final again = await HiddenSpaceStore.load();
    expect(again, hasLength(1));
    expect(again.first.name, 'a.png');
    expect(again.first.isImage, isTrue);
  });

  test('删除会同时删文件和索引条目', () async {
    final file = await write('b.mp4', [1]);
    final files = await HiddenSpaceStore.load();
    final remaining = await HiddenSpaceStore.delete(files.first);
    expect(remaining, isEmpty);
    expect(await file.exists(), isFalse);
  });

  test('索引里指向已删文件的条目会被丢掉', () async {
    final kept = await write('keep.jpg', [1]);
    final gone = await write('gone.jpg', [2]);
    final files = [
      HiddenFile(
        id: '1',
        name: 'keep.jpg',
        path: kept.path,
        mime: 'image/jpeg',
        size: 1,
        addedAt: DateTime.now(),
      ),
      HiddenFile(
        id: '2',
        name: 'gone.jpg',
        path: gone.path,
        mime: 'image/jpeg',
        size: 1,
        addedAt: DateTime.now(),
      ),
    ];
    await HiddenSpaceStore.saveIndex(files);
    await gone.delete();
    final loaded = await HiddenSpaceStore.load();
    expect(loaded.map((f) => f.name), ['keep.jpg']);
  });
}
