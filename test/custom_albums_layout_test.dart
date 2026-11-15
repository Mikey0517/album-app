import 'dart:convert';

import 'package:album_app/core/design/theme.dart';
import 'package:album_app/features/album/custom_albums_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_http.dart';

String _albumsJson(List<Map<String, Object?>> items) =>
    jsonEncode({'items': items});

Map<String, Object?> _album(int id, String title) => {
      'id': id,
      'title': title,
      'media_count': 3,
      'visibility': 'family',
      'created_at': '2026-01-01T00:00:00Z',
    };

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: CustomAlbumsPage(scope: AlbumScope.family),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('新建相册按钮 = 同排封面的正方形，图标文字居中', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(installFakeApi(json: _albumsJson([_album(7, '夏天')])));

    await _pumpPage(tester);

    final cover = find.byKey(albumCoverKey);
    final button = find.byKey(newAlbumCardKey);
    expect(cover, findsOneWidget);
    expect(button, findsOneWidget);

    final coverRect = tester.getRect(cover);
    final buttonRect = tester.getRect(button);

    // 封面和按钮都是正方形。
    expect(coverRect.width, moreOrLessEquals(coverRect.height, epsilon: 0.01),
        reason: '相册封面是正方形');
    expect(buttonRect.width, moreOrLessEquals(buttonRect.height, epsilon: 0.01),
        reason: '新建相册按钮是正方形');

    // 两者尺寸完全一致，且同一排对齐（上沿齐，高度一样所以下沿也齐）。
    expect(buttonRect.width, moreOrLessEquals(coverRect.width, epsilon: 0.01),
        reason: '按钮宽度 == 同排封面宽度');
    expect(buttonRect.height, moreOrLessEquals(coverRect.height, epsilon: 0.01),
        reason: '按钮高度 == 同排封面高度');
    expect(buttonRect.top, moreOrLessEquals(coverRect.top, epsilon: 0.01),
        reason: '和同排封面从同一条上沿开始');
    expect(buttonRect.bottom, moreOrLessEquals(coverRect.bottom, epsilon: 0.01));

    // 边长跟随网格：390 - 16*2 = 358，两列再减 12 的列间距后平分。
    const expectedSide = (390 - 16 * 2 - 12) / 2;
    expect(coverRect.width, moreOrLessEquals(expectedSide, epsilon: 0.01));
    expect(buttonRect.left, moreOrLessEquals(16 + expectedSide + 12, epsilon: 0.01),
        reason: '第二列：左内边距 + 一格 + 列间距');

    // 内容水平垂直居中：图标的横坐标、以及「图标 + 文字」整体的中轴都在卡片中心。
    final icon = find.descendant(of: button, matching: find.byIcon(Icons.add));
    final label = find.descendant(of: button, matching: find.text('新建相册'));
    expect(icon, findsOneWidget);
    expect(label, findsOneWidget);
    expect(tester.getCenter(icon).dx,
        moreOrLessEquals(buttonRect.center.dx, epsilon: 0.01));
    expect(tester.getCenter(label).dx,
        moreOrLessEquals(buttonRect.center.dx, epsilon: 0.01));
    final iconRect = tester.getRect(icon);
    final labelRect = tester.getRect(label);
    expect((iconRect.top + labelRect.bottom) / 2,
        moreOrLessEquals(buttonRect.center.dy, epsilon: 0.5),
        reason: '图标 + 文字整体垂直居中');

    expect(tester.takeException(), isNull, reason: '不能有 overflow 报错');
  });

  testWidgets('多列（平板）时按钮仍然和同排封面一样大', (tester) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(installFakeApi(
      json: _albumsJson([_album(1, '春'), _album(2, '夏'), _album(3, '秋')]),
    ));

    await _pumpPage(tester);

    final covers = find.byKey(albumCoverKey);
    final button = find.byKey(newAlbumCardKey);
    expect(covers, findsNWidgets(3));
    final coverRect = tester.getRect(covers.first);
    final buttonRect = tester.getRect(button);
    expect(coverRect.width, moreOrLessEquals(coverRect.height, epsilon: 0.01));
    expect(buttonRect.size, coverRect.size);
    // 三列：1024 - 32 - 12*2 = 968，平分三列。
    expect(coverRect.width, moreOrLessEquals((1024 - 32 - 24) / 3, epsilon: 0.01));
    expect(tester.takeException(), isNull);
  });
}
