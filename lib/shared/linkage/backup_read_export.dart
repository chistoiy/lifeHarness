/// 备份格式四件套批2 ·「可读目录」导出（格式第二档，评估件 §8.4 档①）。
///
/// 口径（需求清单 V1.66 / 工单批2 面板钉子5）：
/// - 落点＝`<docs>/exports/lifeharness_readable_<ts>/`，改扩展名即可读，
///   不进恢复链（子集包口径同源：**这是数据出口，不是恢复源**）；
/// - 结构：`config/settings.json` ＋ `notes/` md 投影（与包内同源，见
///   [buildNoteProjectionMembers]）＋ 模块投影器（记账/健康复用既有领域
///   导出器＝「收编」，其余模块 `data/<表>.json` 通用投影）＋ `attachments/`
///   拷贝（开关）；
/// - **既有模块内深度导出入口不动**（记账 p-export 整屏、笔记「导出为本地
///   目录」，评估件 §9.6）——本件是聚合侧的投影出口。
///
/// 落位 shared/linkage：要吃 ledger/health 的 data 层仓库（R1 禁 features
/// 互 import，聚合层唯一合法落点）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/database/schema.dart';
import '../../core/database/schema/health.dart' as healthschema;
import '../../core/logging/app_log.dart';
import '../../features/health/data/health_repository.dart';
import '../../features/health/domain/health_export.dart'
    show writeHealthExportFile;
import '../../features/ledger/data/ledger_repository.dart';
import '../../features/ledger/domain/ledger_export.dart'
    show writeLedgerExportFile;
import 'backup_projection.dart';
import 'export_units.dart';

/// 日键本地别名（`export_units.dayKey` 与 health 域同名，避开歧义导入）。
String exportDayKey(DateTime d) => dayKey(d);

/// 可读目录导出报告（toast 汇总句的唯一文案源；失败必须出声）。
class ReadableExportReport {
  const ReadableExportReport({
    required this.dir,
    required this.files,
    this.error = '',
  });

  final String dir;
  final int files;

  /// ''＝成功；非空＝人话成因（目录建不出/投影全失败等）。
  final String error;

  String get line => error.isNotEmpty
      ? '导出失败：$error'
      : '已导出可读目录 · $files 个文件';
}

/// 文件名净化：路径非法字符换 `-`（目录名同 note_export 文件名口径）。
String _sanitize(String name) =>
    name.replaceAll(RegExp(r'[/\\:*?"<>|\r\n\t]'), '-').trim();

/// 导出「可读目录」树。[moduleIds] 空 = 全部数据。
///
/// 单投影腿失败降级 warn + 跳过（投影是只读增值件），全失败才 error。
Future<ReadableExportReport> exportReadableTree({
  required Database db,
  required String outDir,
  required Set<String> moduleIds,
  required bool assets,
  required bool md,
  List<String> attachDirs = const [],
  Map<String, Object?>? settingsMap,
  DateTime? now,
  /// 余量批3 · 时间维度：与 `.lhbak` 包**同源同谓词**（可读目录不得
  /// 比包多出数据，否则「导出范围」这条承诺在两档格式下不一致）。
  ({DateTime from, DateTime to})? timeRange,
}) async {
  final ts = now ?? DateTime.now();
  // 逐表谓词（恒全量表不在其中＝不施加任何 WHERE）。
  final filters = timeRange == null
      ? const <String, ExportTimeFilter>{}
      : exportTimeFilters(moduleIds,
          from: timeRange.from, to: timeRange.to);
  Future<List<Map<String, Object?>>> readTable(String t) async {
    final f = filters[t];
    if (f == null) return db.query(t);
    return db.rawQuery('SELECT * FROM "$t" WHERE ${f.whereSql}', f.args);
  }
  try {
    Directory(outDir).createSync(recursive: true);
  } catch (e) {
    return ReadableExportReport(dir: outDir, files: 0, error: '目录建不出来');
  }
  var files = 0;
  void count(String path) {
    if (File(path).existsSync()) files++;
  }

  // 1) config/settings.json（口径设置·零凭据，与包内同源）。
  if (settingsMap != null) {
    try {
      final f = File(p.join(outDir, 'config', 'settings.json'));
      await f.create(recursive: true);
      await f.writeAsString(
          const JsonEncoder.withIndent('  ').convert(settingsMap));
      count(f.path);
    } catch (e) {
      AppLog.add('可读目录 config 落盘失败：$e', level: LhLevel.warn);
    }
  }

  // 2) notes/ md 投影（与包内同源；md 开关关＝跳过）。
  if (md) {
    try {
      final members = await buildNoteProjectionMembers(db,
          moduleIds: moduleIds, timeFilters: filters);
      for (final e in members.entries) {
        final f = File(p.join(outDir, p.joinAll(e.key.split('/'))));
        await f.create(recursive: true);
        await f.writeAsString(e.value);
        count(f.path);
      }
    } catch (e) {
      AppLog.add('可读目录 notes 投影失败：$e', level: LhLevel.warn);
    }
  }

  final all = moduleIds.isEmpty;
  final wantLedger = all || moduleIds.contains('ledger');
  final wantHealth = all || moduleIds.contains('health');

  // 记账/健康投影的时间日界（`YYYY-MM-DD` 文本日闭区间，与包内 TEXT 日列同口径）。
  final df = timeRange == null ? null : exportDayKey(timeRange.from);
  final dt = timeRange == null ? null : exportDayKey(timeRange.to);

  // 3) 记账投影器（收编：逐账本复用 writeLedgerExportFile，csv+json）。
  // catName/acctName 预取成同步映射（writer 的回调是同步签名）。
  if (wantLedger) {
    try {
      final repo = LedgerRepository(db);
      final books = await db.query(DbSchema.tLedgerBooks, orderBy: 'id ASC');
      final acctName = <int, String>{
        for (final r in await db.query(DbSchema.tLedgerAccounts))
          r['id']! as int: (r['name'] as String?) ?? '账户',
      };
      final catName = <int, String>{
        for (final r in await db.query(DbSchema.tLedgerCategories))
          r['id']! as int: (r['name'] as String?) ?? '其他',
      };
      for (final b in books) {
        final bk = b['id']! as int;
        final label = _sanitize((b['name'] as String?) ?? '账本$bk');
        final dir = p.join(outDir, 'ledger', label);
        // 写入器假定目录已存在（原调用方=记账导出页自备目录）——聚合侧自建。
        Directory(dir).createSync(recursive: true);
        for (final fmt in const ['csv', 'json']) {
          final r = await writeLedgerExportFile(
            dir: dir,
            fmt: fmt,
            fetchPage: (offset, limit) => repo.exportTxnsPage(bk,
                offset: offset, limit: limit, dateFrom: df, dateTo: dt),
            catName: (id) =>
                id == null ? '其他' : (catName[id] ?? '其他'),
            acctName: (id) => id == null ? '其他' : (acctName[id] ?? '其他'),
          );
          count(r.path);
        }
      }
    } catch (e) {
      AppLog.add('可读目录记账投影失败：$e', level: LhLevel.warn);
    }
  }

  // 4) 健康投影器（收编：复用 HealthRepository.exportRows + writeHealthExportFile）。
  if (wantHealth) {
    try {
      final profiles =
          await db.query(healthschema.tHealthProfile, limit: 1);
      if (profiles.isNotEmpty) {
        final pid = profiles.first['id']! as int;
        final repo = HealthRepository(db);
        final rows =
            await repo.exportRows(pid, df ?? '0000-01-01', dt ?? exportDayKey(ts));
        final dir = p.join(outDir, 'health');
        Directory(dir).createSync(recursive: true);
        for (final fmt in const ['csv', 'json']) {
          final r = await writeHealthExportFile(
              dir: dir, fmt: fmt, rows: rows, now: ts);
          count(r.path);
        }
      }
    } catch (e) {
      AppLog.add('可读目录健康投影失败：$e', level: LhLevel.warn);
    }
  }

  // 5) 其余所选模块通用投影：data/<表>.json（整表直读；空表也写空数组＝
  // 「导了但没数据」的实话形态，不许静默缺文件）。
  final units = all
      ? kExportUnits
      : [
          for (final id in moduleIds)
            if (exportUnitById(id) != null) exportUnitById(id)!,
        ];
  for (final u in units) {
    if (u.id == 'ledger' || u.id == 'health') continue; // 走专属投影器
    for (final t in u.tables) {
      try {
        final rows = await readTable(t);
        final f = File(p.join(outDir, 'data', u.id, '$t.json'));
        await f.create(recursive: true);
        await f.writeAsString(
            const JsonEncoder.withIndent('  ').convert(rows));
        count(f.path);
      } catch (e) {
        AppLog.add('可读目录通用投影失败（$t）：$e', level: LhLevel.warn);
      }
    }
  }

  // 6) attachments/ 拷贝（开关；子集只拷所选模块映射目录——与打包同口径）。
  if (assets) {
    final keepDirs = all ? null : exportAttachDirsForModules(moduleIds);
    for (final dirPath in attachDirs) {
      final base = p.basename(dirPath);
      if (keepDirs != null && !keepDirs.contains(base)) continue;
      final src = Directory(dirPath);
      if (!src.existsSync()) continue;
      try {
        for (final f in src.listSync(recursive: true).whereType<File>()) {
          final rel = p.relative(f.path, from: dirPath);
          final dst = File(p.join(outDir, 'attachments', base, rel));
          await dst.create(recursive: true);
          await f.copy(dst.path);
          files++;
        }
      } catch (e) {
        AppLog.add('可读目录附件拷贝失败（$base）：$e', level: LhLevel.warn);
      }
    }
  }

  return ReadableExportReport(dir: outDir, files: files);
}
