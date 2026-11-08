import 'package:album_app/models/album.dart';
import 'package:flutter_test/flutter_test.dart';

Album _album({
  String visibility = 'family',
  String myRole = 'family',
  int? ownerId = 1,
  String? ownerNickname = '爸爸',
  bool isOwner = true,
  int shareCount = 0,
}) {
  return Album(
    id: 1,
    title: '测试',
    coverThumb: null,
    mediaCount: 3,
    createdAt: DateTime(2026, 1, 1),
    visibility: visibility,
    ownerId: ownerId,
    ownerNickname: ownerNickname,
    isOwner: isOwner,
    shareCount: shareCount,
    myRole: myRole,
  );
}

void main() {
  test('家庭相册所有人可编辑可管理', () {
    final album = _album();
    expect(album.isPrivate, isFalse);
    expect(album.canEditMedia, isTrue);
    expect(album.canManage, isTrue);
    expect(album.roleLabel, '家庭相册');
  });

  test('自己创建的私人相册可编辑可管理', () {
    final album = _album(visibility: 'private', myRole: 'owner');
    expect(album.isPrivate, isTrue);
    expect(album.canEditMedia, isTrue);
    expect(album.canManage, isTrue);
    expect(album.roleLabel, '我创建的');
  });

  test('只读分享：只能看', () {
    final album = _album(
      visibility: 'private',
      myRole: 'viewer',
      isOwner: false,
      ownerNickname: '妈妈',
    );
    expect(album.canEditMedia, isFalse);
    expect(album.canManage, isFalse);
    expect(album.roleLabel, '只读');
  });

  test('可写分享：能传/删照片，不能删相册', () {
    final album = _album(
      visibility: 'private',
      myRole: 'editor',
      isOwner: false,
    );
    expect(album.canEditMedia, isTrue);
    expect(album.canManage, isFalse);
    expect(album.roleLabel, '可写');
  });

  test('管理员分享：能传/删照片，也能删相册', () {
    final album = _album(
      visibility: 'private',
      myRole: 'admin',
      isOwner: false,
    );
    expect(album.canEditMedia, isTrue);
    expect(album.canManage, isTrue);
    expect(album.roleLabel, '管理员');
  });
}
