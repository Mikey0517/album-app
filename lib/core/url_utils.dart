import 'server_config.dart';

/// 大图预览地址：服务端会把 HEIC/超大 JPEG 转成 2560px 的 JPEG 再返回，
/// 避免全屏时因为解不了 HEIC 或图片过大只能显示缩略图。
String displayUrl(String path) {
  const prefix = '/files/';
  if (path.startsWith(prefix)) {
    return '/files/display/${path.substring(prefix.length)}';
  }
  return path;
}

/// 静态资源路径统一拼接；path 以 / 开头，base 可以带 context path。
String fullUrl(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  final base = ServerConfig.current;
  final p = path.startsWith('/') ? path : '/$path';
  return '$base$p';
}
