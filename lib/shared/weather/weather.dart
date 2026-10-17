/// M1批2e · 天气领域模型（数据源 Open-Meteo · 免费无 key）。
///
/// 定案口径：只存「写日记当天抓取」的条目快照（历史天气接口收费→不查历史）；
/// WMO 天气码 → 中文标签在本文件收敛，展示图标映射在 presentation 层。
library;

/// 天气城市（设置页一次选定；编码进 SharedPreferences 单键）。
class WeatherCity {
  const WeatherCity({required this.name, required this.lat, required this.lon});

  final String name;
  final double lat;
  final double lon;

  /// 持久化编码：`name|lat|lon`（''=未设置）。
  static String encode(WeatherCity? c) =>
      c == null ? '' : '${c.name}|${c.lat}|${c.lon}';

  static WeatherCity? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    final lat = double.tryParse(parts[1]);
    final lon = double.tryParse(parts[2]);
    if (parts[0].isEmpty || lat == null || lon == null) return null;
    return WeatherCity(name: parts[0], lat: lat, lon: lon);
  }
}

/// 某日天气快照（code=WMO 天气码；温度为当日最低/最高，可能缺项）。
class WeatherDay {
  const WeatherDay({required this.code, this.tmax, this.tmin});

  final int code;
  final double? tmax;
  final double? tmin;
}

/// geocoding 搜索命中（城市选择弹层条目）。
class CityHit {
  const CityHit(
      {required this.name,
      required this.lat,
      required this.lon,
      this.admin1,
      this.admin2,
      this.country});

  final String name;
  final double lat;
  final double lon;
  final String? admin1;
  // 轮4：数据源同名条目多（「阜阳」既是安徽地级市也是江苏的村），
  // 二级区划并进标签让全部结果可区分，由用户自选，不做过滤。
  final String? admin2;
  final String? country;

  /// 条目主文案：`名 · 省 · 市`（空段跳过；真机反馈轮4 产品口径）。
  String get label {
    final parts = <String>[
      name,
      if (admin1 != null && admin1!.isNotEmpty && admin1 != name) admin1!,
      if (admin2 != null &&
          admin2!.isNotEmpty &&
          admin2 != name &&
          admin2 != admin1)
        admin2!,
      if ((admin1 == null || admin1!.isEmpty) &&
          country != null &&
          country!.isNotEmpty)
        country!,
    ];
    return parts.join(' · ');
  }
}

/// 手动覆盖七选项（与原型 sheetWeatherPick 同构，存代表码）。
const kWeatherOptions = <int>[0, 2, 3, 61, 71, 45, 95];

/// WMO 天气码 → 中文标签（桶化：细档位仍归入可读懂的中文说法）。
String weatherLabel(int code) {
  if (code == 0 || code == 1) return '晴';
  if (code == 2) return '多云';
  if (code == 3) return '阴';
  if (code == 45 || code == 48) return '雾';
  if (code >= 51 && code <= 57) return '毛毛雨';
  if (code == 61) return '小雨';
  if (code == 63) return '中雨';
  if (code == 65) return '大雨';
  if (code == 66 || code == 67) return '冻雨';
  if (code == 71) return '小雪';
  if (code == 73) return '中雪';
  if (code >= 75 && code <= 77) return '大雪';
  if (code >= 80 && code <= 82) return '阵雨';
  if (code == 85 || code == 86) return '阵雪';
  if (code >= 95) return '雷阵雨';
  return '未知';
}

/// chip/副标题展示文本：「晴 20~30°」/「晴 24°」/「晴」。
String weatherText(int code, {double? tmax, double? tmin, bool compact = false}) {
  final label = weatherLabel(code);
  final hi = tmax?.round();
  final lo = tmin?.round();
  if (compact || hi == null || lo == null || hi == lo) {
    final t = compact ? hi : (hi ?? lo);
    return t == null ? label : '$label $t°';
  }
  return '$label $lo~$hi°';
}
