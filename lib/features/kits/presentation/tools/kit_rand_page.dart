// 工具屏 · 随机数（原型 `TOOLS.rand` / `randGo` / `randCard` 同源 · 批2）。
//
// 结果与历史落 `kit_tool_data.tool='rand'`（`{u, rHist}`，与原型 `KITS.rndU` /
// `KITS.rHist` 同构）；随机源用 `math.Random()`，纯本机计算零出站。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/kit_calc.dart' show kitRelText;
import '../../domain/kit_models.dart';
import '../../domain/kit_rand.dart';
import '../kit_providers.dart';
import 'kit_tools_kit.dart';

class KitRandBody extends ConsumerStatefulWidget {
  const KitRandBody({super.key});

  @override
  ConsumerState<KitRandBody> createState() => _KitRandBodyState();
}

class _KitRandBodyState extends ConsumerState<KitRandBody> {
  final math.Random _rnd = math.Random();

  int _min = 1;
  int _max = 100;
  int _count = 3;
  bool _unique = false;
  List<String> _out = const [];
  List<KitRandRecord> _hist = const [];
  String _hint = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final d = await ref.read(kitRepositoryProvider).toolData(kitToolKeyRand);
    if (!mounted) return;
    final s = kitRandDecode(d);
    setState(() {
      _unique = s.unique;
      _hist = s.history;
      _loaded = true;
    });
  }

  Future<void> _persist() async {
    await ref.read(kitRepositoryProvider).setToolData(
          kitToolKeyRand,
          kitRandEncode(unique: _unique, history: _hist),
        );
  }

  void _emit(KitRandOutcome o) {
    setState(() {
      _out = o.values;
      _hint = o.error;
    });
  }

  void _generate({int? min, int? max, int? count}) {
    if (min != null) _min = min;
    if (max != null) _max = max;
    if (count != null) _count = count;
    final o = kitRandGenerate(
      min: _min,
      max: _max,
      count: _count,
      unique: _unique,
      rnd: _rnd,
    );
    if (!o.ok) {
      _emit(o);
      return;
    }
    _emit(o);
    _push(
      KitRandRecord(
        min: _min,
        max: _max,
        values: o.values,
        unique: _unique,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void _drawCard() {
    final r = kitRandCard(rnd: _rnd, ts: DateTime.now().millisecondsSinceEpoch);
    setState(() {
      _out = [r.card];
      _hint = '抽到 ${r.card} · 52 张牌堆等概率';
    });
    _push(r.record);
  }

  Future<void> _push(KitRandRecord rec) async {
    setState(() => _hist = kitRandPush(_hist, rec));
    await _persist();
  }

  Future<void> _setUnique(bool v) async {
    setState(() => _unique = v);
    await _persist();
  }

  Future<void> _clearHist() async {
    setState(() => _hist = const []);
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KitToolNumberField(
              value: _min,
              onChanged: (v) => setState(() => _min = v),
              width: 68,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('~', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            KitToolNumberField(
              value: _max,
              onChanged: (v) => setState(() => _max = v),
              width: 68,
            ),
            const SizedBox(width: 8),
            KitToolNumberField(
              value: _count,
              onChanged: (v) => setState(() => _count = v),
              width: 58,
              max: kKitRandMaxCount,
            ),
            const SizedBox(width: 6),
            kitToolBtn(context, '生成', _generate, keyName: 'kit-rand-go'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Switch(
              key: const ValueKey('kit-rand-unique'),
              value: _unique,
              onChanged: _setUnique,
            ),
            const Text('不重复', style: TextStyle(fontSize: 11)),
            const Spacer(),
            kitToolBtn(
              context,
              '复制',
              _out.isEmpty ? null : () => kitToolCopy(context, _out.join(' · ')),
              small: true,
            ),
            const SizedBox(width: 4),
            kitToolBtn(
              context,
              '转倒数日',
              _out.isEmpty
                  ? null
                  : () {
                      kitToolCopy(context, _out.first, msg: '已生成倒数日草稿内容 · 请到日子页新建');
                      context.go('/days');
                    },
              small: true,
              keyName: 'kit-rand-to-day',
            ),
          ],
        ),
        if (_hint.isNotEmpty)
          kitToolNote(
            _hint,
            key: const ValueKey('kit-rand-hint'),
          ),
        if (_out.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            key: const ValueKey('kit-rand-out'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in _out)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [tokens.g1, tokens.g3]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    v,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            kitToolBtn(context, '骰子', () => _generate(min: 1, max: 6, count: 1),
                keyName: 'kit-rand-q-dice', small: true),
            kitToolBtn(context, '硬币', () => _generate(min: 1, max: 2, count: 1),
                keyName: 'kit-rand-q-coin', small: true),
            kitToolBtn(context, 'D20', () => _generate(min: 1, max: 20, count: 1),
                keyName: 'kit-rand-q-d20', small: true),
            kitToolBtn(context, '随机 5 天', () => _generate(min: 1, max: 365, count: 5),
                keyName: 'kit-rand-q-days', small: true),
            kitToolBtn(context, '抽牌', _drawCard,
                keyName: 'kit-rand-q-card', small: true),
          ],
        ),
        const SizedBox(height: 14),
        kitToolSubCard(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              kitToolSection(
                '历史 · 近 $kKitRandHistMax 组',
                trailing: [
                  kitToolBtn(
                    context,
                    '清空',
                    _hist.isEmpty ? null : _clearHist,
                    keyName: 'kit-rand-hist-clear',
                    small: true,
                    color: Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_hist.isEmpty)
                kitToolNote(_loaded ? '还没有生成记录 · 点「生成」即留痕' : '正在读本机记录…')
              else
                for (final x in _hist)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 58,
                          child: Text(
                            kitRelText(x.ts, now),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            x.paramsText,
                            style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            x.valuesText,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (_hist.isNotEmpty)
                kitToolNote('结果存本机 · 随备份导出'),
            ],
          ),
        ),
      ],
    );
  }
}
