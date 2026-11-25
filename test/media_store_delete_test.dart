import 'package:album_app/core/media_store.dart';
import 'package:album_app/core/source_media_cleanup.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 删除前的校验：一条非法 URI 混进 createDeleteRequest 会让整批抛
/// IllegalArgumentException（"All requested items must be referenced by
/// specific ID"），所以坏的一条都不能进批。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('album/media_store');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(calls.clear);

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// 通道参数里的 items，用来断言「到底哪几条被送去了系统」。
  List<Object?> itemsOf(MethodCall call) =>
      ((call.arguments as Map)['items'] as List).cast<Object?>();

  List<Object?> methods() => calls.map((call) => call.method).toList();

  test('非法 picker / 不存在的 id / 类型不匹配：一条都不会进 deleteUris', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'resolveDeleteUris') {
        // 原生按 id 查库：第一张还在，第二张已经不在相册里了。
        return {
          'items': [
            {
              'uri': 'content://media/external/images/media/11',
              'video': false,
              'reason': null,
            },
            {'uri': null, 'video': false, 'reason': 'not_found'},
          ],
        };
      }
      return {'deleted': 1, 'failed': 0};
    });

    final result = await MediaStore.deleteSources([
      (uri: 'content://media/external/images/media/11', isVideo: false),
      (uri: 'content://media/external/images/media/12', isVideo: false),
      // 云相册的 picker URI 末尾不是媒体 id：换不成 MediaStore 单项 URI。
      (
        uri: 'content://media/picker/0/com.android.providers.media.photopicker'
            '/media/cloud-item-1',
        isVideo: false,
      ),
      // URI 说是视频、调用方说不是：两边对不上，别拿去删。
      (uri: 'content://media/external/video/media/13', isVideo: false),
    ]);

    expect(methods(), ['resolveDeleteUris', 'deleteUris']);
    // 预校验只收到形态合法的两条：非法 picker 和类型不匹配在 Dart 侧就剔掉了。
    expect(itemsOf(calls[0]), [
      {'uri': 'content://media/external/images/media/11', 'video': false},
      {'uri': 'content://media/external/images/media/12', 'video': false},
    ]);
    // 真正交给系统的只有查库确认存在的那一条。
    expect(itemsOf(calls[1]), [
      {'uri': 'content://media/external/images/media/11', 'video': false},
    ]);
    expect(result.deleted, 1);
    expect(result.failed, 3);
  });

  test('一条都不合格时连原生都不碰，一次 createDeleteRequest 都不会发生', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'deleted': 1, 'failed': 0};
    });

    final result = await MediaStore.deleteSources([
      (
        uri: 'content://media/picker/0/com.android.providers.media.photopicker'
            '/media/no-id',
        isVideo: false,
      ),
      (uri: 'file:///storage/emulated/0/DCIM/IMG_0001.jpg', isVideo: false),
      (uri: 'content://media/external/images/media/abc', isVideo: false),
    ]);

    expect(calls, isEmpty);
    expect(result.deleted, 0);
    expect(result.failed, 3);
    expect(result.reason, SourceDeleteFailure.unresolvedPicker);
    expect(
      sourceDeleteMessage(result),
      '3 项无法删除：系统没能把它们换成相册条目，请到系统相册里手动删除',
    );
  });

  test('picker URI 先换成 MediaStore 单项 URI，再用换回来的地址去删', () async {
    const picker = 'content://media/picker/0/com.android.providers.media'
        '.photopicker/media/1000000033';
    const media = 'content://media/external/images/media/1000000033';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'resolveDeleteUris') {
        return {
          'items': [
            {'uri': media, 'video': false, 'reason': null},
          ],
        };
      }
      return {'deleted': 1, 'failed': 0};
    });

    final result = await MediaStore.deleteSources([(uri: picker, isVideo: false)]);

    expect(itemsOf(calls[0]), [
      {'uri': picker, 'video': false},
    ]);
    expect(itemsOf(calls[1]), [
      {'uri': media, 'video': false},
    ]);
    expect(result.deleted, 1);
    expect(result.failed, 0);
    expect(result.reason, isNull);
  });

  test('查库说已经不存在的条目不会再送去删，文案说明真实原因', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {
        'items': [
          {'uri': null, 'video': false, 'reason': 'not_found'},
          {'uri': null, 'video': true, 'reason': 'not_found'},
        ],
      };
    });

    final result = await MediaStore.deleteSources([
      (uri: 'content://media/external/images/media/21', isVideo: false),
      (uri: 'content://media/external/video/media/22', isVideo: true),
    ]);

    expect(methods(), ['resolveDeleteUris'], reason: '一条都不能删时不该再调删除');
    expect(result.deleted, 0);
    expect(result.failed, 2);
    expect(result.reason, SourceDeleteFailure.notFound);
    expect(
      sourceDeleteMessage(result),
      '2 项无法删除：手机相册里已经找不到这些条目，请到系统相册里手动删除',
    );
  });

  test('用户在系统确认框取消：如实说原图还在，不再抛异常原文', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'resolveDeleteUris') {
        return {
          'items': [
            {
              'uri': 'content://media/external/images/media/31',
              'video': false,
              'reason': null,
            },
          ],
        };
      }
      return {'deleted': 0, 'failed': 1, 'reason': 'user_cancelled'};
    });

    final result = await MediaStore.deleteSources([
      (uri: 'content://media/external/images/media/31', isVideo: false),
    ]);

    expect(result.reason, SourceDeleteFailure.userCancelled);
    expect(sourceDeleteMessage(result), '已取消删除，手机相册里的原图还在');
  });

  test('原生没有预校验方法时退回形状校验，删除照常进行', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'resolveDeleteUris') {
        throw MissingPluginException('没有这个方法');
      }
      return {'deleted': 1, 'failed': 0};
    });

    final result = await MediaStore.deleteSources([
      (uri: 'content://media/external/images/media/41', isVideo: false),
    ]);

    expect(methods(), ['resolveDeleteUris', 'deleteUris']);
    expect(result.deleted, 1);
    expect(result.failed, 0);
  });

  test('原生说这条不能删时不会把原地址塞回去', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'resolveDeleteUris') {
        // 没给 uri、也没给原因码：不能退回原 URI（那正是会整批抛异常的地址）。
        return {
          'items': [
            {'uri': null, 'video': false, 'reason': null},
            {
              'uri': 'content://media/external/images/media/42',
              'video': false,
              'reason': null,
            },
          ],
        };
      }
      return {'deleted': 1, 'failed': 0};
    });

    final result = await MediaStore.deleteSources([
      (uri: 'content://media/external/images/media/41', isVideo: false),
      (uri: 'content://media/external/images/media/42', isVideo: false),
    ]);

    expect(itemsOf(calls[1]), [
      {'uri': 'content://media/external/images/media/42', 'video': false},
    ]);
    expect(result.deleted, 1);
    expect(result.failed, 1);
  });

  group('形状自检', () {
    test('合法的 MediaStore 单项 URI 放行', () {
      expect(
        sourceTargetRejection(
          (uri: 'content://media/external/images/media/7', isVideo: false),
        ),
        isNull,
      );
      expect(
        sourceTargetRejection(
          (uri: 'content://media/external_primary/video/media/7', isVideo: true),
        ),
        isNull,
      );
      expect(
        sourceTargetRejection(
          (
            uri: 'content://media/picker/0/com.android.providers.media'
                '.photopicker/media/7',
            isVideo: true,
          ),
        ),
        isNull,
      );
    });


    test('厂商选择器给的副本 URI 放行，交给原生按 EXIF 回查原图', () {
      expect(
        sourceTargetRejection((
          uri: 'content://com.hyper.photopicker.fileProvider/cache/1795601712401.jpg',
          isVideo: false,
        )),
        isNull,
      );
    });

    test('DocumentsUI 回退的 document URI 也放行（没有相册选择器的机型）', () {
      expect(
        sourceTargetRejection((
          uri: 'content://com.android.providers.media.documents'
              '/document/image%3A7',
          isVideo: false,
        )),
        isNull,
      );
      expect(
        sourceTargetRejection((
          uri: 'content://com.android.providers.media.documents'
              '/document/video%3A7',
          isVideo: true,
        )),
        isNull,
      );
      // document id 说图片、调用方说是视频：对不上，交给剔除。
      expect(
        sourceTargetRejection((
          uri: 'content://com.android.providers.media.documents'
              '/document/image%3A7',
          isVideo: true,
        )),
        SourceDeleteFailure.typeMismatch,
      );
      // document id 不是 image/video 集合：系统删不了。
      expect(
        sourceTargetRejection((
          uri: 'content://com.android.providers.media.documents'
              '/document/audio%3A7',
          isVideo: false,
        )),
        SourceDeleteFailure.unsupported,
      );
    });

    test('picker_get 变体也认（个别 ROM 的 Photo Picker）', () {
      expect(
        sourceTargetRejection((
          uri: 'content://media/picker_get/0/com.android.providers.media'
              '.photopicker/media/7',
          isVideo: false,
        )),
        isNull,
      );
    });

    test('别的形态一律剔除', () {
      // 没有媒体 id 的 picker URI
      expect(
        sourceTargetRejection(
          (
            uri: 'content://media/picker/0/com.android.providers.media'
                '.photopicker/media/xyz',
            isVideo: false,
          ),
        ),
        SourceDeleteFailure.unresolvedPicker,
      );
      // 集合 URI（缺 id）
      expect(
        sourceTargetRejection(
          (uri: 'content://media/external/images/media', isVideo: false),
        ),
        SourceDeleteFailure.unsupported,
      );
      // document 路径但不带 image:/video: 的 id：系统删不了
      expect(
        sourceTargetRejection(
          (uri: 'content://com.android.providers.media.documents/document/1',
              isVideo: false),
        ),
        SourceDeleteFailure.unsupported,
      );
      // audio / file 集合系统不认
      expect(
        sourceTargetRejection(
          (uri: 'content://media/external/audio/media/7', isVideo: false),
        ),
        SourceDeleteFailure.unsupported,
      );
      // 类型和集合对不上
      expect(
        sourceTargetRejection(
          (uri: 'content://media/external/images/media/7', isVideo: true),
        ),
        SourceDeleteFailure.typeMismatch,
      );
    });
  });
}
