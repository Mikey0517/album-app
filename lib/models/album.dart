class Album {
  final int id;
  final String title;
  final String? coverThumb;
  final int mediaCount;
  final DateTime createdAt;

  /// family（家庭公共） / private（私人，仅创建者与被分享者可见）
  final String visibility;
  final int? ownerId;
  final String? ownerNickname;
  final bool isOwner;
  final int shareCount;

  /// family / owner / viewer（只读）/ editor（可写）/ admin（管理员）
  final String myRole;

  const Album({
    required this.id,
    required this.title,
    required this.coverThumb,
    required this.mediaCount,
    required this.createdAt,
    this.visibility = 'family',
    this.ownerId,
    this.ownerNickname,
    this.isOwner = true,
    this.shareCount = 0,
    this.myRole = 'family',
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '',
      coverThumb: json['cover_thumb'] as String?,
      mediaCount: (json['media_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      visibility: json['visibility'] as String? ?? 'family',
      ownerId: (json['owner_id'] as num?)?.toInt(),
      ownerNickname: json['owner_nickname'] as String?,
      isOwner: json['is_owner'] as bool? ?? true,
      shareCount: (json['share_count'] as num?)?.toInt() ?? 0,
      myRole: json['my_role'] as String? ?? 'family',
    );
  }

  Album copyWith({String? title, String? coverThumb, int? mediaCount}) {
    return Album(
      id: id,
      title: title ?? this.title,
      coverThumb: coverThumb ?? this.coverThumb,
      mediaCount: mediaCount ?? this.mediaCount,
      createdAt: createdAt,
      visibility: visibility,
      ownerId: ownerId,
      ownerNickname: ownerNickname,
      isOwner: isOwner,
      shareCount: shareCount,
      myRole: myRole,
    );
  }

  bool get isPrivate => visibility == 'private';

  /// 能上传/删除照片：家庭相册所有人；私人相册的创建者、管理员、可写。
  bool get canEditMedia =>
      !isPrivate ||
      myRole == 'owner' ||
      myRole == 'admin' ||
      myRole == 'editor';

  /// 能改相册本身（改名/封面/删相册）：创建者与管理员。
  bool get canManage => !isPrivate || myRole == 'owner' || myRole == 'admin';

  String get ownerLabel =>
      (ownerNickname == null || ownerNickname!.isEmpty) ? '家人' : ownerNickname!;

  String get roleLabel {
    return switch (myRole) {
      'owner' => '我创建的',
      'editor' => '可写',
      'admin' => '管理员',
      'viewer' => '只读',
      _ => '家庭相册',
    };
  }
}
