import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/weather/weather.dart';
import '../../../shared/weather/weather_visual.dart';

/// 天气城市选择底部弹层（原型 sheetCityPick · M1批2e）：
/// Open-Meteo geocoding 搜索，一次选定落设置（不申请定位权限）。
Future<void> showWeatherCitySheet(BuildContext context, WidgetRef ref) {
  final current =
      WeatherCity.decode(ref.read(settingsControllerProvider).weatherCity);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CitySheet(current: current),
  );
}

class _CitySheet extends ConsumerStatefulWidget {
  const _CitySheet({this.current});
  final WeatherCity? current;

  @override
  ConsumerState<_CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends ConsumerState<_CitySheet> {
  final _ctl = TextEditingController();
  List<CityHit>? _hits;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _ctl.text = widget.current?.name ?? '';
    if (_ctl.text.isNotEmpty) _search(); // 打开即带出当前城市（✓ 位）
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctl.text.trim();
    if (q.isEmpty) {
      setState(() => _hits = null);
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    final hits = await ref.read(weatherServiceProvider).searchCity(q);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _hits = hits;
      _failed = hits.isEmpty; // 含无网/无匹配（静默失败给一行提示位）
    });
  }

  Future<void> _pick(CityHit hit) async {
    await ref.read(settingsControllerProvider.notifier).setWeatherCity(
        WeatherCity.encode(
            WeatherCity(name: hit.name, lat: hit.lat, lon: hit.lon)));
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('天气城市已设置 · ${hit.name}'),
          duration: const Duration(milliseconds: 1300)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hits = _hits;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
              child: Text('天气城市',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900))),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('city-search'),
            controller: _ctl,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(
                isDense: true, hintText: '输入城市名'),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: _busy
                ? const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child:
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                : hits == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: Text('输入城市名搜索',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey))),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final h in hits)
                            InkWell(
                              key: ValueKey('city-hit-${h.name}'),
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _pick(h),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 11),
                                decoration: BoxDecoration(
                                    color: h.name == widget.current?.name
                                        ? scheme.primary.withValues(alpha: .08)
                                        : scheme.surfaceContainerHighest
                                            .withValues(alpha: .5),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: h.name == widget.current?.name
                                            ? scheme.primary
                                            : Colors.transparent)),
                                child: Row(
                                  children: [
                                    Expanded(
                                        child: Text(h.label,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700))),
                                    if (h.name == widget.current?.name)
                                      Icon(Icons.check,
                                          size: 16, color: scheme.primary),
                                  ],
                                ),
                              ),
                            ),
                          if (_failed)
                            const Center(
                                child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text('无匹配城市',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey))),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
