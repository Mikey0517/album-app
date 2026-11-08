import 'package:album_app/core/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServerConfig.normalize', () {
    test('adds http scheme and strips trailing slash', () {
      expect(
        ServerConfig.normalize('192.168.1.50:8000/'),
        'http://192.168.1.50:8000',
      );
    });

    test('keeps https and lowercases host', () {
      expect(
        ServerConfig.normalize('https://MyNAS.Local:8443'),
        'https://mynas.local:8443',
      );
    });

    test('keeps the context path', () {
      expect(
        ServerConfig.validate('http://mikey.fucku.top/album'),
        isNull,
      );
      expect(
        ServerConfig.normalize('mikey.fucku.top/album/'),
        'http://mikey.fucku.top/album',
      );
      expect(
        ServerConfig.normalize('http://192.168.1.50:8000/'),
        'http://192.168.1.50:8000',
      );
    });

    test('rejects empty and malformed addresses', () {
      expect(ServerConfig.validate(''), isNotNull);
      expect(ServerConfig.validate('not a url'), isNotNull);
      expect(ServerConfig.validate('ftp://192.168.1.50'), isNotNull);
    });

    test('accepts ipv4 and hostname', () {
      expect(ServerConfig.validate('http://192.168.1.50:8000'), isNull);
      expect(ServerConfig.validate('my-nas.local:8000'), isNull);
    });
  });

  group('ServerConfig.init', () {
    setUp(() {
      ServerConfig.resetForTest();
      ServerConfig.setNetworkKindForTest('mobile');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(ServerConfig.resetForTest);

    test('fills both defaults on a fresh install', () async {
      await ServerConfig.init();
      expect(ServerConfig.lanUrl, ServerConfig.defaultLanUrl);
      expect(ServerConfig.wanUrl, ServerConfig.defaultWanUrl);
      expect(ServerConfig.current, ServerConfig.defaultWanUrl);
    });

    test('migrates server_base_url to lan_url and removes old key', () async {
      SharedPreferences.setMockInitialValues({
        'server_base_url': 'http://192.168.1.50:8000',
      });
      await ServerConfig.init();
      expect(ServerConfig.lanUrl, 'http://192.168.1.50:8000');
      expect(ServerConfig.wanUrl, ServerConfig.defaultWanUrl);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('server_base_url'), isFalse);
      expect(prefs.getString('lan_url'), 'http://192.168.1.50:8000');
    });
  });
}
