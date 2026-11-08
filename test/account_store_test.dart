import 'package:album_app/core/account_store.dart';
import 'package:album_app/models/app_user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mikey = AppUser(id: 1, userId: 'mikey', nickname: '爸爸');
  const mama = AppUser(id: 2, userId: 'mama', nickname: '妈妈');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('记住账号和密码，最近登录的排在最前', () async {
    await AccountStore.remember(mikey, 'pass1', savePassword: true);
    await AccountStore.remember(mama, 'pass2', savePassword: true);

    final accounts = await AccountStore.load();
    expect(accounts.map((a) => a.userId).toList(), ['mama', 'mikey']);
    expect(accounts.first.password, 'pass2');
    expect(accounts.first.hasPassword, isTrue);
    expect(accounts.first.label, '妈妈');
  });

  test('不勾记住密码时清掉该账号的旧密码', () async {
    await AccountStore.remember(mikey, 'old', savePassword: true);
    await AccountStore.remember(mikey, 'new', savePassword: false);

    final accounts = await AccountStore.load();
    expect(accounts.length, 1);
    expect(accounts.single.password, isNull);
    expect(accounts.single.hasPassword, isFalse);
  });

  test('重复登录同一个账号不会产生重复记录', () async {
    await AccountStore.remember(mikey, 'a', savePassword: true);
    await AccountStore.remember(mikey, 'b', savePassword: true);

    final accounts = await AccountStore.load();
    expect(accounts.length, 1);
    expect(accounts.single.password, 'b');
  });

  test('最多保留 8 个账号', () async {
    for (var i = 0; i < 12; i++) {
      await AccountStore.remember(
        AppUser(id: i, userId: 'user$i', nickname: 'u$i'),
        'p',
        savePassword: true,
      );
    }
    final accounts = await AccountStore.load();
    expect(accounts.length, AccountStore.maxAccounts);
    expect(accounts.first.userId, 'user11');
  });

  test('可以只忘记密码，也可以删除整个账号', () async {
    await AccountStore.remember(mikey, 'p', savePassword: true);

    await AccountStore.forgetPassword('mikey');
    var accounts = await AccountStore.load();
    expect(accounts.single.userId, 'mikey');
    expect(accounts.single.hasPassword, isFalse);

    await AccountStore.remove('mikey');
    accounts = await AccountStore.load();
    expect(accounts, isEmpty);
  });
}
