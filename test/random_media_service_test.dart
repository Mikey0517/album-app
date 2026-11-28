import 'dart:math';

import 'package:album_app/api/album_api.dart';
import 'package:album_app/core/random_media_service.dart';
import 'package:album_app/models/album.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/models/paged.dart';
import 'package:flutter_test/flutter_test.dart';

Media _media(int id) => Media(
      id: id,
      type: 'image',
      thumbUrl: null,
      url: '/api/media/$id/display',
      width: 100,
      height: 100,
      durationMs: null,
      takenAt: DateTime(2026, 1, 1),
      createdAt: DateTime(2026, 1, 1),
      postId: null,
    );

Album _album(int id, {int count = 3}) => Album(
      id: id,
      title: '相册$id',
      coverThumb: null,
      mediaCount: count,
      createdAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('随机到一个相册里的某张：返回整个列表和合法下标', () async {
    final albums = [_album(1, count: 5), _album(2, count: 1)];
    final detail = <int, List<Media>>{
      1: [for (var i = 0; i < 5; i++) _media(100 + i)],
      2: [_media(200)],
    };
    final pick = await RandomMediaService.pick(
      random: Random(7),
      albumList: () async => albums,
      albumDetail: (id) async => AlbumDetail(
        album: albums.firstWhere((a) => a.id == id),
        items: detail[id]!,
      ),
      feed: () async => Paged(items: [_media(300)], nextCursor: null),
    );
    expect(pick, isNotNull);
    expect(pick!.index, inInclusiveRange(0, pick.items.length - 1));
    expect(pick.items, isNotEmpty);
  });

  test('相册详情加载失败时换下一个来源', () async {
    final albums = [_album(1), _album(2)];
    final pick = await RandomMediaService.pick(
      random: Random(3),
      albumList: () async => albums,
      albumDetail: (id) async {
        if (id == 1) throw Exception('boom');
        return AlbumDetail(album: albums[1], items: [_media(11), _media(12)]);
      },
      feed: () async => Paged(items: [_media(99)], nextCursor: null),
    );
    expect(pick, isNotNull);
    expect(pick!.items, isNotEmpty);
  });

  test('所有来源都失败时返回 null', () async {
    final pick = await RandomMediaService.pick(
      random: Random(1),
      albumList: () async => [_album(1)],
      albumDetail: (_) async => throw Exception('boom'),
      feed: () async => throw Exception('boom'),
      maxAttempts: 3,
    );
    expect(pick, isNull);
  });

  test('没有相册入口时只随机朋友圈相册', () async {
    final pick = await RandomMediaService.pick(
      random: Random(2),
      albumList: () async => const [],
      feed: () async =>
          Paged(items: [_media(1), _media(2), _media(3)], nextCursor: null),
    );
    expect(pick, isNotNull);
    expect(pick!.items.length, 3);
    expect(pick.index, inInclusiveRange(0, 2));
  });

  test('空了的朋友圈不返回结果', () async {
    final pick = await RandomMediaService.pick(
      albumList: () async => const [],
      feed: () async => const Paged<Media>(items: [], nextCursor: null),
    );
    expect(pick, isNull);
  });
}
