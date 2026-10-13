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

class _ExportSheetState extends ConsumerState<ExportSheet> {
  final Set<String> _modules = {}; // 空 = 全部数据
  bool _assets = true;
  bool _md = true;
  String _fmt = 'lhbak';
  bool _busy = false;

  /// 预估缓存（进弹层算一次；切模块/开关重算——COUNT 全表 sqlite 毫秒级）。
  ({int bytes, bool empty})? _estimate;

  bool get _all => _modules.isEmpty;
  bool get _mdAvailable => exportMdAvailable(_modules);

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
      if (!_all) {
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
          final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM "$t"');
          final c = rows.isEmpty ? 0 : (rows.first['c'] as int? ?? 0);
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
            // ---- ② 内容 ----
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
            // ---- ③ 格式 ----
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
                          TextStyle(fontSize: 11.5, color: Color(0xFFB45309))),
                ),
              ),
            const SizedBox(height: 14),
            // ---- ④ 导出位置（V1.66 装机回知批·原型同步）----
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
            // ---- ④ 底栏 ----
            Row(
              children: [
                Expanded(
                  child: Text(
                    _busy
                        ? '正在导出…'
                        : empty
                            ? '所选范围暂无数据'
                            : '$_summaryLabel$_sizeLine',
                    style: TextStyle(
                        fontSize: 12,
                        color: empty ? Colors.grey : null,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton(
                  key: const ValueKey('ex-go'),
                  onPressed: _busy || empty ? null : _doExport,
                  child: Text(_busy
                      ? '正在导出…'
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
