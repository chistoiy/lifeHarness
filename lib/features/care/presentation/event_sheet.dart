import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/care_events.dart';
import '../domain/care_models.dart';
import 'baby_sheets.dart';
import 'care_kit.dart';
import 'care_providers.dart';

/// sheetEventLog 全事件统一录入 / 二次编辑（交接 §2/§5 决策 4、5、6、7、8）。
///
/// 覆盖：母乳亲喂计时/手动双模（左右计时球+分段 seg）、补剂多行一次多条入账、
/// 尿布类型+颜色7点+粘稠4档+量少中多（无称重）、辅食+过敏二级弹层、吸奶、
/// 自定义录入流（名称/单位/固定速记区）、起止与量二次修改、⌨ 键盘输入量。

/// 打开录入弹层。kind=新建事件键；edit=既有记录（二次编辑默认手动模式回填 seg）。
Future<void> showEventLogSheet(BuildContext context,
    {String? kind, CareRecord? edit}) async {
  await showCareSheet<void>(
    context,
    builder: (bc) => _EventLog(kind: kind, edit: edit),
  );
}

class _EventLog extends ConsumerStatefulWidget {
  const _EventLog({this.kind, this.edit});
  final String? kind;
  final CareRecord? edit;

  @override
  ConsumerState<_EventLog> createState() => _EventLogState();
}

class _EventLogState extends ConsumerState<_EventLog> {
  static final List<String> _h24 = [for (var i = 0; i < 24; i++) careP2(i)];
  static final List<String> _m60 = [for (var i = 0; i < 60; i++) careP2(i)];
  static final List<String> _min60 = [for (var i = 0; i < 60; i++) '$i'];

  CareRecord? get src => widget.edit;
  late final String k = src?.k ?? widget.kind ?? 'custom';
  late final EvDef E = () {
    final d = ref.read(careDataProvider).valueOrNull;
    return d?.evOf(k) ?? resolveEv(k, const {});
  }();

  bool get isCus => E.sp == 'cus' || k.startsWith('cus:');
  bool get showAmt =>
      E.amt || isCus || E.sp == 'solid';
  bool get showDia => E.sp == 'dia';
  bool get showSupp => E.sp == 'supp';
  bool get showSolid => E.sp == 'solid';
  bool get isNurse => k == 'nurse';

  // —— 起止 ——
  late int _sh;
  late int _sm;
  late int _eh;
  late int _em;

  // —— 量 ——
  String _unit = 'ml';
  List<String> _amtLabels = const [];
  int _amtIdx = 0;
  bool _kbMode = false;
  final _kbCtl = TextEditingController();

  // —— 尿布 ——
  String _dia = 'pee';
  String _color = '金黄';
  String? _tex;
  String _vol = '中';

  // —— 补剂 ——
  final List<(TextEditingController, TextEditingController)> _supp = [];

  // —— 辅食/自定义/元 ——
  final _solidCtl = TextEditingController();
  final List<AlaHit> _ala = [];
  final _cusCtl = TextEditingController();
  String _cusUnit = 'min';
  bool _pin = false;
  String _recPick = '';
  final _noteCtl = TextEditingController();

  // —— 亲喂双模 ——
  bool _manMode = false; // false=计时 true=手动
  double _accL = 0, _accR = 0;
  String? _runSide;
  DateTime? _runT0;
  Timer? _ticker;
  String? _nurseStart;
  double _manL = 0, _manR = 0;
  (int, int) _lastNurse = (0, 0);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final s = src?.s ?? '${careP2(now.hour)}:${careP2(now.minute)}';
    _sh = int.parse(s.substring(0, 2));
    _sm = int.parse(s.substring(3, 5));
    var eStr = src?.e ?? s;
    if (src == null && (E.dur || k == 'sleep')) {
      final t = careT2m(s) + (E.def ?? 15);
      eStr = '${careP2((t % 1440) ~/ 60)}:${careP2(t % 60)}';
    }
    _eh = int.parse(eStr.substring(0, 2));
    _em = int.parse(eStr.substring(3, 5));

    if (isCus) {
      _cusUnit = src?.unit ?? E.unit ?? 'min';
      _cusCtl.text = src?.name ?? (k.startsWith('cus:') ? E.name : '');
      _buildAmt(_cusUnit, _parseInt(src?.amt) ?? 10);
    } else if (showAmt) {
      _unit = src?.unit ?? E.unit ?? (E.sp == 'solid' ? 'g' : 'ml');
      final v = src?.ml ?? _parseInt(src?.amt) ?? E.def ?? 30;
      _buildAmt(_unit, v);
    } else {
      _unit = E.unit ?? 'min';
      _amtLabels = const [];
    }

    _dia = src?.dia ?? 'pee';
    _color = src?.color ?? '金黄';
    _tex = src?.tex;
    _vol = src?.vol ?? '中';
    if (showSupp) {
      _supp.add((
        TextEditingController(text: src?.name ?? ''),
        TextEditingController(text: src?.amt ?? ''),
      ));
      _supp.add((TextEditingController(), TextEditingController()));
    }
    if (showSolid) {
      _solidCtl.text = src?.name ?? '';
      _ala.addAll(src?.ala ?? const []);
    }
    _recPick = src?.rec ?? '';
    _noteCtl.text = src?.note ?? '';
    if (isNurse) {
      _lastNurse = _parseLastSeg();
      if (src != null) {
        _manMode = true; // 编辑既有记录默认进手动模式回填 seg（决策 6）
        final seg = RegExp(r'左(\d+)′/右(\d+)′').firstMatch(src!.seg ?? '');
        if (seg != null) {
          _manL = double.parse(seg.group(1)!);
          _manR = double.parse(seg.group(2)!);
        }
      }
    }
  }

  int? _parseInt(String? s) => s == null ? null : int.tryParse(s);

  (int, int) _parseLastSeg() {
    final d = ref.read(careDataProvider).valueOrNull;
    if (d == null) return (0, 0);
    final logs = [...d.logs]..sort((a, b) => b.day.compareTo(a.day));
    for (final r in logs) {
      if (r.k == 'nurse' && r.seg != null) {
        final m = RegExp(r'左(\d+)′/右(\d+)′').firstMatch(r.seg!);
        if (m != null) return (int.parse(m.group(1)!), int.parse(m.group(2)!));
      }
    }
    return (0, 0);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _kbCtl.dispose();
    _noteCtl.dispose();
    _solidCtl.dispose();
    _cusCtl.dispose();
    for (final (a, b) in _supp) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  (String, String) get _times => ('${careP2(_sh)}:${careP2(_sm)}', '${careP2(_eh)}:${careP2(_em)}');

  int get _durMin {
    var d = careT2m(_times.$2) - careT2m(_times.$1);
    if (d < 0) d += 1440;
    return d;
  }

  void _buildAmt(String unit, num val) {
    final rg = kAmtRange[unit] ?? kAmtRange['min']!;
    _amtLabels = [for (var v = rg[0]; v <= rg[1]; v += rg[2]) '$v'];
    final target = val.round();
    var bi = 0, bd = 1 << 30;
    for (var i = 0; i < _amtLabels.length; i++) {
      final dist = (int.parse(_amtLabels[i]) - target).abs();
      if (dist < bd) {
        bd = dist;
        bi = i;
      }
    }
    _amtIdx = bi;
    _unit = unit;
  }

  num get _amtVal => _kbMode
      ? (double.tryParse(_kbCtl.text.trim()) ?? 0)
      : (_amtLabels.isEmpty ? 0 : int.parse(_amtLabels[_amtIdx]));

  void _durQuick(int v) {
    final end = (careT2m(_times.$1) + v) % 1440;
    setState(() {
      _eh = end ~/ 60;
      _em = end % 60;
    });
  }

  void _toggleRun(String side) {
    if (_runSide == side) {
      _collectRun();
      setState(() {});
      return;
    }
    _collectRun();
    final now = DateTime.now();
    _nurseStart ??= '${careP2(now.hour)}:${careP2(now.minute)}';
    setState(() {
      _runSide = side;
      _runT0 = now;
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    });
  }

  void _collectRun() {
    if (_runSide != null && _runT0 != null) {
      final add = DateTime.now().difference(_runT0!).inSeconds / 60;
      if (_runSide == '左') {
        _accL += add;
      } else {
        _accR += add;
      }
    }
    _runSide = null;
    _runT0 = null;
    _ticker?.cancel();
    _ticker = null;
  }

  double _live(String side) => _runSide == side && _runT0 != null
      ? DateTime.now().difference(_runT0!).inSeconds / 60
      : 0;

  /// 当前两侧分钟（计时=累计+进行中，手动=滚轮值）。
  (int, int) get _nurseLR => _manMode
      ? (_manL.round(), _manR.round())
      : ((_accL + _live('左')).floor(), (_accR + _live('右')).floor());

  Future<void> _save() async {
    final d = ref.read(careDataProvider).valueOrNull;
    final baby = d?.currentBaby;
    if (d == null || baby == null) {
      if (mounted) AppToast.show(context, '先建立宝宝档案');
      return;
    }
    final repo = ref.read(careRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    if (isNurse) _collectRun();

    // —— 补剂多行先行校验（一次保存多条入账 · 决策 7）——
    List<({String n, String a})>? suppRows;
    if (showSupp) {
      suppRows = _supp
          .map((r) => (n: r.$1.text.trim(), a: r.$2.text.trim()))
          .where((r) => r.n.isNotEmpty || r.a.isNotEmpty)
          .toList();
      if (suppRows.isEmpty) {
        AppToast.show(context, '请先填写至少一条补剂');
        return;
      }
    }

    var (s, e) = _times;
    var dur = _durMin;
    String? seg;
    if (isNurse) {
      final (L, R) = _nurseLR;
      seg = '左$L′/右$R′';
      dur = L + R;
      if (!_manMode) {
        s = _nurseStart ?? s;
        final em = (careT2m(s) + dur) % 1440;
        e = '${careP2(em ~/ 60)}:${careP2(em % 60)}';
      }
    }
    final rec = _recPick.isEmpty ? d.curCarer : _recPick;
    final note = _noteCtl.text.trim();

    CareRecord mk({String? kOverride, String? name, String? amt, int? id, String? day}) => CareRecord(
          id: id,
          babyId: baby.id,
          day: day ?? src?.day ?? careDayKey(DateTime.now()),
          k: kOverride ?? k,
          s: s,
          e: e,
          dur: (E.dur || k == 'sleep' || isNurse)
              ? dur
              : (dur > 0 ? dur : null),
          ml: E.amt && !isCus && E.sp != 'solid' && k != 'supp' && _amtVal > 0
              ? _amtVal.toDouble()
              : null,
          seg: seg,
          dia: showDia ? _dia : null,
          color: showDia && _dia != 'pee' ? _color : null,
          tex: showDia && _dia != 'pee' ? (_tex ?? '糊状') : null,
          vol: showDia && _dia != 'pee' ? _vol : null,
          name: name,
          unit: amt == null ? null : (isCus ? _cusUnit : (E.sp == 'solid' ? 'g' : null)),
          amt: amt,
          note: note.isEmpty ? null : note,
          rec: rec,
          at: src?.at ?? s,
          ala: showSolid && _ala.isNotEmpty ? [..._ala] : null,
        );

    CareRecord base;
    if (showSupp) {
      base = mk(
          name: suppRows!.first.n.isEmpty ? '补剂' : suppRows.first.n,
          amt: suppRows.first.a.isEmpty ? null : suppRows.first.a);
    } else if (showSolid) {
      base = mk(
          name: _solidCtl.text.trim().isEmpty ? '辅食' : _solidCtl.text.trim(),
          amt: _amtVal > 0 ? '${_amtVal.round()}' : null);
    } else if (isCus) {
      base = mk(
          name: _cusCtl.text.trim().isEmpty ? '自定义' : _cusCtl.text.trim(),
          amt: '${_amtVal.round()}');
    } else {
      base = mk();
    }

    if (src != null) {
      // 编辑态以原行 id 为准回写（mk 统一不带 id，防 whereArgs=[null] 空转）。
      final origId = src!.id;
      await repo.updateLog(CareRecord.fromRow(base.toRow()..['id'] = origId));
      if (showSupp) {
        for (final r in suppRows!.skip(1)) {
          await repo.addLog(mk(
              id: null,
              day: src!.day,
              name: r.n.isEmpty ? '补剂' : r.n,
              amt: r.a.isEmpty ? null : r.a));
        }
      }
    } else {
      await repo.addLog(base);
      if (showSupp) {
        for (final r in suppRows!.skip(1)) {
          await repo.addLog(mk(
              name: r.n.isEmpty ? '补剂' : r.n, amt: r.a.isEmpty ? null : r.a));
        }
      }
    }
    // 过敏命中同步落宝宝过敏史（反应非空且未录）
    if (showSolid) {
      for (final a in _ala) {
        if ((a.r?.isNotEmpty ?? false) &&
            !d.allergies.any((x) => x.food == a.f)) {
          await repo.addAllergy(baby.id, a.f, a.r);
        }
      }
    }
    // 固定到速记区（新建自定义录入流）
    if (isCus && k == 'custom' && _pin) {
      final nm = _cusCtl.text.trim();
      if (nm.isNotEmpty) {
        final added = await repo.addCustomEvent(nm, '✨', _cusUnit);
        if (added) {
          final cur = await repo.customEvents();
          final ord = await repo.evOrder(cur);
          // evOrder 已把未入序的自定义键补齐，二次 add 会撞 UNIQUE。
          if (!ord.contains('cus:$nm')) ord.add('cus:$nm');
          await repo.saveEvOrder(ord);
        }
      }
    }
    careTouch(ref);
    if (mounted) Navigator.pop(context);
    if (src != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('✔ 已更新记录（起止/量二次修改生效）'),
            duration: Duration(milliseconds: 1600)));
      return;
    }
    final warn = base.k == 'diaper' && base.color == '砖红'
        ? ' · 砖红色便建议拍照留档并咨询儿科'
        : base.k == 'diaper' && base.color == '灰白'
            ? ' · 灰白便提示就医参考（演示文案）'
            : '';
    final savedName = (isCus && k == 'custom') ? (base.name ?? '自定义') : E.name;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('✔ $savedName已入账 $s~$e$warn'),
          duration: const Duration(milliseconds: 1800)));
  }

  Future<void> _delete() async {
    final repo = ref.read(careRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    await repo.delLog(src!.id!);
    careTouch(ref);
    if (mounted) Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('记录已删除'), duration: Duration(milliseconds: 1500)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final d = ref.watch(careDataProvider).valueOrNull;
    final carers = d?.carers ?? const [];
    final selRec = _recPick.isEmpty ? (d?.curCarer ?? '') : _recPick;
    final (s, e) = _times;
    final dur = _durMin;
    final (tL, tR) = isNurse ? _nurseLR : (0, 0);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(src != null ? careIconOf(src!) : E.icon,
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${E.name}${src != null ? ' · 二次修改' : ''}',
                        style:
                            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                    Text('添加人：${src?.rec ?? d?.curCarer ?? '—'}',
                        style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
              ),
              GestureDetector(
                key: const ValueKey('el-now'),
                onTap: () {
                  final now = DateTime.now();
                  setState(() {
                    _eh = now.hour;
                    _em = now.minute;
                  });
                },
                child: Text('此刻',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: tokens.accent)),
              ),
              if (E.timer && src == null && !isNurse) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  key: const ValueKey('el-timer'),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(feedTimerProvider.notifier).start(k);
                    AppToast.show(
                        context, '${E.icon} ${E.name}计时开始 · 界面可继续做别的');
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: tokens.accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text('🕐 计时',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: tokens.accent)),
                  ),
                ),
              ],
            ],
          ),
          if (!(isNurse && !_manMode))
            Padding(
              key: const ValueKey('el-dur'),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                isNurse
                    ? '时长 ${careHms(tL + tR)}（左$tL′/右$tR′）'
                    : (E.dur || k == 'sleep')
                        ? '时长 ${careHms(dur)}'
                        : (dur > 0 ? '用时 ${dur}min · $s → $e' : '$s → $e'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
            ),
          if (isNurse) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Row(
                    children: [
                      _tab('el-nm-timer', '计时', !_manMode,
                          () => setState(() => _manMode = false)),
                      const SizedBox(width: 6),
                      _tab('el-nm-man', '手动输入', _manMode,
                          () => setState(() => _manMode = true)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!_manMode) ...[
                    const Text('本次两侧总时长',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey)),
                    Text('${tL + tR} 分钟',
                        key: const ValueKey('el-nm-total'),
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: tokens.accent)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _ball('L', '左', tL)),
                        const SizedBox(width: 8),
                        Expanded(child: _ball('R', '右', tR)),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              const Text('左侧分钟',
                                  style: TextStyle(fontSize: 9, color: Colors.grey)),
                              CWheel(
                                key: const ValueKey('el-nl'),
                                labels: _min60,
                                height: 110,
                                initialIndex: _manL.round().clamp(0, 59),
                                onSelect: (i) => setState(() => _manL = i.toDouble()),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            children: [
                              const Text('右侧分钟',
                                  style: TextStyle(fontSize: 9, color: Colors.grey)),
                              CWheel(
                                key: const ValueKey('el-nr'),
                                labels: _min60,
                                height: 110,
                                initialIndex: _manR.round().clamp(0, 59),
                                onSelect: (i) => setState(() => _manR = i.toDouble()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Text('最后使用：左${_lastNurse.$1}′ / 右${_lastNurse.$2}′',
                        style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ],
              ),
            ),
          ],
          if (!(isNurse && !_manMode)) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('起始时间',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey)),
                      Row(
                        children: [
                          Expanded(
                            child: CWheel(
                              key: const ValueKey('el-sh'),
                              labels: _h24,
                              height: 110,
                              initialIndex: _sh,
                              onSelect: (i) => setState(() => _sh = i),
                            ),
                          ),
                          Expanded(
                            child: CWheel(
                              key: const ValueKey('el-sm'),
                              labels: _m60,
                              height: 110,
                              initialIndex: _sm,
                              onSelect: (i) => setState(() => _sm = i),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      const Text('结束时间',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey)),
                      Row(
                        children: [
                          Expanded(
                            child: CWheel(
                              key: const ValueKey('el-eh'),
                              labels: _h24,
                              height: 110,
                              initialIndex: _eh,
                              onSelect: (i) => setState(() => _eh = i),
                            ),
                          ),
                          Expanded(
                            child: CWheel(
                              key: const ValueKey('el-em'),
                              labels: _m60,
                              height: 110,
                              initialIndex: _em,
                              onSelect: (i) => setState(() => _em = i),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (showAmt) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    k == 'water'
                        ? '喝奶/水量（ml）'
                        : '${E.name}量（$_unit）',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey)),
                GestureDetector(
                  key: const ValueKey('el-kb'),
                  onTap: () => setState(() {
                    _kbMode = !_kbMode;
                    if (_kbMode) _kbCtl.text = '$_amtVal';
                  }),
                  child: Text(_kbMode ? '◎ 滚轮选择' : '⌨ 键盘输入',
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey)),
                ),
              ],
            ),
            if (!_kbMode)
              Row(
                children: [
                  GestureDetector(
                    key: const ValueKey('el-amt-minus'),
                    onTap: () => setState(
                        () => _amtIdx = (_amtIdx - 1).clamp(0, _amtLabels.length - 1)),
                    child: Container(
                      width: 28,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: careHex('#f43f5e').withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(9)),
                      child: const Text('◀',
                          style: TextStyle(fontSize: 10, color: Color(0xFFF43F5E))),
                    ),
                  ),
                  Expanded(
                    child: CWheel(
                      key: const ValueKey('el-amt'),
                      labels: _amtLabels,
                      initialIndex: _amtIdx,
                      onSelect: (i) => setState(() => _amtIdx = i),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('el-amt-plus'),
                    onTap: () => setState(
                        () => _amtIdx = (_amtIdx + 1).clamp(0, _amtLabels.length - 1)),
                    child: Container(
                      width: 28,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: careHex('#f43f5e').withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(9)),
                      child: const Text('▶',
                          style: TextStyle(fontSize: 10, color: Color(0xFFF43F5E))),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(_unit,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey)),
                  ),
                ],
              )
            else
              TextField(
                key: const ValueKey('el-amt-kb'),
                controller: _kbCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                decoration: _inp(context, '键盘输入量'),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final q in _quickOptions())
                  CChip(
                    key: ValueKey('el-quick-$q'),
                    label: _fmtQuick(q),
                    dense: true,
                    onTap: () => setState(() {
                      if (E.dur && !E.amt) {
                        _durQuick(q);
                      } else {
                        _buildAmt(_unit, q);
                      }
                    }),
                  ),
              ],
            ),
          ],
          if (showDia) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (v, t) in const [
                  ('pee', '💧 尿尿'),
                  ('poop', '💩 臭臭'),
                  ('mix', '💩+💧 混合'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: CChip(
                      key: ValueKey('el-dia-$v'),
                      label: t,
                      selected: _dia == v,
                      onTap: () => setState(() => _dia = v),
                    ),
                  ),
              ],
            ),
            if (_dia != 'pee') ...[
              const CLabel('颜色', top: 10),
              Row(
                children: [
                  for (final (name, hex) in kPooColors)
                    Expanded(
                      child: GestureDetector(
                        key: ValueKey('el-color-$name'),
                        onTap: () => setState(() => _color = name),
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: _color == name ? 30 : 26,
                              height: _color == name ? 30 : 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: careHex(hex),
                                border: Border.all(
                                    color: _color == name
                                        ? tokens.accent
                                        : Colors.transparent,
                                    width: 2),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(name,
                                style: TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w700,
                                    color: _color == name
                                        ? tokens.accent
                                        : Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const CLabel('粘稠度（婴儿 4 档）', top: 12),
              CSingleRow(
                options: kPooTex,
                selected: _tex ?? '糊状',
                onPick: (v) => setState(() => _tex = v),
              ),
              const CLabel('量估算', top: 12),
              CSingleRow(
                options: const ['少', '中', '多'],
                selected: _vol,
                onPick: (v) => setState(() => _vol = v),
              ),
            ],
          ],
          if (showSupp) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('补剂',
                    style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey)),
                GestureDetector(
                  key: const ValueKey('el-supp-add'),
                  onTap: () => setState(() =>
                      _supp.add((TextEditingController(), TextEditingController()))),
                  child: Text('＋ 添加',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: tokens.accent)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _supp.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  key: ValueKey('el-supp-row-$i'),
                  children: [
                    Expanded(
                      child: TextField(
                        key: ValueKey('el-supp-name-$i'),
                        controller: _supp[i].$1,
                        style: const TextStyle(fontSize: 12),
                        decoration: _inp(context, '输入补剂名称'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('|', style: TextStyle(color: Colors.grey)),
                    ),
                    SizedBox(
                      width: 72,
                      child: TextField(
                        key: ValueKey('el-supp-amt-$i'),
                        controller: _supp[i].$2,
                        style: const TextStyle(fontSize: 12),
                        decoration: _inp(context, '用量'),
                      ),
                    ),
                    GestureDetector(
                      key: ValueKey('el-supp-del-$i'),
                      onTap: () => setState(() {
                        if (_supp.length > 1) {
                          final r = _supp.removeAt(i);
                          r.$1.dispose();
                          r.$2.dispose();
                        }
                      }),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text('×',
                            style: TextStyle(color: Colors.grey, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            const CLabel('常见补剂', top: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in kSuppPresets)
                  CChip(
                    key: ValueKey('el-supp-p-$n'),
                    label: n,
                    dense: true,
                    onTap: () => _suppQuick(n),
                  ),
              ],
            ),
          ],
          if (showSolid) ...[
            const CLabel('辅食名称', top: 12),
            TextField(
              key: const ValueKey('el-solid-name'),
              controller: _solidCtl,
              style: const TextStyle(fontSize: 12),
              decoration: _inp(context, '如：米粉 / 蛋黄泥'),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('宝宝过敏',
                    style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey)),
                GestureDetector(
                  key: const ValueKey('el-ala-add'),
                  onTap: () async {
                    final hit = await showAllergySheet(context, forProfile: false);
                    if (hit != null && !_ala.any((a) => a.f == hit.f)) {
                      if (mounted) setState(() => _ala.add(hit));
                    }
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration:
                        BoxDecoration(color: tokens.cardBorder, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('＋',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: tokens.accent)),
                  ),
                ),
              ],
            ),
            if (_ala.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _ala.length; i++)
                    CChip(
                      key: ValueKey('el-ala-${_ala[i].f}'),
                      label: '${_ala[i].f}${_ala[i].r != null ? '·${_ala[i].r}' : ''} ×',
                      dense: true,
                      selected: true,
                      onTap: () => setState(() => _ala.removeAt(i)),
                    ),
                ],
              ),
          ],
          if (isCus) ...[
            const CLabel('事件名称', top: 12),
            TextField(
              key: const ValueKey('el-cus-name'),
              controller: _cusCtl,
              style: const TextStyle(fontSize: 12),
              decoration: _inp(context, '如：按摩 / 出门散步'),
            ),
            const CLabel('单位（自行选择）'),
            CSingleRow(
              options: const ['分钟', '毫升', '次数', '克', '温度'],
              selected: const {
                'min': '分钟',
                'ml': '毫升',
                '次': '次数',
                'g': '克',
                '°C': '温度'
              }[_cusUnit],
              onPick: (v) {
                final map = const {
                  '分钟': 'min',
                  '毫升': 'ml',
                  '次数': '次',
                  '克': 'g',
                  '温度': '°C'
                };
                setState(() {
                  _cusUnit = map[v]!;
                  _buildAmt(_cusUnit, _amtVal);
                });
              },
            ),
            if (k == 'custom')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('固定到速记区（可排序）', style: TextStyle(fontSize: 12)),
                    CToggle(
                        key: const ValueKey('el-cus-pin'),
                        label: '固定到速记区',
                        on: _pin,
                        onChanged: (v) => setState(() => _pin = v)),
                  ],
                ),
              ),
          ],
          const CLabel('记录人', top: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in carers)
                CChip(
                  key: ValueKey('el-rec-${c.name}'),
                  label: c.name,
                  dense: true,
                  selected: selRec == c.name,
                  onTap: () => setState(() => _recPick = c.name),
                ),
            ],
          ),
          const CLabel('备注'),
          TextField(
            key: const ValueKey('el-note'),
            controller: _noteCtl,
            style: const TextStyle(fontSize: 12),
            decoration: _inp(context, '可选'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (src != null) ...[
                Expanded(
                  child: TextButton(
                    key: const ValueKey('el-del'),
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                      backgroundColor: careHex('#f43f5e').withValues(alpha: .12),
                      foregroundColor: careHex('#f43f5e'),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('删除'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const ValueKey('el-save'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('起止与量均可二次修改 · 滑动滚轮快选 · 时长自动计算',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  List<int> _quickOptions() {
    if (E.dur && !E.amt) return E.quick.isEmpty ? [5, 10, 15, 30, 60] : E.quick;
    return E.quick.isEmpty ? [10, 30, 50, 100, 150, 200] : E.quick;
  }

  String _fmtQuick(int q) =>
      (E.dur && !E.amt) ? (q >= 60 ? '${q ~/ 60}h' : '${q}min') : '$q';

  void _suppQuick(String n) {
    for (final r in _supp) {
      if (r.$1.text.trim().isEmpty) {
        r.$1.text = n;
        setState(() {});
        return;
      }
    }
    setState(() => _supp.add((TextEditingController(text: n), TextEditingController())));
  }

  Widget _tab(String key, String t, bool on, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          key: ValueKey(key),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: on ? context.tokens.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(t,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.white : Colors.grey)),
          ),
        ),
      );

  Widget _ball(String tag, String side, int shown) {
    final tokens = context.tokens;
    final running = _runSide == side;
    final last = tag == 'L' ? _lastNurse.$1 : _lastNurse.$2;
    return GestureDetector(
      key: ValueKey('el-ball-$tag'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleRun(side),
      child: Container(
        height: 104,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: running
              ? tokens.accent.withValues(alpha: .08)
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
              color: running ? tokens.accent : tokens.cardBorder, width: 2),
        ),
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 8,
              child: Text('上次 $side$last′',
                  style: const TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey)),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 10),
                Text('$side侧',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                Text('$shown′',
                    style:
                        const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(running ? '⏸ 停止' : (_runSide != null ? '⇄ 换边' : '▶ 开始'),
                    style: TextStyle(fontSize: 8.5, color: tokens.accent)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _inp(BuildContext context, String hint) {
  final tokens = context.tokens;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.cardBorder)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.cardBorder)),
  );
}
