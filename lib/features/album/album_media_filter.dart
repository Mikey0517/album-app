import '../../models/media.dart';

/// 相册详情页的类型筛选。
///
/// 状态只存在页面里，跟着当次打开结束：它是「我现在想找视频」的一次性意图，
/// 若像排序/分组那样全局持久化，下次进别的相册会莫名只剩视频，用户还得
/// 自己找回来。页内刷新、上传后仍然保留，切走再进来回到「全部」。
///
/// 枚举顺序就是筛选条上的顺序（全部 / 照片 / 动态图片 / 视频）：
/// [AlbumMediaFilterBar] 直接按 values 摆，文案、数量、选中态都不会另起一套。
enum AlbumMediaFilter { all, photos, livePhotos, videos }

extension AlbumMediaFilterX on AlbumMediaFilter {
  String get label => switch (this) {
        AlbumMediaFilter.all => '全部',
        AlbumMediaFilter.photos => '照片',
        AlbumMediaFilter.livePhotos => '动态图片',
        AlbumMediaFilter.videos => '视频',
      };

  /// 这一类的名字，空状态用它拼「还没有…」/「筛选后没有…」。
  String get noun => switch (this) {
        AlbumMediaFilter.all => '内容',
        AlbumMediaFilter.photos => '照片',
        AlbumMediaFilter.livePhotos => '动态图片',
        AlbumMediaFilter.videos => '视频',
      };

  /// 「动态图片」= 图片且有服务端提取出来的动态视频；「照片」只剩普通静态照片，
  /// 否则动态图片会被数两次，「全部」就对不上照片 + 动态图片 + 视频。
  bool matches(Media media) => switch (this) {
        AlbumMediaFilter.all => true,
        AlbumMediaFilter.photos => !media.isVideo && !media.isLivePhoto,
        AlbumMediaFilter.livePhotos => !media.isVideo && media.isLivePhoto,
        AlbumMediaFilter.videos => media.isVideo,
      };
}

/// 相册里照片/动态图片/视频各有几个。筛选条上的数量始终取全量，
/// 这样切换筛选时数字不跳，用户知道自己漏掉了多少。
class AlbumMediaCounts {
  /// 普通静态照片（不含动态图片）。
  final int photos;

  /// 动态图片（图片 + 动态视频）。
  final int livePhotos;
  final int videos;

  const AlbumMediaCounts({
    required this.photos,
    required this.livePhotos,
    required this.videos,
  });

  /// 照片总数，含动态图片：页头那句「N 张照片」用这个——
  /// 动态图片也是照片，页头不必拆成三项。
  int get images => photos + livePhotos;

  int get total => photos + livePhotos + videos;

  int of(AlbumMediaFilter filter) => switch (filter) {
        AlbumMediaFilter.all => total,
        AlbumMediaFilter.photos => photos,
        AlbumMediaFilter.livePhotos => livePhotos,
        AlbumMediaFilter.videos => videos,
      };

  factory AlbumMediaCounts.from(List<Media> items) {
    var photos = 0;
    var livePhotos = 0;
    var videos = 0;
    for (final item in items) {
      if (item.isVideo) {
        videos++;
      } else if (item.isLivePhoto) {
        livePhotos++;
      } else {
        photos++;
      }
    }
    return AlbumMediaCounts(
      photos: photos,
      livePhotos: livePhotos,
      videos: videos,
    );
  }
}

List<Media> filterAlbumMedia(List<Media> items, AlbumMediaFilter filter) {
  if (filter == AlbumMediaFilter.all) return items;
  return items.where(filter.matches).toList(growable: false);
}
