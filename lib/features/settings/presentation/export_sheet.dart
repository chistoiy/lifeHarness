/// 备份格式四件套批2 ·「导出数据」页内弹层（原型 `sheetExport`·挂数据与同步屏）。
///
/// 口径（需求清单 V1.66 / 工单批2 面板）：
/// - 范围＝「全部数据」快捷（单选语义，`modules=[]`）＋ 12 模块 chips 多选；
/// - 内容＝含图片附件（带预估体积）＋ 附可读 Markdown（无笔记类模块置灰）；
/// - 格式两档＝`.lhbak`（可恢复包·含投影成员）／ 可读目录（md+csv+json 树）；
/// - 非全量选 `.lhbak` 出提示行「子集包暂不能直接恢复，仅作数据出口」；
/// - 面板开关是**瞬时 UI 状态，不持久化**（原型拍板·L963 注释）；
/// - 时间维度与子集合并恢复不立项于本版（需求清单 V1.66 末句）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/backup/backup_service.dart';
import '../../../core/backup/lh_bak.dart' show LhBakException;
import '../../../core/logging/app_log.dart';
import '../../../core/platform/saf_tree.dart';
import '../../../core/providers.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/backup_read_export.dart';
import '../../../shared/linkage/export_units.dart';
import '../../../shared/widgets/lh_wheel.dart';
import '../../../shared/widgets/ui_kit.dart';

/// 打开「导出数据」弹层。[withLogs] 由调用方（备份半屏的日志勾选）透传。
Future<void> showExportSheet(BuildContext context, {bool withLogs = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ExportSheet(withLogs: withLogs),
  );
}

class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key, this.withLogs = false});

  final bool withLogs;

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

/// 面板警示色（全仓既有琥珀 `0xFFB45309`，UI组件规范〇B 同语义色同源：
/// 散成多枚字面量既撞色值棘轮，也迟早走偏）。
const Color _amber = Color(0xFFB45309);

class _ExportSheetState extends ConsumerState<ExportSheet> {
  final Set<String> _modules = {}; // 空 = 全部数据
  bool _assets = true;
  bool _md = true;
  String _fmt = 'lhbak';
  bool _busy = false;

  // ---- 余量批3 · 时间维度（产品拍板 2026-10-15 A2 四档）----
  /// `all` / `y1` / `y3` / `custom`；`all` 不筛也不写 manifest.scope。
  String _time = 'all';
  DateTime _from = DateTime.now().subtract(const Duration(days: 365));
  DateTime _to = DateTime.now();

  /// 预估缓存（进弹层算一次；切模块/开关重算——COUNT 全表 sqlite 毫秒级）。
  ({int bytes, bool empty})? _estimate;

  bool get _all => _modules.isEmpty;
  bool get _mdAvailable => exportMdAvailable(_modules);

  // ---- 时间维度派生 ----

  /// 解析后的闭区间（起 00:00:00.000 止 23:59:59.999，含端点）。
  /// **null ≠ 非法**：「全部」档也返回 null（＝不施加任何时间过滤，合法）；
  /// 自定义档止早于起才是真非法，由 [_timeBlocked] 单独判（两者语义不可混：
  /// 混了会把默认态的主钮误禁掉）。
  ({DateTime from, DateTime to})? get _range {
    if (_time == 'all') return null;
    final now = DateTime.now();
    final r = switch (_time) {
      'y1' => (
          from: DateTime(now.year - 1, now.month, now.day),
          to: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        ),
      'y3' => (
          from: DateTime(now.year - 3, now.month, now.day),
          to: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        ),
      _ => null,
    };
    if (r != null) return r;
    if (_timeBlocked) return null;
    return (
      from: DateTime(_from.year, _from.month, _from.day),
      to: DateTime(_to.year, _to.month, _to.day, 23, 59, 59, 999),
    );
  }

  /// 自定义档止日期早于起日期＝区间非法（主钮禁用并出琥珀提示）。
  bool get _timeBlocked => _time == 'custom' && _to.isBefore(_from);

  /// 所选范围里不可按时间筛选的单元（原型 EX_NOTIME 口径：明说而非静默忽略）。
  List<String> get _unfilterable => _time == 'all'
      ? const []
      : exportTimeUnfilterableLabels(_modules);

  String get _timeLabel {
    if (_time == 'all') return '';
    if (_time == 'y1') return '近 1 年';
    if (_time == 'y3') return '近 3 年';
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    return '${d(_from)} ~ ${d(_to)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reestimate());
  }

  Future<void> _reestimate() async {
    final svc = ref.read(backupServiceProvider);
    try {
      final db = await svc.db();
      final keepDirs =
          _all ? null : exportAttachDirsForModules(_modules);
      var attach = 0;
      for (final d in svc.attachDirs) {
        if (keepDirs != null && !keepDirs.contains(p.basename(d))) continue;
        final dir = Directory(d);
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          try {
            attach += f.lengthSync();
          } catch (_) {}
        }
      }
      var dbBytes = 0;
      try {
        // 6120 装机回知修正：DB 腿＝快照剔除恒排除表后 gzip 实测（wal 已并入
        // 快照），与实包同口径；活库九成七是可再生索引，按原文件预估会把
        // 2.5MB 实包说成 37MB。测量失败退回原文件粗估。
        dbBytes = await svc.measureIncludedDbBytes(db);
      } catch (_) {
        try {
          final dbFile = File(db.path);
          if (dbFile.existsSync()) dbBytes = dbFile.lengthSync();
          final wal = File('${db.path}-wal');
          if (wal.existsSync()) dbBytes += wal.lengthSync();
        } catch (_) {}
      }
      var empty = false;
      final range = _range;
      final timeTables = range == null
          ? const <String, ExportTimeFilter>{}
          : exportTimeFilters(_modules, from: range.from, to: range.to);
      if (!_all || range != null) {
        final tables = exportTablesForModules(_modules);
        // 分母只数实包会装的表（恒排除表不计），比例才不被可再生表稀释。
        final excluded = svc.estimateExcludedTables().toSet();
        var selected = 0;
        var totalRows = 0;
        final live = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%'");
        for (final r in live) {
          final t = r['name'] as String;
          if (excluded.contains(t)) continue;
          // 余量批3：命中时间谓词的表改走 COUNT(谓词)——行数占比才是真占比。
          final filt = timeTables[t];
          var c = 0;
          if (filt == null) {
            final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM "$t"');
            c = rows.isEmpty ? 0 : (rows.first['c'] as int? ?? 0);
          } else {
            try {
              final rows = await db.rawQuery(
                  'SELECT COUNT(*) AS c FROM "$t" WHERE ${filt.whereSql}',
                  filt.args);
              c = rows.isEmpty ? 0 : (rows.first['c'] as int? ?? 0);
            } catch (_) {
              c = 0;
            }
          }
          totalRows += c;
          if (tables.contains(t)) selected += c;
        }
        empty = selected == 0;
        // 子集 DB 粗估＝实测基线 × 行数占比（UI 带「约」，不做逐表字节扫描）。
        dbBytes =
            totalRows == 0 ? 0 : (dbBytes * selected / totalRows).round();
      }
      if (mounted) {
        setState(() => _estimate = (bytes: attach + dbBytes, empty: empty));
      }
    } catch (e) {
      AppLog.add('导出体积预估失败（按不可估展示）：$e', level: LhLevel.warn);
      if (mounted) setState(() => _estimate = null);
    }
  }

  String get _sizeLine {
    final est = _estimate;
    if (est == null) return '';
    final mb = est.bytes / (1024 * 1024);
    if (mb < 0.05) return '';
    return mb < 0.1 ? ' · 约 0.1 MB' : ' · 约 ${mb.toStringAsFixed(1)} MB';
  }

  String get _summaryLabel => _all ? '全部数据' : '${_modules.length} 模块';

  /// 时间段提示行：自定义档起止颠倒时出琥珀警示；否则若范围里有不可筛
  /// 单元（AI 记录）出灰字明说——**明说而非静默忽略**（原型 EX_NOTIME）。
  String? get _timeNote {
    if (_time == 'all') return null;
    if (_timeBlocked) return '起止时间不合法（止日期须不早于起日期）';
    if (_unfilterable.isEmpty) return null;
    return '${_unfilterable.join('、')} 无时间字段，不按时间筛选';
  }

  /// 自定义区间就地滚轮（红线：时间输入禁两段式弹层）。
  Widget _customRange() {
    final now = DateTime.now();
    final years = List.generate(12, (i) => '${now.year - 10 + i}');
    final months = List.generate(12, (i) => '${i + 1}'.padLeft(2, '0'));
    final days = List.generate(31, (i) => '${i + 1}'.padLeft(2, '0'));
    Widget col(String label, List<String> labels, int value, String prefix,
            void Function(int) onSel) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.w700)),
              SizedBox(
                height: 96,
                child: LHWheel(
                  labels: labels,
                  initialIndex: value.clamp(0, labels.length - 1),
                  keyPrefix: prefix,
                  height: 96,
                  itemExtent: 26,
                  onSelect: onSel,
                ),
              ),
            ],
          ),
        );
    return Container(
      key: const ValueKey('ex-time-custom'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        // 中性底，**不用 `g1`**（g1 是主题主色变量，铺满色块＝深浅两态都炸，
        // 且滚轮选中项本身也是主色 ⇒ 主色底＋主色字＝对比度崩）。原型口径＝
        // `bg-slate-50 dark:bg-slate-800/50`，对应 `tokens.cardBorder`（深浅自适应）。
        // 全仓其余 `tokens.g1` 用法都带 alpha（.2/.3）作淡底，此处曾是不透明孤例。
        color: context.tokens.cardBorder,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('起',
                    style: TextStyle(
                        fontSize: 9.5,
                        color: Colors.grey,
                        fontWeight: FontWeight.w700)),
                Row(children: [
                  col('年', years, years.indexOf('${_from.year}'), 'ex-from-y',
                      (i) => _setFrom(years[i], null, null)),
                  col('月', months, _from.month - 1, 'ex-from-m',
                      (i) => _setFrom(null, months[i], null)),
                  col('日', days, _from.day - 1, 'ex-from-d',
                      (i) => _setFrom(null, null, days[i])),
                ]),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 26),
            child: Text('→',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('止',
                    style: TextStyle(
                        fontSize: 9.5,
                        color: Colors.grey,
                        fontWeight: FontWeight.w700)),
                Row(children: [
                  col('年', years, years.indexOf('${_to.year}'), 'ex-to-y',
                      (i) => _setTo(years[i], null, null)),
                  col('月', months, _to.month - 1, 'ex-to-m',
                      (i) => _setTo(null, months[i], null)),
                  col('日', days, _to.day - 1, 'ex-to-d',
                      (i) => _setTo(null, null, days[i])),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _setFrom(String? y, String? m, String? d) {
    setState(() {
      _from = DateTime(
          int.tryParse(y ?? '${_from.year}') ?? _from.year,
          int.tryParse(m ?? '${_from.month}') ?? _from.month,
          int.tryParse(d ?? '${_from.day}') ?? _from.day,
          _from.hour, _from.minute);
    });
    _reestimate();
  }

  void _setTo(String? y, String? m, String? d) {
    setState(() {
      _to = DateTime(
          int.tryParse(y ?? '${_to.year}') ?? _to.year,
          int.tryParse(m ?? '${_to.month}') ?? _to.month,
          int.tryParse(d ?? '${_to.day}') ?? _to.day,
          _to.hour, _to.minute);
    });
    _reestimate();
  }

  /// 导出位置：系统目录树选择（持久授权），选择后导出直达该目录。
  Future<void> _pickLoc() async {
    final uri = await safPickTree();
    if (uri == null) return; // 取消不动现值
    await ref.read(backupServiceProvider).setExportTree(uri);
    if (mounted) setState(() {});
  }

  Future<void> _doExport() async {
    if (_busy) return;
    setState(() => _busy = true);
    final svc = ref.read(backupServiceProvider);
    try {
      if (_fmt == 'lhbak') {
        final res = await svc.exportBackup(
          withLogs: widget.withLogs,
          withAttachments: _assets,
          modules: _modules.toList(),
          withProjection: true,
          withMd: _md && _mdAvailable,
          timeRange: _range,
        );
        var line = '已导出：${p.basename(res.file.path)}';
        // 设了导出位置＝导出直达：包拷入持久 SAF 目录树（应用目录原包保留）。
        final tree = svc.exportTreeUri;
        if (tree != null) {
          final w = await safCreateInTree(
              tree: tree,
              relPath: '',
              name: p.basename(res.file.path),
              text: '',
              mime: 'application/zip',
              srcPath: res.file.path);
          if (w.ok) {
            line = '已导出：${w.name} · ${svc.exportTreeName}';
          } else {
            AppLog.add('导出位置写入失败（包保留在应用目录）：${w.code}',
                level: LhLevel.warn);
          }
        }
        if (mounted) AppToast.show(context, line);
      } else {
        final db = await svc.db();
        final docsRoot = p.dirname(svc.exportDir());
        final ts = DateTime.now();
        String two(int n) => n.toString().padLeft(2, '0');
        final outDir = p.join(
            docsRoot,
            'exports',
            'lifeharness_readable_'
                '${ts.year}${two(ts.month)}${two(ts.day)}'
                '_${two(ts.hour)}${two(ts.minute)}${two(ts.second)}');
        final rep = await exportReadableTree(
          db: db,
          outDir: outDir,
          moduleIds: _modules,
          assets: _assets,
          md: _md && _mdAvailable,
          attachDirs: svc.attachDirs,
          settingsMap:
              SettingsRepository(ref.read(sharedPreferencesProvider))
                  .exportAll(),
          timeRange: _range,
        );
        if (mounted) {
          AppToast.show(context,
              rep.error.isNotEmpty ? rep.line : '${rep.line} · 见 ${p.basename(outDir)}');
        }
      }
      if (mounted) Navigator.pop(context);
    } on LhBakException catch (e) {
      if (mounted) AppToast.show(context, '导出失败：${e.code}');
    } catch (e) {
      AppLog.add('导出数据异常（面板兜底）：$e', level: LhLevel.error);
      if (mounted) AppToast.show(context, '导出失败，详情见日志');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final est = _estimate;
    final empty = est?.empty ?? false;
    final warn = !_all && _fmt == 'lhbak';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('导出数据',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  key: const ValueKey('ex-close'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('db.sqlite 恢复权威 · md 与配置为投影 · 新包纯明文',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 14),
            // ---- ① 范围 ----
            const Text('范围',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                    key: 'ex-chip-all',
                    label: '全部数据',
                    on: _all,
                    onTap: () {
                      setState(() => _modules.clear());
                      _reestimate();
                    }),
                for (final u in kExportUnits)
                  _chip(
                      key: 'ex-chip-${u.id}',
                      label: u.label,
                      on: _modules.contains(u.id),
                      onTap: () {
                        setState(() {
                          if (_all) {
                            // 全部 → 单选该模块（原型互斥口径）
                            _modules
                              ..clear()
                              ..add(u.id);
                          } else if (_modules.contains(u.id)) {
                            _modules.remove(u.id);
                          } else {
                            _modules.add(u.id);
                          }
                        });
                        _reestimate();
                      }),
              ],
            ),
            const SizedBox(height: 4),
            Text(_all ? '全部模块' : '已选 ${_modules.length} 个模块',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 12),
            // ---- ② 时间（余量批3）----
            const Text('时间',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in const [
                  ('all', '全部'),
                  ('y1', '近 1 年'),
                  ('y3', '近 3 年'),
                  ('custom', '自定义'),
                ])
                  _chip(
                      key: 'ex-time-${t.$1}',
                      label: t.$2,
                      on: _time == t.$1,
                      onTap: () {
                        setState(() => _time = t.$1);
                        _reestimate();
                      }),
              ],
            ),
            if (_time == 'custom') ...[
              const SizedBox(height: 8),
              _customRange(),
            ],
            if (_timeNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_timeNote!,
                    key: const ValueKey('ex-time-note'),
                    style: TextStyle(
                        fontSize: 10.5,
                        color: _timeBlocked ? _amber : Colors.grey)),
              ),
            const SizedBox(height: 12),
            // ---- ③ 内容 ----
            const Text('内容',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            SwitchListTile(
              key: const ValueKey('ex-asset-tgl'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _assets,
              onChanged: (v) => setState(() => _assets = v),
              title: const Text('含图片附件', style: TextStyle(fontSize: 13)),
            ),
            SwitchListTile(
              key: const ValueKey('ex-md-tgl'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _md && _mdAvailable,
              onChanged: _mdAvailable
                  ? (v) => setState(() => _md = v)
                  : (v) => AppToast.show(
                      context, '所选模块无笔记类数据，Markdown 投影不可用'),
              title: const Text('附可读 Markdown', style: TextStyle(fontSize: 13)),
              subtitle: const Text('笔记 / 书摘 / 导图投影 · 恢复以数据库为准',
                  style: TextStyle(fontSize: 10.5)),
            ),
            const SizedBox(height: 8),
            // ---- ④ 格式 ----
            const Text('格式',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SegRow<String>(
              keyPrefix: 'ex-fmt',
              items: const [
                (id: 'lhbak', label: '.lhbak 可恢复'),
                (id: 'dir', label: '可读目录 md+csv+json'),
              ],
              value: _fmt,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _fmt = v),
            ),
            if (warn)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  key: const ValueKey('ex-scope-warn'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('子集包暂不能直接恢复，仅作数据出口',
                      style:
                          TextStyle(fontSize: 11.5, color: _amber)),
                ),
              ),
            const SizedBox(height: 14),
            // ---- ⑤ 导出位置（V1.66 装机回知批·原型同步）----
            const Text('导出位置',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            GestureDetector(
              key: const ValueKey('ex-loc-row'),
              onTap: _busy ? null : _pickLoc,
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 13),
                        children: [
                          const TextSpan(text: '导出直达所选目录 '),
                          TextSpan(
                            text: ref
                                    .watch(backupServiceProvider)
                                    .exportTreeName ??
                                '默认 · 应用目录',
                            style: const TextStyle(
                                fontSize: 10.5, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text('变更',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: tokens.accent)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // ---- 底栏 ----
            Row(
              children: [
                Expanded(
                  child: Text(
                    _busy
                        ? '正在导出…'
                        : empty
                            ? '所选范围暂无数据'
                            : '$_summaryLabel${_timeLabel.isEmpty ? '' : ' · $_timeLabel'}$_sizeLine',
                    style: TextStyle(
                        fontSize: 12,
                        color: empty ? Colors.grey : null,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton(
                  key: const ValueKey('ex-go'),
                  onPressed: _busy || empty || _timeBlocked ? null : _doExport,
                  child: Text(_busy
                      ? '正在导出…'
                      : _timeBlocked
                          ? '请选起止时间'
                          : _all && _fmt == 'lhbak'
                              ? '导出备份'
                              : '导出'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
      {required String key, required String label, required bool on, required VoidCallback onTap}) {
    final tokens = context.tokens;
    return GestureDetector(
      key: ValueKey(key),
      onTap: _busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? tokens.accent.withValues(alpha: .14) : tokens.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: on ? tokens.accent : tokens.cardBorder),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? tokens.accent : null)),
      ),
    );
  }
}
