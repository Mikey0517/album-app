import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:album_app/core/api_client.dart';
import 'package:album_app/core/current_user.dart';
import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/feed/compose_page.dart';
import 'package:album_app/features/feed/feed_page.dart';
import 'package:album_app/features/feed/post_card.dart';
import 'package:album_app/models/app_user.dart';
import 'package:album_app/models/media.dart';
import 'package:album_app/models/post.dart';
import 'package:album_app/widgets/album_thumb.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 已发布动态的再编辑：
// 1. 「编辑」入口只在作者本人的「更多」菜单里；
// 2. 编辑页复用发布页的文案编辑器，媒体只读（无加号、无删除角标、无 AI 帮写）；
// 3. 保存后把最新动态交回列表就地替换，不整页重拉；
// 4. 改过的动态标一个「已编辑」。

const AppUser _me = AppUser(id: 1, userId: 'me', nickname: '我');

/// 一条自己的动态，带一张「缩略图取不到」的媒体：媒体区照常渲染占位块，
/// 测试不碰网络。
Post _post({
  int id = 7,
  int authorId = 1,
  String? content = '旧的正文',
  DateTime? editedAt,
  bool withMedia = true,
}) {
  return Post(
    id: id,
    authorId: authorId,
    authorNickname: authorId == 1 ? '我' : '妈妈',
    content: content,
    postedAt: DateTime(2026, 1, 1, 10),
    editedAt: editedAt,
    medias: withMedia
        ? [
            Media(
              id: 101,
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
          ]
        : const [],
  );
}

Map<String, dynamic> _mediaJson() => {
      'id': 101,
      'type': 'image',
      'thumb_url': null,
      'url': '',
      'width': 100,
      'height': 100,
      'taken_at': '2026-01-01T10:00:00',
      'created_at': '2026-01-01T10:00:00',
      'post_id': 7,
      'thumb_failed': true,
      'favorite': false,
    };

Map<String, dynamic> _postJson({
  int id = 7,
  int authorId = 1,
  String? content = '旧的正文',
  String? editedAt,
}) =>
    {
      'id': id,
      'author_id': authorId,
      'author_nickname': authorId == 1 ? '我' : '妈妈',
      'content': content,
      'posted_at': '2026-01-01T10:00:00',
      'edited_at': editedAt,
      'medias': [_mediaJson()],
    };

ResponseBody _jsonBody(Object body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// 按请求分派的假适配器：记下每个请求，测试断言用。
class _RouteFake implements HttpClientAdapter {
  _RouteFake(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

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

/// 装上假适配器并关掉 dio 超时定时器（否则测试结束会报 Timer is pending）。
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

Widget _host(Widget child) {
  return MaterialApp(theme: buildAppTheme(), home: child);
}

Widget _cardHost(PostCard card) {
  return _host(Scaffold(body: ListView(children: [card])));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CurrentUser.notifier.value = _me;
  });

  tearDown(() => CurrentUser.notifier.value = null);

  void sizePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('作者本人的「更多」菜单里有编辑', (tester) async {
    sizePhone(tester);
    _installFake((_) => _jsonBody(_postJson()));

    await tester.pumpWidget(
      _cardHost(PostCard(
        post: _post(),
        onOpenMedia: (_, __) {},
        onDeleted: () {},
      )),
    );
    await tester.pump();

    expect(find.byTooltip('更多'), findsOneWidget);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
  });

  testWidgets('别人的动态没有「更多」，也就没有编辑', (tester) async {
    sizePhone(tester);
    _installFake((_) => _jsonBody(_postJson(authorId: 2)));

    await tester.pumpWidget(
      _cardHost(PostCard(
        post: _post(authorId: 2),
        onOpenMedia: (_, __) {},
        onDeleted: () {},
      )),
    );
    await tester.pump();

    expect(find.byTooltip('更多'), findsNothing);
    expect(find.text('编辑'), findsNothing);
  });

  testWidgets('编辑页预填正文、媒体只读，保存后交回新动态', (tester) async {
    sizePhone(tester);
    final fake = _installFake((_) => _jsonBody(_postJson(
          content: '新的正文',
          editedAt: '2026-01-02T09:00:00',
        )));

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

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.byType(ComposePage), findsOneWidget);
    // 复用发布页那套编辑器，正文原样带过来。
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '旧的正文');
    expect(field.decoration?.hintText, '这一刻的想法…');

    // 媒体只读：有缩略图，没有加号、没有删除角标、没有拖动排序、没有 AI 帮写。
    expect(find.byType(AlbumThumb), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget,
        reason: '只剩左上角关闭；媒体上没有移除角标');
    expect(find.byType(LongPressDraggable<int>), findsNothing);
    expect(find.text('AI 帮写'), findsNothing);

    // 保存按钮的文案换成了「保存」，空文案时不可点。
    expect(find.widgetWithText(TextButton, '保存'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '新的正文');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    final puts = fake.requests.where((r) => r.method == 'PUT').toList();
    expect(puts, hasLength(1));
    expect(puts.single.path, '/api/posts/7');
    expect(puts.single.data, {'content': '新的正文'});

    expect(find.byType(ComposePage), findsNothing, reason: '保存后返回列表');
    expect(edited, isNotNull);
    expect(edited!.content, '新的正文');
    expect(edited!.editedAt, isNotNull);
    expect(edited!.medias, hasLength(1), reason: '媒体不参与编辑');
  });

  testWidgets('保存后朋友圈列表就地换成新正文，不重拉列表', (tester) async {
    sizePhone(tester);
    final fake = _installFake((options) {
      if (options.method == 'PUT') {
        return _jsonBody(_postJson(
          content: '新的正文',
          editedAt: '2026-01-02T09:00:00',
        ));
      }
      return _jsonBody({
        'items': [_postJson()],
        'next_cursor': null,
      });
    });

    await tester.pumpWidget(_host(const FeedPage()));
    await tester.pumpAndSettle();

    expect(find.text('旧的正文'), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新的正文');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('新的正文'), findsOneWidget);
    expect(find.text('旧的正文'), findsNothing);
    expect(find.text('已编辑'), findsOneWidget, reason: '改过就该标出来');
    // 列表就地替换：只请求了首屏列表和这一次编辑，没有为了刷新再拉一次。
    expect(fake.requests.where((r) => r.method == 'GET'), hasLength(1));
    expect(fake.requests.where((r) => r.method == 'PUT'), hasLength(1));
  });

  testWidgets('edited_at 非空才显示「已编辑」', (tester) async {
    sizePhone(tester);
    _installFake((_) => _jsonBody(_postJson()));

    await tester.pumpWidget(
      _cardHost(PostCard(
        post: _post(editedAt: DateTime(2026, 1, 2, 9)),
        onOpenMedia: (_, __) {},
        onDeleted: () {},
      )),
    );
    await tester.pump();
    expect(find.text('已编辑'), findsOneWidget);

    await tester.pumpWidget(
      _cardHost(PostCard(
        post: _post(),
        onOpenMedia: (_, __) {},
        onDeleted: () {},
      )),
    );
    await tester.pump();
    expect(find.text('已编辑'), findsNothing);
  });
}
