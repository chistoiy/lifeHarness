/* L4 日志批文档同步（工单 §三/§五 + 交接文档变更日志 + 交棒话术 §⑤）
   用法：node tools/doc_l4_sync.js [门禁文案]
   例：node tools/doc_l4_sync.js "1690 例 0 失败"
   护栏：逐条命中断言；CRLF 文件按原行尾写回。 */
const fs = require("fs");
const GATE = process.argv[2] || '全量 run_gate 结果见提交注记';

function edit(F, pairs) {
  let s = fs.readFileSync(F, "utf8");
  const crlf = s.includes("\r\n");
  const nl = (t) => (crlf ? t.replace(/\n/g, "\r\n") : t);
  for (const [old_, neu0, want, label] of pairs) {
    const neu = nl(neu0);
    const n = s.split(old_).length - 1;
    if (n !== (want || 1)) {
      console.error("!! [" + F + "][" + (label || "") + "] 命中 " + n + " 次，期望 " + (want || 1));
      process.exit(1);
    }
    s = s.split(old_).join(neu);
  }
  const before = fs.statSync(F).size;
  fs.writeFileSync(F, s);
  console.log("已更新 " + F + " " + before + " → " + Buffer.byteLength(s) + "B" + (crlf ? " (CRLF)" : ""));
}

// ---- 1. 日志覆盖工单 ----
const TK = "docs/日志覆盖工单-20260929.md";
edit(TK, [
  ["> 状态：**已拍板（2026-09-29）· L1~L3 已交付，L4~L5 待排**（四档决定见 §五）。",
   "> 状态：**已拍板（2026-09-29）· L1~L4 已交付，L5 待排**（四档决定见 §五）。", 1, "状态行"],

  ["| L4 | care + habit + journal + inbox | 记录写入失败、打卡结算、同步前清洗异常 | 同上逐模块抽查 |",
   "| L4 | care + habit + journal + inbox | **已交付 2026-09-29 续批**：习惯＝`upsertEntry` 落账 key 行（**结算 streak/best 直接写进行文**，事后不必翻流水重算）+ 未来日写入被拒 warn（抛错照旧）+ 撤销流水 / 负向触发登记 / 宽限抵签 / 待确认达成入账各一条；呵护＝速记落库 key 行（记录 id·宝宝·日·事件键）、删档级联清理 key 行（不可逆动作留硬证据）、过敏项重名被 UNIQUE 吞掉时 warn（UI 只提示一次，库里查不到就靠这条）；日记笔记＝保存/删单篇/批量删除 key 行，rich 正文非 Delta JSON 回退 Markdown 扫描 warn、标签非 JSON 兜底 warn、笔记摘要回退 warn，图片卡与导出两处**原先被 catch 吞掉只 toast** 的失败改记 error；收集箱＝四向分流（待办/今晚日记/笔记/阅读摘录）各一条 key 行 + 两处拒绝 warn + 「直接删除未整理条目」key 行（**原文只截 16 字**，防整段进环形缓冲） | 已达成：`test/l4_log_coverage_test.dart` 10 例（落账含结算值·撤销·未来日·触发·速记·过敏重名·删档·日记读写·rich 回退·收集箱源码级守门），逐组断言 `src` 归类；「同步前清洗异常」核实现由 `core/sync` 的 snapshot/cloud_clean/sync_orchestrator 承担，L2 附项与 V1.43 批已覆盖，本批不重复铺 |", 1, "L4 行"],

  ["4. 交付门新增一条自证：**来源归类必须核对**",
   "   - **L4 已交付（2026-09-29 续批）**：同纪律（`catch (_)` 只为写日志改 `catch (err)`，控制流一字未动；两处表达式体方法改 async 块仅为落日志，返回值不变）。**新增一条硬约定**：仓库层落 key 行以后，模块内**每个** widget 用例末尾都要 `await drainLogTimer(tester)`——本批用 `tools/l4_test_drains.js` 一次性补齐 17 个文件 99 处（脚本按「同层 `});` 回溯同层 `testWidgets(`」定位，注意 `group` 收尾同为 `  });`，缩进不同层不可混判）。`tearDown(AppLog.reset)` 这条路**试过不成立**：定时器不变式在包级 tearDown 之前校验。\n" +
   "4. 交付门新增一条自证：**来源归类必须核对**", 1, "§五 L4 条"],
]);

// ---- 2. 交接文档变更日志（新行置于 L3 行之前）----
edit("docs/交接文档.md", [
  ["| 2026-09-29 | **L3 日志批：记账 / 待办 / 日程三域补留痕（只加日志零行为改动）**",
   "| 2026-09-29 | **L4 日志批：习惯 / 呵护 / 日记笔记 / 收集箱补留痕（只加日志零行为改动）** 按 `docs/日志覆盖工单-20260929.md` §三 L4 范围。① 习惯 `habit_repository.dart`：`upsertEntry` 落账 key 行（checked/value/origin + **结算 streak·best 直接写进行文**）、未来日时钟防护 warn（`ArgumentError` 照抛）、`deleteEntry` 撤销、`recordTrigger` 触发登记、`useFreeze` 宽限抵签、`confirmPend` 自动达成入账；② 呵护 `care_repository.dart`：`addLog` 速记落库 key 行（记录 id·宝宝·日·事件键，表达式体改 async 块只落日志、返回值不变）、`deleteBaby` 级联清理 key 行、`addAllergy` 重名被 UNIQUE 吞掉时 warn；③ 日记笔记：`journal_repository.dart` 保存/删单篇/批量删除 key 行，`journal_entry.dart` 与 `note.dart` 三处「非 Delta JSON 回退」warn，`note_sheets.dart` 图片卡生成与导出两处**原先吞异常只 toast** 的 catch 改记 error；④ 收集箱 `inbox_page.dart`：四向分流各一条 key 行 + 无书可摘/同句重复两处 warn + 直接删除未整理条目一条（`_brief()` 只截 16 字，防整段原文进 300 行环形缓冲）。测试：新增 `test/l4_log_coverage_test.dart` 10 例逐组断言 `src` 归类；`helpers.dart` 的 `settle5` 内置排空，另用 `tools/l4_test_drains.js` 给 17 个模块用例文件补 99 处末尾 `drainLogTimer`（仓库落日志后 FakeAsync 不排空就判「A Timer is still pending」）。${GATE}。 | lib/features/habit/data/habit_repository.dart, lib/features/care/data/care_repository.dart, lib/features/journal/domain/journal_repository.dart, lib/features/journal/domain/journal_entry.dart, lib/features/journal/domain/note.dart, lib/features/journal/presentation/widgets/note_sheets.dart, lib/features/inbox/presentation/inbox_page.dart, test/l4_log_coverage_test.dart, test/helpers.dart, tools/l4_log_patch.js, tools/l4_test_drains.js, docs/日志覆盖工单-20260929.md |\n| 2026-09-29 | **L3 日志批：记账 / 待办 / 日程三域补留痕（只加日志零行为改动）**", 1, "变更日志新行"],
]);

// ---- 3. 交棒话术 §⑤ 队列 ----
edit("docs/交棒话术-20260929-r14轮.md", [
  ["**下一步 L4**＝care + habit + journal + inbox（记录写入失败、打卡结算、同步前清洗异常）。",
   "**L4 已交付（2026-09-29 续批）**＝习惯落账/结算·呵护记录与删档·日记读写与富文本回退·收集箱四向分流；`test/l4_log_coverage_test.dart` 10 例，另用 `tools/l4_test_drains.js` 给 17 个模块用例文件补 99 处 `drainLogTimer`（**仓库层落日志后必须排空节流 Timer**，`tearDown(AppLog.reset)` 不成立）。**下一步 L5**＝days + goals + items + dashboard（目标/日子计算与聚合异常）。", 1, "§⑤ L4 标记"],
]);
