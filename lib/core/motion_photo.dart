import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// 小米/Google Motion Photo 的 XMP 位于 JPEG 头部，通常远小于 256KB。
/// 只读文件头，不加载整张大图。
const int _probeBytes = 256 * 1024;

final Map<String, Future<MotionPhotoInfo?>> _infoCache = {};
final Map<String, Future<String?>> _extractedCache = {};

class MotionPhotoInfo {
  final int videoLength;
  final int padding;
  final int totalSize;

  const MotionPhotoInfo({
    required this.videoLength,
    required this.padding,
    required this.totalSize,
  });

  int get videoStart => max(0, totalSize - videoLength - padding);
}

Future<MotionPhotoInfo?> motionPhotoInfoFile(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final total = await file.length();
    if (total <= 0) return null;
    final bytes = await file.read(min(total, _probeBytes));
    return _parseInfo(String.fromCharCodes(bytes), total);
  } catch (_) {
    return null;
  } finally {
    await file?.close();
  }
}

Future<bool> isMotionPhotoFile(String path) async {
  return await motionPhotoInfoFile(path) != null;
}

Future<MotionPhotoInfo?> motionPhotoInfoUrl(String url) {
  return _infoCache.putIfAbsent(url, () => _probeUrl(url));
}

Future<bool> isMotionPhotoUrl(String url) async {
  return await motionPhotoInfoUrl(url) != null;
}

/// 从本地 Motion Photo 尾部提取内嵌 MP4，返回可交给 video_player 的临时文件。
Future<String?> extractMotionVideoFile(String path, MotionPhotoInfo info) {
  final key =
      'file:$path:${info.totalSize}:${info.videoLength}:${info.padding}';
  return _extractedCache.putIfAbsent(key, () => _extractLocal(path, info, key));
}

/// 远程 Motion Photo 只拉取文件尾部视频，不下载整张原图。
Future<String?> extractMotionVideoUrl(String url, MotionPhotoInfo info) {
  final key = 'url:$url:${info.totalSize}:${info.videoLength}:${info.padding}';
  return _extractedCache.putIfAbsent(key, () => _extractRemote(url, info, key));
}

Future<MotionPhotoInfo?> _probeUrl(String url) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );
  try {
    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=0-${_probeBytes - 1}'},
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    final stream = response.data?.stream;
    if (stream == null) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
      if (builder.length >= _probeBytes) break;
    }
    final total = _totalFromHeaders(response.headers);
    if (total == null) return null;
    return _parseInfo(String.fromCharCodes(builder.takeBytes()), total);
  } catch (_) {
    return null;
  } finally {
    dio.close(force: true);
  }
}

int? _totalFromHeaders(Headers headers) {
  final range = headers.value('content-range');
  if (range != null) {
    final slash = range.lastIndexOf('/');
    if (slash >= 0) {
      final value = int.tryParse(range.substring(slash + 1));
      if (value != null) return value;
    }
  }
  final length = headers.value('content-length');
  return int.tryParse(length ?? '');
}

MotionPhotoInfo? _parseInfo(String head, int totalSize) {
  final marker = head.indexOf('Semantic="MotionPhoto"');
  if (marker < 0) return null;
  final from = max(0, marker - 800);
  final to = min(head.length, marker + 1600);
  final section = head.substring(from, to);
  final lengthMatch = RegExp(r'Item:Length="(\d+)"').firstMatch(section);
  if (lengthMatch == null) return null;
  final videoLength = int.tryParse(lengthMatch.group(1) ?? '');
  if (videoLength == null || videoLength <= 0 || videoLength > totalSize) {
    return null;
  }
  final paddingMatch = RegExp(r'Item:Padding="(\d+)"').firstMatch(section);
  final padding = int.tryParse(paddingMatch?.group(1) ?? '') ?? 0;
  return MotionPhotoInfo(
    videoLength: videoLength,
    padding: padding,
    totalSize: totalSize,
  );
}

Future<String?> _extractLocal(
  String path,
  MotionPhotoInfo info,
  String key,
) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    await file.setPosition(info.videoStart);
    final bytes = await file.read(info.totalSize - info.videoStart);
    return _writeVideo(bytes, key);
  } catch (_) {
    return null;
  } finally {
    await file?.close();
  }
}

Future<String?> _extractRemote(
  String url,
  MotionPhotoInfo info,
  String key,
) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );
  try {
    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'Range': 'bytes=${info.videoStart}-${info.totalSize - 1}',
        },
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    final data = response.data;
    if (data == null || data.isEmpty) return null;
    Uint8List bytes = Uint8List.fromList(data);
    if (response.statusCode == 200 && bytes.length >= info.totalSize) {
      bytes = Uint8List.sublistView(bytes, info.videoStart);
    }
    return _writeVideo(bytes, key);
  } catch (_) {
    return null;
  } finally {
    dio.close(force: true);
  }
}

Future<String?> _writeVideo(List<int> bytes, String key) async {
  if (bytes.length < 16) return null;
  var offset = 0;
  final searchEnd = min(bytes.length - 8, 64);
  for (var i = 4; i <= searchEnd; i++) {
    if (bytes[i] == 0x66 &&
        bytes[i + 1] == 0x74 &&
        bytes[i + 2] == 0x79 &&
        bytes[i + 3] == 0x70) {
      offset = i - 4;
      break;
    }
  }
  final video = Uint8List.sublistView(Uint8List.fromList(bytes), offset);
  if (video.length < 16) return null;
  try {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/motion_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/motion_${key.hashCode.abs()}.mp4');
    if (await file.exists() && await file.length() > 0) return file.path;
    await file.writeAsBytes(video, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
