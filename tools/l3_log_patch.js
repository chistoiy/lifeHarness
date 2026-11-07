/* L3 日志批 · 记账 / 待办 / 日程 补日志覆盖（只加日志，零行为改动）
   口径来源：docs/日志覆盖工单-20260929.md §三 L3 行（导入批次结果 · 账单解析失败 · 逾期扫描异常）
   用法：node tools/l3_log_patch.js
   护栏：每条编辑按命中次数断言（不符即中止）；文件体积变化逐条打印供核对。 */
const fs = require("fs");

function load(F) {
  const s = fs.readFileSync(F, "utf8");
  const crlf = s.includes("\r\n");
  return { s, nl: (t) => (crlf ? t.replace(/\n/g, "\r\n") : t) };
}

function apply(edits) {
  let bad = 0, hits = 0;
  for (const [F, old0, new0, want] of edits) {
    if (!fs.existsSync(F)) { console.error("!! 文件不存在 " + F); process.exit(1); }
    const { s, nl } = load(F);
    const old_ = nl(old0), neu = nl(new0);
    const n = s.split(old_).length - 1;
    if (n !== want) {
      console.error("!! [" + F + "] 命中 " + n + " 次，期望 " + want + "\n   锚点：" + old0.split("\n")[0].trim().slice(0, 70));
      bad++;
      continue;
    }
    const before = s.length;
    fs.writeFileSync(F, s.split(old_).join(neu));
    hits += want;
    console.log("OK  " + F.replace(/^lib\//, "") + "  +" + (neu.length - old_.length) + "B");
  }
  if (bad) { console.error("!! " + bad + " 条未命中，未应用的请重跑前先查锚点"); process.exit(1); }
  console.log("完成：共应用 " + hits + " 处编辑");
}

const AL = "import '../../../core/logging/app_log.dart';\n";

apply([
  // ---------- 记账 · 解析层 ----------
  ["lib/features/ledger/data/bill_parser.dart",
   "import 'package:enough_convert/gbk.dart';\nimport 'package:spreadsheet_decoder/spreadsheet_decoder.dart';\n",
   "import 'package:enough_convert/gbk.dart';\nimport 'package:spreadsheet_decoder/spreadsheet_decoder.dart';\n\n" + AL, 1],

  ["lib/features/ledger/data/bill_parser.dart",
   "  try {\n    return utf8.decode(bytes);\n  } catch (_) {\n    try {\n      return gbk.decode(bytes);\n    } catch (_) {\n      return utf8.decode(bytes, allowMalformed: true);\n    }\n  }\n",
   "  try {\n    return utf8.decode(bytes);\n  } catch (e) {\n    // 支付宝/微信 CSV 多为 GBK：utf8 严格解码失败属常态路径，记 warn 供复盘。\n    AppLog.add('账单 CSV utf8 解码失败，改按 GBK 重试：$e', level: LhLevel.warn);\n    try {\n      return gbk.decode(bytes);\n    } catch (e2) {\n      AppLog.add('账单 CSV utf8/GBK 均失败，容错解码（可能出乱码行）：$e2',\n          level: LhLevel.warn);\n      return utf8.decode(bytes, allowMalformed: true);\n    }\n  }\n", 1],

  ["lib/features/ledger/data/bill_parser.dart",
   "  final SpreadsheetDecoder dec;\n  try {\n    dec = SpreadsheetDecoder.decodeBytes(bytes);\n  } catch (_) {\n    return null;\n  }\n  final sheet = dec.tables.values.isEmpty ? null : dec.tables.values.first;\n  if (sheet == null) return null;\n",
   "  final SpreadsheetDecoder dec;\n  try {\n    dec = SpreadsheetDecoder.decodeBytes(bytes);\n  } catch (e) {\n    AppLog.add('账单 xlsx 解包失败（不是有效 Excel 容器）：$e',\n        level: LhLevel.error);\n    return null;\n  }\n  final sheet = dec.tables.values.isEmpty ? null : dec.tables.values.first;\n  if (sheet == null) {\n    AppLog.add('账单 xlsx 里没有可用工作表', level: LhLevel.warn);\n    return null;\n  }\n", 1],

  ["lib/features/ledger/data/bill_parser.dart",
   "  if (platform == null) return null;\n  return BillParseResult(platform: platform, rows: rows, skipped: skipped);\n",
   "  if (platform == null) {\n    // 表头认不出＝这批一行都进不来，必须留痕（真机「导入无反应」类反馈看这里）。\n    AppLog.add('账单解析：${lines.length} 行里未识别到支付宝/微信表头',\n        level: LhLevel.warn);\n    return null;\n  }\n  AppLog.addKey('账单解析：平台 $platform · 有效 ${rows.length} 条 · '\n      '规则过滤 $skipped 条（共 ${lines.length} 行）');\n  return BillParseResult(platform: platform, rows: rows, skipped: skipped);\n", 1],

  // ---------- 记账 · 导入向导 ----------
  ["lib/features/ledger/presentation/ledger_import_page.dart",
   "import '../../../core/theme/app_theme.dart';\n",
   AL + "import '../../../core/theme/app_theme.dart';\n", 1],

  ["lib/features/ledger/presentation/ledger_import_page.dart",
   "      if (res.rows.isEmpty) {\n        _toast('解析到 0 条可导入流水');\n        return;\n      }\n",
   "      if (res.rows.isEmpty) {\n        AppLog.add('账单导入：$_fileName 解析到 0 条可导入流水'\n            '（规则过滤 ${res.skipped} 条）', level: LhLevel.warn);\n        _toast('解析到 0 条可导入流水');\n        return;\n      }\n", 1],

  ["lib/features/ledger/presentation/ledger_import_page.dart",
   "      _toast('解析完成：${rows.length} 条 · 重复命中 ${rows.where((p) => p.dup).length} 条');\n",
   "      AppLog.addKey('账单导入预览：文件 $_fileName · 平台 ${res.platform} · '\n          '${rows.length} 条（重复命中 ${rows.where((p) => p.dup).length}）· '\n          '付款方式 ${_agg.length} 组');\n      _toast('解析完成：${rows.length} 条 · 重复命中 ${rows.where((p) => p.dup).length} 条');\n", 1],

  ["lib/features/ledger/presentation/ledger_import_page.dart",
   "      rows: specs,\n    );\n    ledgerTouch(ref);\n",
   "      rows: specs,\n    );\n    // 批次 id 只在这里落日志：页面没有「撤销本批」入口（原型无该行，见 set 页注释），\n    // 真机要追某批导入只能从这条 key 行起查。\n    AppLog.addKey('账单导入落库：批次 ${res.batchId} · 平台 $_plat · '\n        '写入 ${res.written}/${specs.length} 条 · 新建账户 ${newAccts.length} 个'\n        '（$_fileName）');\n    ledgerTouch(ref);\n", 1],

  ["lib/features/ledger/presentation/ledger_import_page.dart",
   "      try {\n        bytes = await File(f.path!).readAsBytes();\n      } catch (_) {\n        bytes = null;\n      }\n",
   "      try {\n        bytes = await File(f.path!).readAsBytes();\n      } catch (e) {\n        AppLog.add('账单文件读取失败（${f.name}）：$e', level: LhLevel.warn);\n        bytes = null;\n      }\n", 1],

  // ---------- 记账 · 导出 ----------
  ["lib/features/ledger/presentation/ledger_export_page.dart",
   "import '../../../core/theme/app_theme.dart';\n",
   AL + "import '../../../core/theme/app_theme.dart';\n", 1],

  ["lib/features/ledger/presentation/ledger_export_page.dart",
   "      );\n      if (mounted) {\n        _toast('已导出 ",
   "      );\n      AppLog.addKey('记账流水导出完成：${r.count} 条 · ${r.path}');\n      if (mounted) {\n        _toast('已导出 ", 1],

  ["lib/features/ledger/presentation/ledger_export_page.dart",
   "    } catch (e) {\n      if (mounted) _toast('导出失败 · $e');\n",
   "    } catch (e) {\n      AppLog.add('记账流水导出失败（$_fmt · 范围 $_scope）：$e',\n          level: LhLevel.error);\n      if (mounted) _toast('导出失败 · $e');\n", 1],

  // ---------- 待办 · 逾期扫描与升级建议 ----------
  ["lib/features/todo/presentation/todo_providers.dart",
   "import '../../../core/database/app_database.dart';\nimport '../../../core/providers.dart';\n",
   "import '../../../core/database/app_database.dart';\nimport '../../../core/logging/app_log.dart';\nimport '../../../core/providers.dart';\n", 1],

  ["lib/features/todo/presentation/todo_providers.dart",
   "/// 全部待办（变更后 invalidate 刷新）。\nfinal todosProvider = FutureProvider<List<Todo>>((ref) {\n  return ref.watch(todoRepositoryProvider).list();\n});\n\n/// 逾期计数（仪表盘角标 / 列表头提示共用）。\nfinal overdueCountProvider = FutureProvider<int>((ref) {\n  return ref.watch(todoRepositoryProvider).countOverdue();\n});\n",
   "/// 全部待办（变更后 invalidate 刷新）。\n/// 读取异常照常抛出（`rethrow` 不改控制流），但必须留痕：\n/// 消费侧一律 `valueOrNull ?? 默认值`，不记日志就会把「读失败」看成「空列表」。\nfinal todosProvider = FutureProvider<List<Todo>>((ref) async {\n  try {\n    return await ref.watch(todoRepositoryProvider).list();\n  } catch (e) {\n    AppLog.add('待办列表读取失败（页面将显示为空）：$e', level: LhLevel.error);\n    rethrow;\n  }\n});\n\n/// 逾期计数（仪表盘角标 / 列表头提示共用）。\nfinal overdueCountProvider = FutureProvider<int>((ref) async {\n  try {\n    return await ref.watch(todoRepositoryProvider).countOverdue();\n  } catch (e) {\n    AppLog.add('待办逾期扫描失败（角标将显示 0）：$e', level: LhLevel.error);\n    rethrow;\n  }\n});\n", 1],

  ["lib/features/todo/presentation/widgets/todo_list_view.dart",
   "import '../../../../core/providers.dart';\n",
   "import '../../../../core/logging/app_log.dart';\nimport '../../../../core/providers.dart';\n", 1],

  ["lib/features/todo/presentation/widgets/todo_list_view.dart",
   "                    final repo = ref.read(todoRepositoryProvider);\n                    for (final t in escalate) {\n                      await repo.moveQuadrant(t, Quadrant.q1);\n                    }\n",
   "                    final repo = ref.read(todoRepositoryProvider);\n                    for (final t in escalate) {\n                      await repo.moveQuadrant(t, Quadrant.q1);\n                    }\n                    // 一次改多条，留「改了哪些 id」才可能事后逐条核对。\n                    AppLog.addKey('待办一键升紧急：${escalate.length} 项 重要不紧急→重要且紧急 '\n                        '（id ${escalate.map((t) => t.id).join('/')}）');\n", 1],

  // ---------- 日程 · 时间块落库 ----------
  ["lib/features/calendar/data/time_block_dao.dart",
   "import '../../../core/database/schema.dart';\n",
   "import '../../../core/database/schema.dart';\nimport '../../../core/logging/app_log.dart';\n", 1],

  ["lib/features/calendar/data/time_block_dao.dart",
   "        where: 'id = ?', whereArgs: [id]);\n    return b.copyWith(endMin: e, source: kSrcMark);\n",
   "        where: 'id = ?', whereArgs: [id]);\n    AppLog.addKey('日程计时收口：块 #$id '\n        '${fmtMin(b.startMin)}→${fmtMin(e)}（请求 ${fmtMin(atMin)}）');\n    return b.copyWith(endMin: e, source: kSrcMark);\n", 1],

  ["lib/features/calendar/data/time_block_dao.dart",
   "  Future<void> restoreDay(DateTime day, List<TimeBlock> rows) async {\n    final dayMs = _dayMs(day);\n    await db.transaction((txn) async {\n      await txn.delete(table, where: 'day = ?', whereArgs: [dayMs]);\n      for (final b in rows) {\n        await txn.insert(table, b.toRow());\n      }\n    });\n  }\n",
   "  Future<void> restoreDay(DateTime day, List<TimeBlock> rows) async {\n    final dayMs = _dayMs(day);\n    await db.transaction((txn) async {\n      await txn.delete(table, where: 'day = ?', whereArgs: [dayMs]);\n      for (final b in rows) {\n        await txn.insert(table, b.toRow());\n      }\n    });\n    AppLog.addKey('日程撤销回写：日 $dayMs 恢复 ${rows.length} 段');\n  }\n", 1],

  ["lib/features/calendar/data/time_block_dao.dart",
   "      await batch.commit(noResult: true);\n    });\n  }\n",
   "      await batch.commit(noResult: true);\n      // 段数前后对照：V1.52 真机「合并丢块」就是这里少写了一段，\n      // 只靠 toast 复盘不出来。\n      AppLog.addKey('日程标记落库：${fmtMin(startMin)}-${fmtMin(endMin)} · $catName '\n          '· 日内 mark 段 ${rows.length}→${merged.length}');\n    });\n  }\n", 1],
]);
