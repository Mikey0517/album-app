import 'media.dart';

class Post {
  final int id;
  final int authorId;
  final String authorNickname;
  final String? content;
  final DateTime postedAt;

  /// 最后一次编辑时间；null 表示发布后没改过（服务端 edited_at 为空）。
  final DateTime? editedAt;
  final List<Media> medias;

  const Post({
    required this.id,
    required this.authorId,
    required this.authorNickname,
    required this.content,
    required this.postedAt,
    this.editedAt,
    required this.medias,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    final rawMedias = json['medias'] as List<dynamic>? ?? const [];
    return Post(
      id: (json['id'] as num).toInt(),
      authorId: (json['author_id'] as num).toInt(),
      authorNickname: json['author_nickname'] as String? ?? '',
      content: json['content'] as String?,
      postedAt: DateTime.tryParse(json['posted_at'] as String? ?? '') ??
          DateTime.now(),
      editedAt: DateTime.tryParse(json['edited_at'] as String? ?? ''),
      medias: rawMedias
          .whereType<Map<String, dynamic>>()
          .map(Media.fromJson)
          .toList(),
    );
  }
}
