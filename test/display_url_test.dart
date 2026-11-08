import 'package:album_app/core/url_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('图片地址改写为服务端大图预览地址', () {
    expect(displayUrl('/files/abc.jpg'), '/files/display/abc.jpg');
    expect(displayUrl('/files/abc.heic'), '/files/display/abc.heic');
  });

  test('非 /files 路径保持原样', () {
    expect(displayUrl('https://example.com/x.jpg'),
        'https://example.com/x.jpg');
    expect(displayUrl('/api/x'), '/api/x');
  });
}
