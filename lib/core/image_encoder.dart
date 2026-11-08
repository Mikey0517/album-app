import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// 编码后的图片：bytes + mime（Android 出 JPEG，iOS 回退成 PNG）。
class EncodedImage {
  final Uint8List bytes;
  final String mime;

  const EncodedImage(this.bytes, this.mime);
}

/// 把本地图片压成适合发给 AI 的小图：长边 512。
/// Android 走原生 Bitmap 编码 JPEG；iOS 没有该通道，用 dart:ui 缩图后编码 PNG。
class ImageEncoder {
  ImageEncoder._();

  static const MethodChannel _channel = MethodChannel('album/image_encoder');

  static Future<EncodedImage?> encode(
    String path, {
    int maxEdge = 512,
    int quality = 80,
  }) async {
    if (Platform.isAndroid) {
      try {
        final bytes = await _channel.invokeMethod<Uint8List>('encodeJpeg', {
          'path': path,
          'maxEdge': maxEdge,
          'quality': quality,
        });
        if (bytes != null && bytes.isNotEmpty) {
          return EncodedImage(bytes, 'image/jpeg');
        }
      } catch (_) {
        // 原生通道不可用时退回纯 Dart 实现。
      }
    }
    return _encodeWithDart(path, maxEdge);
  }

  /// 解码时先限制到 2 倍目标尺寸控制内存，再按长边缩到 maxEdge 并编码 PNG。
  static Future<EncodedImage?> _encodeWithDart(String path, int maxEdge) async {
    try {
      final raw = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        raw,
        targetWidth: maxEdge * 2,
        targetHeight: maxEdge * 2,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final source = frame.image;
      ui.Image output = source;

      final longest = math.max(source.width, source.height);
      if (longest > maxEdge) {
        final ratio = maxEdge / longest;
        final width = math.max(1, (source.width * ratio).round());
        final height = math.max(1, (source.height * ratio).round());
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          source,
          ui.Rect.fromLTWH(
              0, 0, source.width.toDouble(), source.height.toDouble()),
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.medium,
        );
        output = await recorder.endRecording().toImage(width, height);
        source.dispose();
      }

      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      output.dispose();
      if (data == null) return null;
      final bytes = data.buffer.asUint8List();
      if (bytes.isEmpty) return null;
      return EncodedImage(bytes, 'image/png');
    } catch (_) {
      return null;
    }
  }
}
