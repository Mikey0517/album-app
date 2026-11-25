import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// 一个城市中心点（`assets/cities.json` 里的一条）。
///
/// 数据是地级市中心点的平均坐标（精确到市级，不区分区县）；只用来把
/// 照片 GPS 反查成「成都市」这种城市名，不参与地图定位。
class CityPoint {
  final String name;
  final double latitude;
  final double longitude;

  const CityPoint(this.name, this.latitude, this.longitude);
}

/// 照片 GPS → 市级名称。
///
/// 不联网、不依赖任何地图服务：离线查表取**最近的市**。公里级误差对内陆城市
/// 没有影响；离最近的中国地级市超过 [maxRadiusKm]（境外、海上等）就不猜，
/// 返回 null，详情页继续显示经纬度。
class CityLookup {
  CityLookup._();

  /// 匹配半径：超过这个距离就不认（照片可能在境外）。
  ///
  /// 250km 是按「地级市本身很大」定的：呼伦贝尔、三沙这类城市，拍摄点离
  /// 中心点几百公里都算正常；再放宽就会把境外照片硬套到边境城市上。
  static const double maxRadiusKm = 250;

  static List<CityPoint>? _cities;
  static Future<List<CityPoint>>? _loading;

  /// 载入表（只解析一次）。失败时返回空表，调用方按「没有城市名」处理。
  static Future<List<CityPoint>> load() {
    final cached = _cities;
    if (cached != null) return Future.value(cached);
    return _loading ??= _parse();
  }

  static Future<List<CityPoint>> _parse() async {
    try {
      final raw = await rootBundle.loadString('assets/cities.json');
      final decoded = jsonDecode(raw);
      final cities = <CityPoint>[];
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! List || item.length < 3) continue;
          final name = item[0];
          final lat = item[1];
          final lng = item[2];
          if (name is! String || lat is! num || lng is! num) continue;
          cities.add(CityPoint(name, lat.toDouble(), lng.toDouble()));
        }
      }
      _cities = cities;
      return cities;
    } catch (_) {
      _cities = const <CityPoint>[];
      return _cities!;
    }
  }

  /// 最近的城市名；没有 GPS、表为空或超出 [maxRadiusKm] 时返回 null。
  static Future<String?> nearestCity(double? latitude, double? longitude) async {
    if (latitude == null || longitude == null) return null;
    final cities = await load();
    if (cities.isEmpty) return null;
    CityPoint? best;
    var bestDistance = double.infinity;
    for (final city in cities) {
      final distance = distanceKm(latitude, longitude, city.latitude, city.longitude);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = city;
      }
    }
    if (best == null || bestDistance > maxRadiusKm) return null;
    return best.name;
  }

  /// 球面距离（km），haversine。
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double degrees) => degrees * math.pi / 180;

  /// 测试用：清掉缓存（换掉假数据表时调用）。
  static void resetForTest() {
    _cities = null;
    _loading = null;
  }
}
