// 工具屏 · 日期计算（原型 `TOOLS.datec` 同源 · 批2）。
//
// 三区结构照原型：① 两日期间隔（含节日快捷）② 日期 ± 天数 ③ 今天速览；
// 日期选择一律走应用内滚轮（`core/widgets/wheel_date.dart`，红线：禁系统日期控件）。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/wheel_date.dart';
import '../../domain/kit_calc.dart' show kitDayStart;
import '../../domain/kit_datec.dart';
import 'kit_tools_kit.dart';

/// 日期计算屏主体（由 `KitToolPage` 提供标题与隐私页脚外壳）。
class KitDatecBody extends StatefulWidget {
  const KitDatecBody({super.key});

  @override
  State<KitDatecBody> createState() => _KitDatecBodyState();
}

class _KitDatecBodyState extends State<KitDatecBody> {
  DateTime _a = kitDayStart(DateTime.now());
  DateTime _b = kitAnchorDate(KitDateAnchor.newYear, DateTime.now());
  DateTime _c = kitDayStart(DateTime.now());
  int _n = 100;
  int _sign = 1;

  String _diff = '';
  String _diffLunar = '';
  String _add = '';
  String _addLunar = '';
  String _share = '';

  @override
  void initState() {
    super.initState();
    _calcDiff();
    _calcAdd();
  }

  void _calcDiff() {
    setState(() {
      _diff = kitDateDiffText(_a, _b);
      _diffLunar = kitDateDiffLunarText(_a, _b);
      _share = '${kitIsoDate(_a)} → ${kitIsoDate(_b)} · $_diff';
    });
  }

  void _calcAdd() {
    final r = kitDateAdd(_c, _n * _sign);
    setState(() {
      if (r == null) {
        _add = '';
        _addLunar = '';
        return;
      }
      _add = r.label;
      _addLunar = '${kitIsoDate(r.date)} · ${r.lunar}';
      _share = r.shareFrom(_c);
    });
  }

  Future<void> _pickDate(DateTime initial, ValueChanged<DateTime> set) async {
    final v = await showWheelDatePick(context, initial);
    if (v != null && mounted) {
      setState(() => set(v));
      _calcDiff();
      _calcAdd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final now = kitDayStart(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        kitToolSection('① 两日期间隔', trailing: [
          KitToolChip(label: '农历随日子模块引擎换算', on: false, onTap: () {}),
        ]),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _dateField('kit-datec-a', _a, () => _pickDate(_a, (d) => _a = d)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('→', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            Expanded(
              child: _dateField('kit-datec-b', _b, () => _pickDate(_b, (d) => _b = d)),
            ),
            const SizedBox(width: 6),
            kitToolBtn(context, '算', _calcDiff),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final k in KitDateAnchor.values)
              kitToolBtn(
                context,
                k.label,
                () {
                  setState(() {
                    _b = kitAnchorDate(k, now);
                    _calcDiff();
                  });
                },
                keyName: 'kit-datec-anchor-${k.name}',
                small: true,
              ),
          ],
        ),
        const SizedBox(height: 4),
        kitToolResult(_diff, tokens.accent, keyName: 'kit-datec-diff'),
        if (_diffLunar.isNotEmpty)
          kitToolNote(_diffLunar, key: const ValueKey('kit-datec-diff-lunar')),
        const SizedBox(height: 18),
        kitToolSection('② 日期 ± 天数'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _dateField('kit-datec-c', _c, () => _pickDate(_c, (d) => _c = d)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 5),
              child: Text('±', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            KitToolNumberField(
              value: _n,
              onChanged: (v) {
                _n = v;
                _calcAdd();
              },
            ),
            const SizedBox(width: 4),
            KitToolChip(
              keyName: 'kit-datec-plus',
              label: '＋后',
              on: _sign == 1,
              onTap: () {
                setState(() => _sign = 1);
                _calcAdd();
              },
            ),
            const SizedBox(width: 4),
            KitToolChip(
              keyName: 'kit-datec-minus',
              label: '－前',
              on: _sign == -1,
              onTap: () {
                setState(() => _sign = -1);
                _calcAdd();
              },
            ),
            const SizedBox(width: 4),
            kitToolBtn(context, '算', _calcAdd),
          ],
        ),
        const SizedBox(height: 6),
        kitToolResult(_add, const Color(0xFF0D9488), keyName: 'kit-datec-add'),
        if (_addLunar.isNotEmpty) kitToolNote(_addLunar),
        const SizedBox(height: 14),
        kitToolSubCard(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('③ 今天速览',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                kitTodayQuick(now),
                key: const ValueKey('kit-datec-quick'),
                style: const TextStyle(fontSize: 10.5, height: 1.6, color: Colors.grey),
              ),
              Text(
                '今天农历 ${kitLunarLabel(now)} · 周${kitWeekdayLabel(now)}',
                style: const TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            kitToolBtn(
              context,
              '结果转「重要日子」倒数',
              _share.isEmpty
                  ? null
                  : () {
                      kitToolCopy(context, _share, msg: '结果已复制 · 请到日子页新建倒数日');
                      context.go('/days');
                    },
              keyName: 'kit-datec-to-day',
            ),
            const SizedBox(width: 6),
            kitToolBtn(context, '复制结果', () => kitToolCopy(context, _share)),
          ],
        ),
      ],
    );
  }

  Widget _dateField(String key, DateTime d, VoidCallback onTap) => GestureDetector(
        key: ValueKey(key),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.tokens.cardBorder),
          ),
          child: Text(
            kitIsoDate(d),
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
}
