import '../../models/media.dart';

/// 相册详情页的类型筛选。
///
/// 状态只存在页面里，跟着当次打开结束：它是「我现在想找视频」的一次性意图，
/// 若像排序/分组那样全局持久化，下次进别的相册会莫名只剩视频，用户还得
/// 自己找回来。页内刷新、上传后仍然保留，切走再进来回到「全部」。
///
/// 枚举顺序就是筛选条上的顺序（全部 / 照片 / 动态照片 / 视频）：
/// [AlbumMediaFilterBar] 直接按 values 摆，文案、数量、选中态都不会另起一套。
enum AlbumMediaFilter { all, photos, livePhotos, videos }

extension AlbumMediaFilterX on AlbumMediaFilter {
  String get label => switch (this) {
        AlbumMediaFilter.all => '全部',
        AlbumMediaFilter.photos => '照片',
        AlbumMediaFilter.livePhotos => '动态照片',
        AlbumMediaFilter.videos => '视频',
      };

  /// 这一类的名字，空状态用它拼「还没有…」/「筛选后没有…」。
  String get noun => switch (this) {
        AlbumMediaFilter.all => '内容',
        AlbumMediaFilter.photos => '照片',
        AlbumMediaFilter.livePhotos => '动态照片',
        AlbumMediaFilter.videos => '视频',
      };

  /// 四类的关系是**包含**，不是互斥：
  /// - 全部 = 所有媒体；
  /// - 照片 = 所有图片（含动态照片）；
  /// - 动态照片 = 图片中带实况的那部分，是「照片」的子集；
  /// - 视频 = 所有视频。
  ///
  /// 所以「照片」不再排掉动态照片（旧语义会排掉，照片与动态照片互斥）；
  /// 数量上 照片 = 普通照片 + 动态照片，「全部」= 照片 + 视频——动态照片
  /// 已经算在照片里，不能加第二次。
  bool matches(Media media) => switch (this) {
        AlbumMediaFilter.all => true,
        AlbumMediaFilter.photos => !media.isVideo,
        AlbumMediaFilter.livePhotos => !media.isVideo && media.isLivePhoto,
        AlbumMediaFilter.videos => media.isVideo,
      };
}

/// 相册里普通照片 / 动态照片 / 视频各有几个。筛选条上的数量始终取全量，
/// 这样切换筛选时数字不跳，用户知道自己漏掉了多少。
///
/// 口径（与 [AlbumMediaFilterX.matches] 一致）：
/// - [photos] = 所有图片 = [stillPhotos] + [livePhotos]（含动态照片）；
/// - [livePhotos] 只是照片的子集，[total] 里不能再加它；
/// - [total] = [photos] + [videos]。
class AlbumMediaCounts {
  /// 普通照片：图片、不带实况。是照片的一部分。
  final int stillPhotos;

  /// 动态照片：图片 + 服务端提取出来的实况视频。也是照片的一部分。
  final int livePhotos;
  final int videos;

  const AlbumMediaCounts({
    required this.stillPhotos,
    required this.livePhotos,
    required this.videos,
  });

  /// 照片 = 所有图片（含动态照片）。页头那句「N 张照片」用这个，
  /// 筛选条上「照片」的角标也是这个：两处一个口径。
  int get photos => stillPhotos + livePhotos;

  /// 全部 = 照片 + 视频。动态照片已经算在照片里，不能加第二次。
  int get total => photos + videos;

  int of(AlbumMediaFilter filter) => switch (filter) {
        AlbumMediaFilter.all => total,
        AlbumMediaFilter.photos => photos,
        AlbumMediaFilter.livePhotos => livePhotos,
        AlbumMediaFilter.videos => videos,
      };

  factory AlbumMediaCounts.from(List<Media> items) {
    var stillPhotos = 0;
    var livePhotos = 0;
    var videos = 0;
    for (final item in items) {
      if (item.isVideo) {
        videos++;
      } else if (item.isLivePhoto) {
        livePhotos++;
      } else {
        stillPhotos++;
      }
    }
    return AlbumMediaCounts(
      stillPhotos: stillPhotos,
      livePhotos: livePhotos,
      videos: videos,
    );
  }
}

List<Media> filterAlbumMedia(List<Media> items, AlbumMediaFilter filter) {
  if (filter == AlbumMediaFilter.all) return items;
  return items.where(filter.matches).toList(growable: false);
}
