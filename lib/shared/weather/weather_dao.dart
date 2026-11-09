import 'package:sqflite/sqflite.dart';

import '../../core/database/schema.dart';
import 'weather.dart';

/// weather_daily 表数据访问（M1批2e · 每日天气缓存·day=YYYY-MM-DD）。
class WeatherDao {
  WeatherDao(this.db);

  final Database db;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 某日缓存（城市不一致视为失效返回 null，触发按新城市重抓）。
  Future<WeatherDay?> byDay(DateTime day, String city) async {
    final rows = await db.query(
      DbSchema.tWeatherDaily,
      where: 'day = ?',
      whereArgs: [dayKey(day)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    if ((r['city'] as String?) != city) return null;
    return WeatherDay(
        code: r['code'] as int, tmax: r['tmax'] as double?, tmin: r['tmin'] as double?);
  }

  Future<void> upsert(DateTime day, String city, WeatherDay w) =>
      db.insert(DbSchema.tWeatherDaily, {
        'day': dayKey(day),
        'city': city,
        'code': w.code,
        'tmax': w.tmax,
        'tmin': w.tmin,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
}
