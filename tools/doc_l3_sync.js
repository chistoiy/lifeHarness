/* L3 日志批文档同步（工单 §三/§五 + 交接文档变更日志 + 交棒话术 §⑤）
   用法：node tools/doc_l3_sync.js
   护栏：逐条命中断言，不符即中止；体积变化打印供核对。 */
const fs = require("fs");

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
  ["> 状态：**已拍板（2026-09-29）· L1 已交付，L2~L5 待排**（四档决定见 §六）。",
   "> 状态：**已拍板（2026-09-29）· L1~L3 已交付，L4~L5 待排**（四档决定见 §五）。", 1, "状态行"],

  ["| L3 | ledger + calendar + todo（高频三件套） | 导入批次结果、账单解析失败、逾期扫描异常 | 真机跑一次导入，日志页可复盘全过程 |",
   "| L3 | ledger + calendar + todo（高频三件套） | **已交付 2026-09-29 续批**：记账＝CSV 编码回落链两级 warn（utf8 失败→GBK／再失败→容错解码）+ xlsx 解包失败 error + 空表 warn + 表头未识别 warn + 解析汇总 key 行（平台·有效·规则过滤·总行），导入向导＝预览 key 行（文件·平台·条数·重复命中·付款方式组数）、落库 key 行（**批次 id**·写入 x/y·新建账户数·文件名——页面没有「撤销本批」入口，真机只能从这条追）、文件读取失败 warn、0 条可导入 warn、导出成败（完成 key / 失败 error 带格式与范围）；待办＝列表与逾期计数读取失败 error 后 `rethrow`（**按文案去重只记一次**，防每次 build 重读刷满环形缓冲）+ 一键升紧急 key 行（条数 + id 清单）；日程＝`markRange` 落库 key 行带**段数前后对照**（V1.52 真机「合并丢块」正是这条路少写一段）、计时收口 key 行（块号·原起止·请求值）、撤销回写 key 行（恢复段数） | 已达成：`test/l3_log_coverage_test.dart` 9 例（GBK 回落含汇总 key·坏 xlsx·表头认不出·只有表头·过滤计数·待办两条失败路径·日程段数对照·收口与回写），逐组断言 `src` 归类为 记账/待办/日程。「真机跑一次导入可复盘全过程」＝日志侧已备（预览/落库两条 key 行含批次 id），装机复盘并入下一轮真机走查 |", 1, "L3 行"],

  ["   - **L2 已交付（2026-09-29）**：纪律守住——`catch (_)` 改 `catch (e)` 只为把异常写进日志文本，控制流一字未动；新增日志一律走 `AppLog`，未开第二条通道。",
   "   - **L2 已交付（2026-09-29）**：纪律守住——`catch (_)` 改 `catch (e)` 只为把异常写进日志文本，控制流一字未动；新增日志一律走 `AppLog`，未开第二条通道。\n" +
   "   - **L3 已交付（2026-09-29 续批）**：同纪律。三域里 calendar/todo 原本**零 catch**（异常直接抛给 Riverpod 吞成 `AsyncError`，UI 侧 `valueOrNull ?? 默认值` 表现为「空列表/角标 0」），所以新增点分两类：失败路径一律 `catch (e)` 记完 `rethrow`（控制流未动），成功路径只补 key 汇总行。**自证口径再补一条**：Provider 体内的失败日志必须按文案去重——失败态每次 rebuild 都会重跑 provider，不去重会刷屏；FakeAsync 下 `AppLog` 的 300ms 节流 Timer 要显式推进才到期，故 settle 之后补一次 `helpers.dart` 新增的 `drainLogTimer(tester)`（`time_v152_test`／`g1_back_probe_test`／`dashboard_days_items_test` 三处，顺带暴露这三处都没 override 待办仓储、读取其实一直失败并被当成空列表）。", 1, "§五 L3 条"],
]);

// ---- 2. 交接文档变更日志（新行置于 V1.54 行之前）----
edit("docs/交接文档.md", [
  ["| 2026-09-29 | **V1.54 UI 保真批：R14-7/8/12/13/14 落 Flutter**",
   "| 2026-09-29 | **L3 日志批：记账 / 待办 / 日程三域补留痕（只加日志零行为改动）** 按 `docs/日志覆盖工单-20260929.md` §三 L3 范围。① 记账解析层 `bill_parser.dart`：CSV utf8→GBK→容错解码三级回落各留一条 warn、xlsx 解包失败 error、无工作表 warn、表头认不出 warn、成功落「平台·有效·过滤·总行」key 汇总；② 记账导入向导 `ledger_import_page.dart`：预览 key 行（文件·平台·条数·重复命中·付款方式组数）、落库 key 行（**批次 id**·写入 x/y·新建账户·文件名）、0 条可导入与文件读取失败 warn；`ledger_export_page.dart` 导出完成 key / 失败 error；③ 待办 `todo_providers.dart`：列表与逾期计数读取失败 error 后 `rethrow`（**按文案去重只记一次**，防 build 重读刷满 300 行环形缓冲）、`todo_list_view.dart` 一键升紧急 key 行含 id 清单；④ 日程 `time_block_dao.dart`：`markRange` key 行带**日内 mark 段前后对照**（V1.52 真机「合并丢块」正是这条少写一段）、计时收口 key 行（块号·原起止·请求值）、`restoreDay` 撤销回写 key 行。测试：新增 `test/l3_log_coverage_test.dart` 9 例并逐组断言 `src` 归类（记账/待办/日程）；`test/helpers.dart` 新增 `drainLogTimer(tester)`——AppLog 的 300ms 节流 Timer 在 FakeAsync 下「只看帧不看定时器」，页面 pump 之后补一次 400ms 才不判「A Timer is still pending」，`time_v152_test`/`g1_back_probe_test`/`dashboard_days_items_test` 三处在 settle 后接它（顺带暴露：这三处都没 override 待办仓储，读取其实一直失败并被当作空列表）。全量 run_gate **1681 例 0 失败**。 | lib/features/ledger/data/bill_parser.dart, lib/features/ledger/presentation/ledger_import_page.dart, lib/features/ledger/presentation/ledger_export_page.dart, lib/features/todo/presentation/todo_providers.dart, lib/features/todo/presentation/widgets/todo_list_view.dart, lib/features/calendar/data/time_block_dao.dart, test/l3_log_coverage_test.dart, test/helpers.dart, test/time_v152_test.dart, test/g1_back_probe_test.dart, test/dashboard_days_items_test.dart, tools/l3_log_patch.js, tools/doc_l3_sync.js, docs/日志覆盖工单-20260929.md |\n| 2026-09-29 | **V1.54 UI 保真批：R14-7/8/12/13/14 落 Flutter**", 1, "变更日志新行"],
]);

// ---- 3. 交棒话术 §⑤ 队列 ----
edit("docs/交棒话术-20260929-r14轮.md", [
  ["**下一步 L3**＝ledger + calendar + todo 高频三件套（导入批次结果、账单解析失败、逾期扫描异常）。",
   "**L3 已交付（2026-09-29 续批）**＝记账解析与导入链（含批次 id 落库 key 行）、待办读取/逾期扫描失败留痕（去重 + rethrow）、日程 markRange/收口/撤销回写 key 行；`test/l3_log_coverage_test.dart` 9 例钉桩并断言来源归类。**下一步 L4**＝care + habit + journal + inbox（记录写入失败、打卡结算、同步前清洗异常）。", 1, "§⑤ 条目 3"],
]);
