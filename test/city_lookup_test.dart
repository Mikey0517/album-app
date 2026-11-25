import 'package:album_app/core/city_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(CityLookup.resetForTest);

  test('成都附近的坐标反查成「成都市」', () async {
    expect(await CityLookup.nearestCity(30.57, 104.06), '成都市');
  });

  test('北京、上海、拉萨这些城市都能认出来', () async {
    expect(await CityLookup.nearestCity(39.90, 116.40), '北京市');
    expect(await CityLookup.nearestCity(31.23, 121.47), '上海市');
    expect(await CityLookup.nearestCity(29.65, 91.10), '拉萨市');
  });

  test('境外坐标不硬套中国城市（超过匹配半径返回 null）', () async {
    expect(await CityLookup.nearestCity(48.85, 2.35), isNull, reason: '巴黎');
    expect(await CityLookup.nearestCity(35.68, 139.69), isNull, reason: '东京');
  });

  test('没有 GPS 就是 null', () async {
    expect(await CityLookup.nearestCity(null, null), isNull);
    expect(await CityLookup.nearestCity(null, 104.06), isNull);
  });

  test('球面距离按公里算', () {
    expect(
      CityLookup.distanceKm(30.57, 104.06, 30.66, 104.06),
      closeTo(10, 1.5),
    );
  });
}
