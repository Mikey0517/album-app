import 'dart:io';

import 'package:album_app/core/design/theme.dart';
import 'package:album_app/core/media_store.dart';
import 'package:album_app/core/source_media_cleanup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 极简宿主页：按钮里做的事和相册页/动态页完全一样（确认 → 删除 → 提示）。
class _Harness extends StatelessWidget {
  final List<SourceTarget> items;

  const _Harness({required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (inner) => TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(inner);
              final confirmed = await confirmDeleteSourceMedia(
                inner,
                items,
                targetLabel: '朋友圈',
                action: '发布到',
              );
              if (confirmed) {
                await deleteSourceMedia(items, messenger: messenger);
              }
            },
            child: const Text('发布'),
          ),
        ),
      ),
    );
  }
}

Widget _app(List<SourceTarget> items) => MaterialApp(
      theme: buildAppTheme(),
      home: _Harness(items: items),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('album/media_store');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    // 单测跑在桌面上，Platform.isAndroid 恒为 false，这里按用例指定平台。
    sourceCleanupPlatformCheck = () => true;
  });

  tearDown(() {
    sourceCleanupPlatformCheck = () => Platform.isAndroid;
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('有源 URI 会弹窗，点删除会调用 MediaStore 删掉原图', (tester) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'deleted': 2, 'failed': 0};
    });

    await tester.pumpWidget(_app([
      (uri: 'content://media/1', isVideo: false),
      (uri: 'content://media/2', isVideo: true),
    ]));

    expect(find.text('删除手机里的原图？'), findsNothing, reason: '还没发布，不能弹');

    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    expect(find.text('删除手机里的原图？'), findsOneWidget);
    expect(find.textContaining('2 项已发布到朋友圈。'), findsOneWidget);
    expect(find.textContaining('删除后手机相册里就没有这些照片了'), findsOneWidget);
    expect(find.text('保留'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'deleteUris');
    expect(calls.single.arguments, {
      'items': [
        {'uri': 'content://media/1', 'video': false},
        {'uri': 'content://media/2', 'video': true},
      ],
    });
    expect(find.text('已删除 2 张原图'), findsOneWidget, reason: '成功提示不能丢');
  });

  testWidgets('非 Android（iOS）不弹窗，也不会去删原图', (tester) async {
    sourceCleanupPlatformCheck = () => false;
    var channelHit = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      channelHit = true;
      return {'deleted': 1, 'failed': 0};
    });

    await tester.pumpWidget(_app([
      (uri: 'content://media/1', isVideo: false),
    ]));
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    expect(find.text('删除手机里的原图？'), findsNothing);
    expect(channelHit, isFalse);
  });

  testWidgets('没有源 URI 时不弹窗', (tester) async {
    var channelHit = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      channelHit = true;
      return {'deleted': 0, 'failed': 0};
    });

    await tester.pumpWidget(_app(const <SourceTarget>[]));
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    expect(find.text('删除手机里的原图？'), findsNothing);
    expect(channelHit, isFalse);
  });

  testWidgets('点保留不会调用 MediaStore', (tester) async {
    var channelHit = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      channelHit = true;
      return {'deleted': 1, 'failed': 0};
    });

    await tester.pumpWidget(_app([
      (uri: 'content://media/1', isVideo: false),
    ]));
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();

    expect(find.text('删除手机里的原图？'), findsNothing);
    expect(channelHit, isFalse);
  });

  test('删除结果文案：全部删除 / 部分删除 / 失败原因', () {
    expect(
      sourceDeleteMessage(const SourceDeleteResult(deleted: 3, failed: 0)),
      '已删除 3 张原图',
    );
    expect(
      sourceDeleteMessage(const SourceDeleteResult(deleted: 2, failed: 1)),
      '已删除 2 张，1 张未能删除',
    );
    expect(
      sourceDeleteMessage(
        const SourceDeleteResult(deleted: 0, failed: 2, error: '无权限'),
      ),
      '没能删除（无权限），请到系统相册里手动删除',
    );
    expect(
      sourceDeleteMessage(const SourceDeleteResult(deleted: 0, failed: 1)),
      '没能删除，请稍后在系统相册里手动删除',
    );
  });
}
