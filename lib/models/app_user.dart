class AppUser {
  final int id;
  final String userId;
  final String nickname;

  const AppUser({
    required this.id,
    required this.userId,
    required this.nickname,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] as num).toInt(),
      userId: json['user_id'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'nickname': nickname,
      };

  String get initial => nickname.isEmpty ? '?' : nickname.substring(0, 1);
}
