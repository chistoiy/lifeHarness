import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import 'weather.dart';
import 'weather_dao.dart';
import 'weather_service.dart';

final weatherDaoProvider =
    Provider<WeatherDao>((ref) => WeatherDao(AppDatabase.instance.db));

/// 天气服务（批2e · Open-Meteo）；widget 测试 override 注入假 fetch。
final weatherServiceProvider = Provider<WeatherService>(
    (ref) => WeatherService(ref.watch(weatherDaoProvider)));

/// WMO 天气码 → 线性图标（UI 禁 emoji 规范·chip/副标题/选择弹层共用）。
IconData weatherIcon(int code) {
  if (code <= 1) return Icons.wb_sunny_outlined;
  if (code == 2) return Icons.cloud_outlined;
  if (code == 3) return Icons.cloud_queue;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 71 && code <= 86) return Icons.ac_unit;
  if (code >= 95) return Icons.thunderstorm;
  if (code >= 51 && code <= 67) return Icons.water_drop_outlined;
  return Icons.cloud_outlined;
}

/// 天气弹层结果：pick=选定码（手动覆盖）· restore=恢复自动获取。
class WxSheetResult {
  const WxSheetResult.pick(int this.code) : restore = false;
  const WxSheetResult.restore()
      : code = null,
        restore = true;

  final int? code;
  final bool restore;
}

/// 天气选择底部弹层（原型 sheetWeatherPick）：七项线性图标 grid；
/// 手动选择后本篇不再自动更新；[manual] 且当天显示「恢复自动获取」。
Future<WxSheetResult?> showWeatherPickSheet(BuildContext context,
    {required int? current, required bool manual, required bool isToday}) {
  return showModalBottomSheet<WxSheetResult>(
    context: context,
    isScrollControlled: true,
    builder: (bc) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
                child: Text('本篇天气',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
            const SizedBox(height: 12),
            Wrap(
              key: const ValueKey('wx-grid'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in kWeatherOptions)
                  Builder(builder: (_) {
                    final on = current != null &&
                        weatherLabel(code) == weatherLabel(current);
                    return InkWell(
                      key: ValueKey('wx-opt-$code'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          Navigator.of(bc).pop(WxSheetResult.pick(code)),
                      child: Container(
                        width: 84,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: on
                              ? Theme.of(bc)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .08)
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: on
                                  ? Theme.of(bc).colorScheme.primary
                                  : Colors.black12),
                        ),
                        child: Column(children: [
                          Icon(weatherIcon(code),
                              size: 20,
                              color: on
                                  ? Theme.of(bc).colorScheme.primary
                                  : null),
                          const SizedBox(height: 4),
                          Text(weatherLabel(code),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: on
                                      ? Theme.of(bc).colorScheme.primary
                                      : null)),
                        ]),
                      ),
                    );
                  }),
              ],
            ),
            if (manual && isToday) ...[
              const SizedBox(height: 12),
              SizedBox(
                key: const ValueKey('wx-restore'),
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(bc).pop(const WxSheetResult.restore()),
                  child: const Text('恢复自动获取',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
