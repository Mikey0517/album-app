import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:album_app/core/api_client.dart';
import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/formatters.dart';
import 'package:album_app/core/media_picker.dart';
import 'package:album_app/features/feed/compose_page.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/models/post.dart';
import 'package:album_app/widgets/album_thumb.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 已发布动态编辑的「媒体」部分：
// 1. 编辑页媒体可删、可从相册新增、可拖动排序；
// 2. 保存时先上传新增媒体拿 id，再 PUT 提交最终顺序（media_ids）；
// 3. 编辑不改发布时间：列表里的时间还是发布日期，位置也不动；
// 4. 取消编辑不产生任何上传。

const AppUser _me = AppUser(id: 1, userId: 'me', nickname: '我');

Map<String, dynamic> _mediaJson(int id, {int? postId = 7}) => {
      'id': id,
      'type': 'image',
      'thumb_url': null,
      'url': '',
      'width': 100,
      'height': 100,
      'taken_at': '2026-01-01T10:00:00',
      'created_at': '2026-01-01T10:00:00',
      'post_id': postId,
      'thumb_failed': true,
      'favorite': false,
    };

Map<String, dynamic> _postJson({
  int id = 7,
  String? content = '旧的正文',
  String postedAt = '2026-01-01T10:00:00',
  String? editedAt,
  List<int> mediaIds = const [101, 102],
}) =>
    {
      'id': id,
      'author_id': 1,
      'author_nickname': '我',
      'content': content,
      'posted_at': postedAt,
      'edited_at': editedAt,
      'medias': [for (final mediaId in mediaIds) _mediaJson(mediaId)],
    };

/// 卡片直接吃模型：媒体用 thumbFailed 占位，测试不碰网络。
Post _post({
  int id = 7,
  String? content = '旧的正文',
  DateTime? postedAt,
  List<int> mediaIds = const [101, 102],
}) {
  return Post(
    id: id,
    authorId: 1,
    authorNickname: '我',
    content: content,
    postedAt: postedAt ?? DateTime(2026, 1, 1, 10),
    editedAt: null,
    medias: [
      for (final mediaId in mediaIds)
        Media(
          id: mediaId,
          type: 'image',
          thumbUrl: null,
          url: '',
          width: 100,
          height: 100,
          durationMs: null,
          takenAt: DateTime(2026, 1, 1, 10),
          createdAt: DateTime(2026, 1, 1, 10),
          postId: id,
          thumbFailed: true,
        ),
    ],
  );
}

ResponseBody _jsonBody(Object body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class _RouteFake implements HttpClientAdapter {
  _RouteFake(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  List<String> get calls => requests
      .map((request) => [request.method, request.path].join(' '))
      .toList(growable: false);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

_RouteFake _installFake(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = ApiClient.dio;
  final original = dio.httpClientAdapter;
  final options = dio.options;
  final connect = options.connectTimeout;
  final receive = options.receiveTimeout;
  final send = options.sendTimeout;

  final fake = _RouteFake(handler);
  dio.httpClientAdapter = fake;
  options
    ..connectTimeout = null
    ..receiveTimeout = null
    ..sendTimeout = null;

  addTearDown(() {
    dio.httpClientAdapter = original;
    options
      ..connectTimeout = connect
      ..receiveTimeout = receive
      ..sendTimeout = send;
  });
  return fake;
}

Widget _host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

Widget _cardHost(PostCard card) =>
    _host(Scaffold(body: ListView(children: [card])));

/// 编辑页媒体格子里已发布媒体的顺序（拖动浮层只在拖动中出现，不影响这里）。
List<int> _thumbIds(WidgetTester tester) =>
    _thumbIdsIn(tester, find.byType(AlbumThumb));

/// 某个范围内的缩略图顺序：朋友圈里多条动态都有缩略图时用它只看一条。
List<int> _thumbIdsIn(WidgetTester tester, Finder scope) => tester
    .widgetList<AlbumThumb>(scope)
    .map((thumb) => thumb.media.id)
    .toList(growable: false);

Future<void> _openEdit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('编辑'));
  await tester.pumpAndSettle();
}

/// 点保存。上传要读本地文件（真实 IO），得放到真实事件循环里跑完。
Future<void> _tapSave(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

Finder _tileCloseIcon() => find.descendant(
      of: find.byType(GridView),
      matching: find.byIcon(Icons.close),
    );

/// 点加号选媒体。选中的图片会走一轮真实文件读取（动态照片探测），
/// 必须在真实事件循环里跑完再 pump，否则回调还停在 await 上。
Future<void> _tapAddMedia(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byIcon(Icons.add));
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CurrentUser.notifier.value = _me;
    tempDir = Directory.systemTemp.createTempSync('album_edit_media');
  });

  tearDown(() {
    CurrentUser.notifier.value = null;
    ComposePage.pickMediaFiles = pickMultipleMediaFiles;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  void sizePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 让「选图」返回一个本地文件，测试不碰系统相册通道。
  File mockPickedFile({String name = 'new.jpg'}) {
    final path = [tempDir.path, name].join('/');
    final file = File(path)
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xDB, 0, 0, 0, 0, 0xFF, 0xD9]);
    ComposePage.pickMediaFiles = ({int limit = 9}) async => PickedMediaResult(
          items: [
            PickedMediaFile(
              file: XFile(path, name: name, mimeType: 'image/jpeg'),
            ),
          ],
        );
    return file;
  }

  testWidgets('编辑页可以删除已有媒体，保存只提交保留的那张', (tester) async {
    sizePhone(tester);
    final fake = _installFake((options) {
      if (options.method == 'PUT') {
        return _jsonBody(_postJson(
          editedAt: '2026-01-02T09:00:00',
          mediaIds: const [102],
        ));
      }
      return _jsonBody(_postJson());
    });

    Post? edited;
    await tester.pumpWidget(
      _cardHost(PostCard(
        post: _post(),
        onOpenMedia: (_, __) {},
        onDeleted: () {},
        onEdited: (updated) => edited = updated,
      )),
    );
    await tester.pump();
    await _openEdit(tester);

    expect(find.byType(ComposePage), findsOneWidget);
    expect(_thumbIds(tester), [101, 102], reason: '媒体按已发布顺序进入编辑页');
    // 编辑页媒体可增删：有加号，每张图上有移除角标。
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(_tileCloseIcon(), findsNWidgets(2));

    await tester.tap(_tileCloseIcon().first);
    await tester.pumpAndSettle();
    expect(_thumbIds(tester), [102], reason: '删掉的那张从编辑页消失');

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    final puts = fake.requests.where((request) => request.method == 'PUT').toList();
    expect(puts, hasLength(1));
    expect(puts.single.path, '/api/posts/7');
    expect(puts.single.data, {
      'content': '旧的正文',
      'media_ids': [102],
    });
    expect(find.byType(ComposePage), findsNothing);
    expect(edited, isNotNull);
    expect(edited!.medias.map((media) => media.id).toList(), [102]);
    expect(edited!.postedAt, DateTime(2026, 1, 1, 10), reason: '编辑不改发布时间');
  });

  testWidgets('编辑页可以从相册新增媒体：先上传拿 id，再按顺序提交', (tester) async {
    sizePhone(tester);
    mockPickedFile();
    final fake = _installFake((options) {
      if (options.path == '/api/posts/media') {
        return _jsonBody({
          'items': [_mediaJson(900, postId: null)],
        });
      }
      if (options.method == 'PUT') {
        return _jsonBody(_postJson(
          editedAt: '2026-01-02T09:00:00',
          mediaIds: const [101, 900],
        ));
      }
      return _jsonBody(_postJson(mediaIds: const [101]));
    });

    Post? edited;
    await tester.pumpWidget(
      _cardHost(PostCard(
        post: _post(mediaIds: const [101]),
        onOpenMedia: (_, __) {},
        onDeleted: () {},
        onEdited: (updated) => edited = updated,
      )),
    );
    await tester.pump();
    await _openEdit(tester);

    expect(_thumbIds(tester), [101]);

    await _tapAddMedia(tester);

    // 新选的追加在末尾：还没点保存，所以一次 PUT 都还没有。
    expect(_thumbIds(tester), [101], reason: '本地新媒体还不是服务端媒体');
    expect(fake.requests.where((request) => request.method == 'PUT'), isEmpty);

    await _tapSave(tester);

    expect(fake.calls, ['POST /api/posts/media', 'PUT /api/posts/7'],
        reason: '先上传拿到 id，再提交最终顺序');
    final put = fake.requests.firstWhere((request) => request.method == 'PUT');
    expect(put.data, {
      'content': '旧的正文',
      'media_ids': [101, 900],
    });
    expect(edited!.medias.map((media) => media.id).toList(), [101, 900]);
  });

  testWidgets('编辑页可以拖动改变媒体顺序，保存的 media_ids 跟着变', (tester) async {
    sizePhone(tester);
    final fake = _installFake((options) {
      if (options.method == 'PUT') {
        return _jsonBody(_postJson(
          editedAt: '2026-01-02T09:00:00',
          mediaIds: const [102, 101],
        ));
      }
      return _jsonBody(_postJson());
    });

    await tester.pumpWidget(
      _cardHost(PostCard(
        post: _post(),
        onOpenMedia: (_, __) {},
        onDeleted: () {},
        onEdited: (_) {},
      )),
    );
    await tester.pump();
    await _openEdit(tester);

    expect(_thumbIds(tester), [101, 102]);

    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(AlbumThumb).first));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
    await gesture.moveTo(tester.getCenter(find.byType(AlbumThumb).at(1)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_thumbIds(tester), [102, 101], reason: '长按拖动把第一张挪到后面');

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    final put = fake.requests.firstWhere((request) => request.method == 'PUT');
    expect(put.data, {
      'content': '旧的正文',
      'media_ids': [102, 101],
    });
  });

  testWidgets('取消编辑不产生任何上传', (tester) async {
    sizePhone(tester);
    mockPickedFile();
    final fake =
        _installFake((_) => _jsonBody(_postJson(mediaIds: const [101])));

    await tester.pumpWidget(
      _cardHost(PostCard(
        post: _post(mediaIds: const [101]),
        onOpenMedia: (_, __) {},
        onDeleted: () {},
        onEdited: (_) {},
      )),
    );
    await tester.pump();
    await _openEdit(tester);

    await _tapAddMedia(tester);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('放弃'), findsOneWidget);
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();

    expect(fake.requests.where((request) => request.path.contains('/api/posts/media')),
        isEmpty,
        reason: '只有点保存才上传，取消不会留下孤儿文件');
    expect(find.byType(ComposePage), findsNothing);
  });

  testWidgets('保存失败后关闭页面会清掉已上传的临时媒体', (tester) async {
    sizePhone(tester);
    mockPickedFile();
    final fake = _installFake((options) {
      if (options.path == '/api/posts/media') {
        return _jsonBody({
          'items': [_mediaJson(900, postId: null)],
        });
      }
      if (options.method == 'PUT') {
        return _jsonBody({'detail': '服务器错误'}, status: 500);
      }
      return _jsonBody(_postJson(mediaIds: const [101]));
    });

    await tester.pumpWidget(
      _cardHost(PostCard(
        post: _post(mediaIds: const [101]),
        onOpenMedia: (_, __) {},
        onDeleted: () {},
        onEdited: (_) {},
      )),
    );
    await tester.pump();
    await _openEdit(tester);

    await _tapAddMedia(tester);
    await _tapSave(tester);

    expect(find.byType(ComposePage), findsOneWidget, reason: '保存失败留在编辑页');
    expect(fake.calls, contains('POST /api/posts/media'));

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();

    expect(fake.calls, contains('DELETE /api/posts/media/900'),
        reason: '放弃时把已上传但没挂上的临时媒体删掉');
  });

  testWidgets('保存后朋友圈列表媒体顺序正确、发布时间不变、位置不动', (tester) async {
    sizePhone(tester);
    final fake = _installFake((options) {
      if (options.method == 'PUT') {
        return _jsonBody(_postJson(
          editedAt: '2026-01-02T09:00:00',
          mediaIds: const [102],
        ));
      }
      return _jsonBody({
        'items': [
          _postJson(),
          _postJson(
            id: 8,
            content: '第二条正文',
            postedAt: '2025-12-31T09:00:00',
            mediaIds: const [201],
          ),
        ],
        'next_cursor': null,
      });
    });

    await tester.pumpWidget(_host(const FeedPage()));
    await tester.pumpAndSettle();

    final postedLabel = formatPostTime(DateTime(2026, 1, 1, 10));
    expect(find.text(postedLabel), findsOneWidget, reason: '发布时间显示在卡片头部');
    final firstBefore = tester.getTopLeft(find.text('旧的正文')).dy;
    final secondBefore = tester.getTopLeft(find.text('第二条正文')).dy;
    expect(firstBefore, lessThan(secondBefore));

    await _openEdit(tester);
    await tester.tap(_tileCloseIcon().first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    // 媒体换成保留的那一张，顺序就是保存时提交的顺序。
    expect(
      _thumbIdsIn(
        tester,
        find.descendant(
          of: find.byType(PostCard).first,
          matching: find.byType(AlbumThumb),
        ),
      ),
      [102],
    );
    // 发布时间没变成「现在」，列表也没有整页重拉（否则可能跳到顶部）。
    expect(find.text(postedLabel), findsOneWidget,
        reason: '发布时间还是发布那天，不是现在');
    expect(fake.requests.where((request) => request.method == 'GET'), hasLength(1));
    expect(
      tester.getTopLeft(find.text('旧的正文')).dy,
      lessThan(tester.getTopLeft(find.text('第二条正文')).dy),
    );
  });
}
