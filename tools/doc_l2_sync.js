/* L2 日志批交付后文档同步：工单 §三 L2 行 + §五 追加、交接文档变更行、交棒话术 §⑤ 队列 */
const fs = require("fs");
function edit(F, pairs) {
  let s = fs.readFileSync(F, "utf8");
  for (const [old_, neu] of pairs) {
    const n = s.split(old_).length - 1;
    if (n !== 1) { console.error("!! [" + F + "] 命中 " + n + " 次（要求 1）：" + old_.slice(0, 60)); process.exit(1); }
    s = s.replace(old_, neu);
  }
  fs.writeFileSync(F, s);
  console.log("已更新 " + F);
}

/* ① 工单：L2 行改「已交付」，并把验收列写实 */
const WO = "docs/日志覆盖工单-20260929.md";
let w = fs.readFileSync(WO, "utf8");
const lines = w.split("\n");
const li = lines.findIndex((l) => l.startsWith("| L2 |"));
if (li < 0) { console.error("!! 找不到 L2 行"); process.exit(1); }
if ((lines[li].match(/\|/g) || []).length !== 5) { console.error("!! L2 行列数异常"); process.exit(1); }
lines[li] = "| L2 | core/notifications + core/ai + core/media | **已交付 2026-09-29**：通知＝init 降级链（就绪 key / 未就绪 warn / 异常 error / 时区未取得 warn）+ 权限未授予 warn + 四类排程成功 info、失败 error（取消与开关关**不记**，防启动批量重排刷满 300 行环形缓冲）；AI＝零请求被拒 warn、调用失败 error（带 `kind`+detail 归因）、输出不合约定 warn、端点验证成败、使用记录旁路写入失败 warn、Key 保险箱读/写/删失败 error（**只记槽位名不记 Key 本体**）、服务商列表与用量台账脏数据 warn；图片＝引用列读失败 warn（孤儿判定会偏多·防按错数据误删）、扫描与清理汇总 key 行、越界删除拒绝 warn、删除失败 error、迁移引用替换失败 warn。**附项**：日志文本去 emoji 前缀 12 处（`⚠️ `/`‼️ `，日志页即 UI 且级别标记已表意）——`media_hash_migrator`/`main`/`error_capture`/`snapshot_service`/`s3_store`/`cloud_clean_service`/`sync_page` | 已达成：`test/l2_log_coverage_test.dart` 9 例（通知降级链·未就绪 no-op·AI 四类失败与脏数据回落·图片引用列/扫描汇总/越界删除），逐组断言 `src` 归类为 通知/AI/图片 |";
if ((lines[li].match(/\|/g) || []).length !== 5) { console.error("!! 新 L2 行列数不是 4"); process.exit(1); }
w = lines.join("\n");
fs.writeFileSync(WO, w);
console.log("已更新 " + WO);

/* ② 工单 §五 追加 L2 交付与下一步 */
edit(WO, [
  ["3. **L2~L5 按序排后**，每批独立走三门禁（analyze 基线 / 模块 mini 池 / 全量 run_gate），维持「只加日志零行为改动」纪律。",
   "3. **L2~L5 按序排后**，每批独立走三门禁（analyze 基线 / 模块 mini 池 / 全量 run_gate），维持「只加日志零行为改动」纪律。\n   - **L2 已交付（2026-09-29）**：纪律守住——`catch (_)` 改 `catch (e)` 只为把异常写进日志文本，控制流一字未动；新增日志一律走 `AppLog`，未开第二条通道。"],
]);

/* ③ 交接文档变更行（三列表：日期 | 变更 | 文件） */
edit("docs/交接文档.md", [
  ["| 2026-09-29 | **今天页问候卡联动 + 心情提示去教学化（原型先行·R14-14）**",
   "| 2026-09-29 | **L2 日志批交付（通知 / AI / 图片三域）** 按 `docs/日志覆盖工单-20260929.md` §三 L2 范围只加日志零行为改动：通知侧补 init 降级链（就绪 key·未就绪 warn·异常 error·时区未取得 warn）、权限未授予 warn、四类排程成功 info 与失败 error（取消/开关关不记，防启动批量重排刷缓冲）；AI 侧补零请求被拒 warn、调用失败 error（带 `kind` 归因）、输出不合约定 warn、端点验证成败、使用记录旁路写入失败 warn、Key 保险箱读写删失败 error（只记槽位名不记 Key）、服务商列表与用量台账脏数据 warn；图片侧补引用列读失败 warn（孤儿判定会偏多·防误删）、扫描/清理汇总 key 行、越界删除拒绝 warn、删除失败 error、迁移引用替换失败 warn。附项：日志文本去 emoji 前缀 12 处（日志页即 UI，级别标记已表意）。新增 `test/l2_log_coverage_test.dart` 9 例并逐组断言来源归类；analyze 触及面零告警。 | lib/core/notifications/notification_service.dart, lib/core/ai/ai_service.dart, lib/core/ai/ai_vault.dart, lib/core/ai/ai_config.dart, lib/core/ai/token_stats.dart, lib/core/media/media_usage_scanner.dart, lib/core/media/media_hash_migrator.dart, lib/core/logging/error_capture.dart, lib/core/sync/*, lib/main.dart, test/l2_log_coverage_test.dart, tools/l2_log_emoji_strip.js, docs/日志覆盖工单-20260929.md |\n| 2026-09-29 | **今天页问候卡联动 + 心情提示去教学化（原型先行·R14-14）**"],
]);

/* ④ 交棒话术 §⑤ 第 3 项标完成并接下一项 */
edit("docs/交棒话术-20260929-r14轮.md", [
  ["3. **L2 日志批**（core/notifications + core/ai + core/media）—— **[进行中]**。",
   "3. **L2 日志批**（core/notifications + core/ai + core/media）—— **[已交付]** `test/l2_log_coverage_test.dart` 9 例钉桩，来源归类逐组断言（通知/AI/图片）；附项把日志文本里的 `⚠️ `/`‼️ ` 前缀清了 12 处（日志页即 UI）。**下一步 L3**＝ledger + calendar + todo 高频三件套（导入批次结果、账单解析失败、逾期扫描异常）。"],
]);
