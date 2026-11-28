import 'dart:math';

import '../api/album_api.dart';
import '../api/gallery_api.dart';
import '../models/album.dart';
import '../models/media.dart';
import '../models/paged.dart';

/// 随机回顾的一次结果：整个相册的媒体列表 + 随机命中的下标。
///
/// 打开大屏时必须把 [items] 整份交给浏览页——底部缩略图条要显示「这个相册」
/// 的列表，而不是只有随机到的那一张。
class RandomMediaPick {
  final List<Media> items;
  final int index;

  const RandomMediaPick({required this.items, required this.index});
}

/// 「随机回顾」：从我有权限的相册里随机挑一个媒体。
///
/// 来源 = 所有能访问到的相册 + 朋友圈相册（服务端聚合视图）。隐藏空间是本地
/// 私有文件、不在任何相册接口里，天然不会被随机到。
///
/// 挑法：来源按「媒体数量」加权（大相册被抽中的概率更高，更接近「随机一张
/// 照片」），选中后拉该来源的完整列表再随机一个下标；某个来源加载失败就换
/// 下一个，最多试 [attempts] 次。
class RandomMediaService {
  RandomMediaService._();

  static const int attempts = 4;

  static Future<RandomMediaPick?> pick({
    Random? random,
    Future<List<Album>> Function()? albumList,
    Future<AlbumDetail> Function(int albumId)? albumDetail,
    Future<Paged<Media>> Function()? feed,
    int? maxAttempts,
  }) async {
    final rng = random ?? Random();
    final loadAlbums = albumList ?? AlbumApi.list;
    final loadDetail = albumDetail ?? AlbumApi.detail;
    final loadFeed = feed ?? (() => GalleryApi.feed());
    final limit = maxAttempts ?? attempts;
    final List<({int weight, Future<List<Media>> Function() load})> sources = [];

    try {
      final albums = await loadAlbums();
      for (final album in albums) {
        sources.add((
          weight: max(album.mediaCount, 1),
          load: () async => (await loadDetail(album.id)).items,
        ));
      }
    } catch (_) {
      // 相册列表拿不到就只随机朋友圈相册。
    }

    // 朋友圈相册：没有总数，按「普通相册的平均量」估一个权重。
    final albumWeight = sources.isEmpty
        ? 0
        : sources.fold<int>(0, (sum, s) => sum + s.weight) ~/ sources.length;
    sources.add((
      weight: max(albumWeight, 1),
      load: () async => (await loadFeed()).items,
    ));

    final total = sources.fold<int>(0, (sum, s) => sum + s.weight);
    for (var attempt = 0; attempt < limit; attempt++) {
      final target = rng.nextInt(total);
      var cursor = 0;
      var chosen = sources.last;
      for (final source in sources) {
        cursor += source.weight;
        if (target < cursor) {
          chosen = source;
          break;
        }
      }
      try {
        final items = await chosen.load();
        if (items.isEmpty) continue;
        return RandomMediaPick(
          items: items,
          index: rng.nextInt(items.length),
        );
      } catch (_) {
        // 换一个来源再试。
      }
    }
    return null;
  }
}
