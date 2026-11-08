class AlbumShare {
  final int id;
  final String userId;
  final String nickname;

  /// viewer（只读）/ editor（可写）/ admin（管理员）
  final String role;

  const AlbumShare({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.role,
  });

  factory AlbumShare.fromJson(Map<String, dynamic> json) {
    return AlbumShare(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: json['user_id'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      role: json['role'] as String? ?? 'viewer',
    );
  }

  String get label => nickname.isEmpty ? userId : nickname;

  String get initial {
    final source = label.trim();
    return source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
  }

  static String roleLabelOf(String role) {
    return switch (role) {
      'editor' => '可写',
      'admin' => '管理员',
      _ => '只读',
    };
  }
}
