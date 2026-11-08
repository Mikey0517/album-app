import 'media.dart';

class Post {
  final int id;
  final int authorId;
  final String authorNickname;
  final String? content;
  final DateTime postedAt;
  final List<Media> medias;

  const Post({
    required this.id,
    required this.authorId,
    required this.authorNickname,
    required this.content,
    required this.postedAt,
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
      medias: rawMedias
          .whereType<Map<String, dynamic>>()
          .map(Media.fromJson)
          .toList(),
    );
  }
}
