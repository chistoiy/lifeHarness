/* L5 日志批 · 日子 / 目标 / 物品 补日志覆盖（只加日志，零行为改动）
   口径来源：docs/日志覆盖工单-20260929.md §三 L5 行（目标/日子计算与聚合异常）
   用法：node tools/l5_log_patch.js      ← 已于 2026-09-29 执行；重跑会因锚点已消失而整体中止
   注 1：目标「每期上限」三处 warn 见 tools/l5_goal_limit_logs.js（锚点需带上下文才唯一）。
   注 2：dashboard 域本批有意不铺——它的输入（待办/记账/日记/书籍/物品）已由 L3/L4 在
         数据层留痕，聚合层再加一层就是双计；口径记进工单 L5 行。 */
const fs = require("fs");

function load(F) {
  const s = fs.readFileSync(F, "utf8");
  const crlf = s.includes("\r\n");
  return { s, nl: (t) => (crlf ? t.replace(/\n/g, "\r\n") : t) };
}
let applied = 0;
function apply(edits) {
  // 预检：任一锚点命中数不符就整体中止，绝不「半应用」（重跑即自然失败）
  const pre = [];
  for (const [F, old0, , want] of edits) {
    const { s, nl } = load(F);
    const n = s.split(nl(old0)).length - 1;
    if (n !== want) {
      console.error("!! 预检失败 [" + F + "] 命中 " + n + " 期望 " + want +
          "\n   锚点首行：" + old0.split("\n")[0].trim().slice(0, 72) +
          "\n   （已应用过的脚本不可重跑；如需补单条，另写小脚本）");
      process.exit(1);
    }
    pre.push(F);
  }
  for (const [i, [F, old0, new0]] of edits.entries()) {
    const { s, nl } = load(F);
    const old_ = nl(old0), neu = nl(new0);
    fs.writeFileSync(F, s.split(old_).join(neu));
    applied++;
    console.log("OK  " + F.replace(/^lib\/features\//, "") + "  +" + (neu.length - old_.length) + "B");
  }
  console.log("完成：共应用 " + applied + " 处编辑");
}
const AL = "import '../../../core/logging/app_log.dart';\n";

apply([
  /* ================= 日子 ================= */
  ["lib/features/days/data/days_repository.dart",
   "import '../../../core/database/schema.dart';\n",
   "import '../../../core/database/schema.dart';\n" + AL, 1],

  ["lib/features/days/data/days_repository.dart",
   "    } catch (_) {\n      recurs = const [];\n    }\n",
   "    } catch (e) {\n      // 读不到就当没有订阅：派生条目会静默缺失，必须留一行归因。\n      AppLog.add('日子派生：记账订阅表读取失败（订阅提醒会缺项）：$e',\n          level: LhLevel.warn);\n      recurs = const [];\n    }\n", 1],

  ["lib/features/days/data/days_repository.dart",
   "    } catch (_) {\n      return;\n    }\n",
   "    } catch (e) {\n      AppLog.add('日子派生：物品保修表读取失败（保修提醒会缺项）：$e',\n          level: LhLevel.warn);\n      return;\n    }\n", 1],

  ["lib/features/days/data/days_repository.dart",
   "    if (hasItemTable) {\n      await _syncWarranty(ts);\n    }\n  }\n",
   "    if (hasItemTable) {\n      await _syncWarranty(ts);\n    }\n" +
   "    // syncDerived 随每次 loadAll 触发，同一状态只落一行（同 L2「防刷满环形缓冲」口径）；\n" +
   "    // 数值变了才记，正好留下「订阅 3→4」这类变化轨迹。\n" +
   "    final sig = '订阅 ${keepSub.length} 项 · '\n" +
   "        '保修表${hasItemTable ? '已同步' : '不存在（跳过）'}';\n" +
   "    if (sig != _lastDerivedSig) {\n      _lastDerivedSig = sig;\n" +
   "      AppLog.addKey('日子派生刷新：$sig');\n    }\n  }\n", 1],

  ["lib/features/days/data/days_repository.dart",
   "  final Database db;\n",
   "  final Database db;\n\n" +
   "  /// 上次已记录的派生汇总（进程内去重用；见 [syncDerived] 尾）。\n" +
   "  static String _lastDerivedSig = '';\n", 1],

  /* ================= 目标 ================= */
  ["lib/features/goals/data/goals_repository.dart",
   "import '../../../core/database/schema.dart';\n",
   "import '../../../core/database/schema.dart';\n" + AL, 1],

  ["lib/features/goals/data/goals_repository.dart",
   "  /// 单一数据源在周期窗内的实算值。\n  Future<double> aggregate(KrSource src, String krLabel, String period, DateTime now) async {\n",
   "  /// 单一数据源在周期窗内的实算值。\n  /// 外层只负责留痕：源表缺表/列异常照常抛出（`rethrow` 不改控制流），\n  /// 否则目标页整片空白时没人知道是哪个数据源炸的。\n  Future<double> aggregate(\n      KrSource src, String krLabel, String period, DateTime now) async {\n    try {\n      return await _aggregateOf(src, krLabel, period, now);\n    } catch (e) {\n      AppLog.add('目标自动汇聚失败（源 ${src.label} · KR「$krLabel」 · '\n          '周期 $period）：$e', level: LhLevel.error);\n      rethrow;\n    }\n  }\n\n  Future<double> _aggregateOf(\n      KrSource src, String krLabel, String period, DateTime now) async {\n", 1],

  ["lib/features/goals/data/goals_repository.dart",
   "        await txn.delete(DbSchema.tGoals, where: 'id = ?', whereArgs: [id]);\n      });\n",
   "        await txn.delete(DbSchema.tGoals, where: 'id = ?', whereArgs: [id]);\n        // 目标连 KR 与回填留痕一起删，属不可逆操作（krs 只在事务闭包内可见）。\n        AppLog.addKey('目标删除：#$id 及其 ${krs.length} 条 KR 与回填留痕');\n      });\n", 1],

  ["lib/features/goals/data/goals_repository.dart",
   "  Future<void> bumpKr(int krId, double cur, {String? note}) => db.transaction((txn) async {\n" +
   "        await txn.update(DbSchema.tGoalKrs, {'cur': cur},\n" +
   "            where: 'id = ?', whereArgs: [krId]);\n" +
   "        await txn.insert(DbSchema.tKrUpdates, {\n" +
   "          'kr_id': krId,\n" +
   "          'cur': cur,\n" +
   "          'kind': 'manual',\n" +
   "          'note': note ?? '手动回填',\n" +
   "          'created_at': DateTime.now().millisecondsSinceEpoch,\n" +
   "        });\n" +
   "      });\n",
   // 表达式体改块体只为在事务提交后补一行；事务内容一字未动。
   "  Future<void> bumpKr(int krId, double cur, {String? note}) async {\n" +
   "    await db.transaction((txn) async {\n" +
   "      await txn.update(DbSchema.tGoalKrs, {'cur': cur},\n" +
   "          where: 'id = ?', whereArgs: [krId]);\n" +
   "      await txn.insert(DbSchema.tKrUpdates, {\n" +
   "        'kr_id': krId,\n" +
   "        'cur': cur,\n" +
   "        'kind': 'manual',\n" +
   "        'note': note ?? '手动回填',\n" +
   "        'created_at': DateTime.now().millisecondsSinceEpoch,\n" +
   "      });\n" +
   "    });\n" +
   "    AppLog.addKey('目标 KR 回填：#$krId → $cur（${note ?? '手动回填'}）');\n" +
   "  }\n", 1],

  ["lib/features/goals/data/goals_repository.dart",
   "      copied++;\n    }\n    return copied;\n  }\n",
   "      copied++;\n    }\n    AppLog.addKey('目标整组复制：$fromPeriod → $toPeriod · '\n        '$copied/${src.length} 个（每期上限 $kMaxOkrPerPeriod，超出截断）');\n    return copied;\n  }\n", 1],

  /* ================= 物品 ================= */
  ["lib/features/items/data/items_repository.dart",
   "import '../../../core/database/schema.dart';\n",
   "import '../../../core/database/schema.dart';\n" + AL, 1],

  ["lib/features/items/data/items_repository.dart",
   "  /// 新建（同事务追加「购入」首条审计）。返回新 id。\n  Future<int> addItem(ItemProfile it) async {\n    final ts = DateTime.now().millisecondsSinceEpoch;\n    return db.transaction((txn) async {\n",
   "  /// 新建（同事务追加「购入」首条审计）。返回新 id。\n  Future<int> addItem(ItemProfile it) async {\n    final ts = DateTime.now().millisecondsSinceEpoch;\n    final id = await db.transaction((txn) async {\n", 1],

  ["lib/features/items/data/items_repository.dart",
   "        'event_date': it.buyDate,\n        'created_at': ts,\n      });\n      return id;\n    });\n  }\n",
   "        'event_date': it.buyDate,\n        'created_at': ts,\n      });\n      return id;\n    });\n    AppLog.addKey('物品建档：#$id ${it.name} · 价 ${it.price} · '\n        '${it.buyDate} · 计费=${it.billing} · 来源 ${it.source}');\n    return id;\n  }\n", 1],

  ["lib/features/items/data/items_repository.dart",
   "  Future<void> addExtraPay(int itemId, double amount, String desc,\n          {String? note, String? date}) =>\n      _appendEvent(\n          itemId,\n          ItemEvent(\n              itemId: itemId,\n              kind: kEvExtra,\n              label: '二次付费：$desc',\n              amount: amount,\n              note: note,\n              date: date ?? fmtYmd(DateTime.now())));\n",
   "  Future<void> addExtraPay(int itemId, double amount, String desc,\n          {String? note, String? date}) async {\n    final d = date ?? fmtYmd(DateTime.now());\n    await _appendEvent(\n        itemId,\n        ItemEvent(\n            itemId: itemId,\n            kind: kEvExtra,\n            label: '二次付费：$desc',\n            amount: amount,\n            note: note,\n            date: d));\n    AppLog.addKey('物品二次付费：#$itemId +$amount · $desc · $d（摊回全周期）');\n  }\n", 1],

  ["lib/features/items/data/items_repository.dart",
   "      }, where: 'id = ?', whereArgs: [itemId]);\n    });\n  }\n",
   "      }, where: 'id = ?', whereArgs: [itemId]);\n    });\n    AppLog.addKey('物品回收：#$itemId 残值 $amount · '\n        '${keep ? '抵扣留用·继续计费' : '转出·停计费并冻结决算'} · $d');\n  }\n", 1],

  ["lib/features/items/data/items_repository.dart",
   "          where: 'id = ?',\n          whereArgs: [itemId]);\n    });\n  }\n",
   "          where: 'id = ?',\n          whereArgs: [itemId]);\n    });\n    AppLog.addKey('物品报废：#$itemId · 原因「$reason」 · $d · '\n        '停计费并冻结决算');\n  }\n", 1],
]);
