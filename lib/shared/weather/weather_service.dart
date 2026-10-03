import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/logging/app_log.dart';
import 'weather.dart';
import 'weather_dao.dart';

/// 一次取数的结果：json=成功解析的响应；err=失败短码
/// （`http <status>` / `timeout` / `socket` / `bad-json`），二者按成功/失败互斥。
typedef WeatherFetchResult = ({Map<String, dynamic>? json, String? err});

/// JSON GET 注入位（widget 测试给假实现，避免 FakeAsync 下真实网络挂死）。
/// 真机反馈轮4①：取数**不许把失败伪装成空结果**——失败必须带 err 透出。
typedef WeatherJsonFetcher = Future<WeatherFetchResult> Function(Uri uri);

/// 失败统一出口：落一行日志（来源=天气，按调用帧归类；只记 host，
/// **不记 query 原文**免带隐私）并回带 err 的结果。
WeatherFetchResult _fail(Uri uri, String err) {
  AppLog.add('天气取数失败 host=${uri.host} err=$err', level: LhLevel.warn);
  return (json: null, err: err);
}

Future<WeatherFetchResult> _defaultFetch(Uri uri) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final req = await client.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return _fail(uri, 'http ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join();
    final dynamic j = jsonDecode(body);
    return j is Map<String, dynamic>
        ? (json: j, err: null)
        : _fail(uri, 'bad-json');
  } on TimeoutException {
    // catch-ok: 失败已在 _fail 内落 AppLog，非静默吞噬
    return _fail(uri, 'timeout');
  } on SocketException {
    // catch-ok: 同上
    return _fail(uri, 'socket');
  } on FormatException {
    // catch-ok: 同上
    return _fail(uri, 'bad-json');
  } catch (_) {
    // catch-ok: 同上（ClientException 等其余网络/解码异常归 socket 一档）
    return _fail(uri, 'socket');
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
    final json = (await _fetch(uri)).json;
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
  /// 返回带 err：取数失败≠查无此城，调用方（弹层）按 err 分三态显示。
  Future<({List<CityHit> hits, String? err})> searchCity(String query) async {
    final q = query.trim();
    if (q.isEmpty) return (hits: const <CityHit>[], err: null);
    final r = await _fetch(Uri.https('geocoding-api.open-meteo.com', '/v1/search',
        {'name': q, 'count': '10', 'language': 'zh', 'format': 'json'}));
    if (r.err != null) {
      // 服务层同样留痕：注入假 fetch 的用例也能断言「失败不落静默」。
      AppLog.add('城市搜索失败 err=${r.err}', level: LhLevel.warn);
      return (hits: const <CityHit>[], err: r.err);
    }
    final results = r.json?['results'];
    if (results is! List) return (hits: const <CityHit>[], err: null);
    return (
      hits: [
        for (final item in results)
          if (item is Map &&
              item['name'] is String &&
              item['latitude'] is num &&
              item['longitude'] is num)
            CityHit(
              name: item['name'] as String,
              lat: (item['latitude'] as num).toDouble(),
              lon: (item['longitude'] as num).toDouble(),
              admin1: item['admin1'] as String?,
              country: item['country'] as String?,
            ),
      ],
      err: null,
    );
  }
}
