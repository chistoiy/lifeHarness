import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'weather.dart';
import 'weather_dao.dart';

/// JSON GET 注入位（widget 测试给假实现，避免 FakeAsync 下真实网络挂死）。
typedef WeatherJsonFetcher = Future<Map<String, dynamic>?> Function(Uri uri);

Future<Map<String, dynamic>?> _defaultFetch(Uri uri) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final req = await client.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    final body = await res.transform(utf8.decoder).join();
    final j = jsonDecode(body);
    return j is Map<String, dynamic> ? j : null;
  } catch (_) {
    return null; // 无网/超时/解析失败=静默（不阻塞写作）
  } finally {
    client?.close(force: true);
  }
}

/// Open-Meteo 天气服务（批2e 定案）：免费无 key；每日缓存表当天只抓一次；
/// 仅支持「今天」的天气快照（历史天气接口收费→不查历史）。
class WeatherService {
  WeatherService(this._dao, {WeatherJsonFetcher? fetch})
      : _fetch = fetch ?? _defaultFetch;

  final WeatherDao _dao;
  final WeatherJsonFetcher _fetch;

  /// 某日天气（今天=缓存→miss 抓 API→落缓存；更早=只读缓存，无则 null）。
  Future<WeatherDay?> day(DateTime day, WeatherCity city) async {
    final cached = await _dao.byDay(day, city.name);
    if (cached != null) return cached;
    final now = DateTime.now();
    if (day.year != now.year ||
        day.month != now.month ||
        day.day != now.day) {
      return null; // 不查历史
    }
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${city.lat}',
      'longitude': '${city.lon}',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min',
      'timezone': 'Asia/Shanghai',
      'forecast_days': '1',
    });
    final json = await _fetch(uri);
    final parsed = _parseForecast(json, WeatherDao.dayKey(day));
    if (parsed == null) return null;
    await _dao.upsert(day, city.name, parsed);
    return parsed;
  }

  /// forecast 响应→快照：daily 数组按日期命中（无精确命中取首行）。
  static WeatherDay? _parseForecast(Map<String, dynamic>? json, String key) {
    final daily = json?['daily'];
    if (daily is! Map) return null;
    List? times = daily['time'];
    List? codes = daily['weather_code'];
    List? maxs = daily['temperature_2m_max'];
    List? mins = daily['temperature_2m_min'];
    if (codes == null || codes.isEmpty) return null;
    var i = 0;
    if (times != null) {
      final hit = times.indexOf(key);
      if (hit >= 0) i = hit;
    }
    final code = codes[i];
    if (code is! int) return null;
    return WeatherDay(
      code: code,
      tmax: maxs != null && i < maxs.length ? (maxs[i] as num?)?.toDouble() : null,
      tmin: mins != null && i < mins.length ? (mins[i] as num?)?.toDouble() : null,
    );
  }

  /// 城市搜索（geocoding · 中文支持 language=zh）。
  Future<List<CityHit>> searchCity(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final json = await _fetch(Uri.https('geocoding-api.open-meteo.com', '/v1/search',
        {'name': q, 'count': '10', 'language': 'zh', 'format': 'json'}));
    final results = json?['results'];
    if (results is! List) return const [];
    return [
      for (final r in results)
        if (r is Map && r['name'] is String && r['latitude'] is num && r['longitude'] is num)
          CityHit(
            name: r['name'] as String,
            lat: (r['latitude'] as num).toDouble(),
            lon: (r['longitude'] as num).toDouble(),
            admin1: r['admin1'] as String?,
            country: r['country'] as String?,
          ),
    ];
  }
}
