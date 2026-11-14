import '../../models/media.dart';

/// 相册详情页的类型筛选。
///
/// 状态只存在页面里，跟着当次打开结束：它是「我现在想找视频」的一次性意图，
/// 若像排序/分组那样全局持久化，下次进别的相册会莫名只剩视频，用户还得
/// 自己找回来。页内刷新、上传后仍然保留，切走再进来回到「全部」。
enum AlbumMediaFilter { all, photos, videos }

extension AlbumMediaFilterX on AlbumMediaFilter {
  String get label => switch (this) {
        AlbumMediaFilter.all => '全部',
        AlbumMediaFilter.photos => '照片',
        AlbumMediaFilter.videos => '视频',
      };

  bool matches(Media media) => switch (this) {
        AlbumMediaFilter.all => true,
        AlbumMediaFilter.photos => !media.isVideo,
        AlbumMediaFilter.videos => media.isVideo,
      };
}

/// 相册里照片/视频各有几个。筛选条上的数量始终取全量，
/// 这样切换筛选时数字不跳，用户知道自己漏掉了多少。
class AlbumMediaCounts {
  final int photos;
  final int videos;

  const AlbumMediaCounts({required this.photos, required this.videos});

  int get total => photos + videos;

  int of(AlbumMediaFilter filter) => switch (filter) {
        AlbumMediaFilter.all => total,
        AlbumMediaFilter.photos => photos,
        AlbumMediaFilter.videos => videos,
      };

  factory AlbumMediaCounts.from(List<Media> items) {
    var photos = 0;
    var videos = 0;
    for (final item in items) {
      if (item.isVideo) {
        videos++;
      } else {
        photos++;
      }
    }
    return AlbumMediaCounts(photos: photos, videos: videos);
  }
}

List<Media> filterAlbumMedia(List<Media> items, AlbumMediaFilter filter) {
  if (filter == AlbumMediaFilter.all) return items;
  return items.where(filter.matches).toList(growable: false);
}
