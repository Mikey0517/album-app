import 'package:album_app/core/hidden_space/hidden_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('6 位数字才认', () {
    expect(HiddenLock.isValidPin('123456'), isTrue);
    expect(HiddenLock.isValidPin('12345'), isFalse);
    expect(HiddenLock.isValidPin('1234567'), isFalse);
    expect(HiddenLock.isValidPin('12345a'), isFalse);
  });

  test('设置后能校验通过，错误密码不行', () async {
    expect(await HiddenLock.isConfigured(), isFalse);
    expect(await HiddenLock.setPin('123456'), isTrue);
    expect(await HiddenLock.isConfigured(), isTrue);
    expect(await HiddenLock.verify('123456'), isTrue);
    expect(await HiddenLock.verify('000000'), isFalse);
    expect(await HiddenLock.verify('12345'), isFalse);
  });

  test('存的是加盐哈希，不是明文', () async {
    await HiddenLock.setPin('987654');
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(HiddenLock.prefsKey)!;
    expect(stored.contains('987654'), isFalse);
    expect(stored, contains(':'));
  });

  test('两次设置同一密码，盐不同、哈希也不同', () async {
    await HiddenLock.setPin('123456');
    final first = (await SharedPreferences.getInstance())
        .getString(HiddenLock.prefsKey);
    SharedPreferences.setMockInitialValues({});
    await HiddenLock.setPin('123456');
    final second = (await SharedPreferences.getInstance())
        .getString(HiddenLock.prefsKey);
    expect(first, isNot(second));
  });

  test('清掉密码后回到未设置', () async {
    await HiddenLock.setPin('123456');
    await HiddenLock.clear();
    expect(await HiddenLock.isConfigured(), isFalse);
    expect(await HiddenLock.verify('123456'), isFalse);
  });
}
