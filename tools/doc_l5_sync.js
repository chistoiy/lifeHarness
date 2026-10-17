/* L5 日志批文档同步（工单 §三/§五 收口 + 交接文档变更日志 + 交棒话术 §⑤）
   用法：node tools/doc_l5_sync.js "全量 run_gate 实测文案"
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
  ["> 状态：**已拍板（2026-09-29）· L1~L4 已交付，L5 待排**（四档决定见 §五）。",
   "> 状态：**已拍板（2026-09-29）· L1~L5 全部交付（本单收口）**；§五-2 挂起的「catch 必带日志」架构守护**现已具备启动条件**（四档决定见 §五）。", 1, "状态行"],

  ["| L5 | days + goals + items + dashboard | 目标/日子计算与聚合异常 | 同上 |",
   "| L5 | days + goals + items + dashboard | **已交付 2026-09-29 续批**：日子＝`syncDerived` 两处跨模块读失败 warn（订阅表 / 保修列缺失都会让派生条目**静默失踪**）+ 派生汇总 key 行（**只在数值变化时落一行**，它随每次 loadAll 触发，重复值会刷满环形缓冲；表不存在时写「跳过」不写「0 项」）；目标＝`aggregate` 外层 try/catch 记 error 后 `rethrow`（归因到**哪个源·哪个 KR·哪一期**，否则目标页整片空白无人知道是谁炸的）、每期上限拒绝三处 warn（新建 / 单目标复制 / 复盘 Try 转草稿——三处 `return null` 文本相同，锚点必须带上文才唯一）、KR 回填与整组复制 key 行、删目标（连 KR 与回填留痕一起删）事务内 key 行；物品＝建档 / 二次付费 / 回收 / 报废四条财务动作 key 行（回收与报废会翻 `billing` 并冻结决算，属不可逆）。**dashboard 有意不铺**：其输入（待办/记账/日记/书籍/物品/时间块）已由 L3/L4 在数据层留痕，聚合层再记一遍＝双计且必然刷屏 | 已达成：`test/l5_log_coverage_test.dart` 4 例（派生两分支+两处 warn·目标建满上限与回填与整组复制·汇聚失败归因后照抛·物品四动作并复核 `billing` 真被翻掉），逐组断言 `src` 归类为 日子/目标/物品。" + GATE + " |", 1, "L5 行"],

  ["4. 交付门新增一条自证：**来源归类必须核对**",
   "   - **L5 已交付（2026-09-29 续批）**：同纪律。两条新自证口径进 §四/§五：① **随读触发的汇总行必须按变化去重**（`syncDerived` 每次 `loadAll` 都跑，不去重＝打开一次刷一行）；② **纯表达式体方法（`=> db.transaction(...)`）要落日志必须改块体**，且日志放事务提交之后才不虚报——本批 `bumpKr`/`addItem`/`addExtraPay` 三处即此形（内容一字未动）。\n" +
   "   - **工装两条（写死在 `tools/run_gate.sh` 注释里）**：① `sqlite3.dll` 拷贝冲突（errno 183）会让 `flutter test` 启动即崩、表现为成片「找不到 dll」，**只在 gate-err.log 出现 PathExistsException 时**摘除该产物再重跑；② 反过来，**预防性地删这个 dll 会制造假红**——最早并发起来的若干测试文件会在重拷贝完成前解析 `sqlite3_initialize`（errno 126），本批实测埋了 8 个假红后才改回。\n" +
   "4. 交付门新增一条自证：**来源归类必须核对**", 1, "§五 L5 条"],
]);

// ---- 2. 交接文档变更日志 ----
edit("docs/交接文档.md", [
  ["| 2026-09-29 | **L4 日志批：习惯 / 呵护 / 日记笔记 / 收集箱补留痕（只加日志零行为改动）**",
   "| 2026-09-29 | **L5 日志批：日子 / 目标 / 物品补留痕（只加日志零行为改动·日志覆盖工单收口）** 按 §三 L5 范围。① 日子 `days_repository.dart`：`syncDerived` 两处跨模块读失败 warn（订阅表 / 保修列缺失＝派生条目静默失踪）+ 派生汇总 key 行**按变化去重**（随每次 loadAll 触发，重复值刷满环形缓冲；表不存在写「跳过」）；② 目标 `goals_repository.dart`：`aggregate` 加外层 try/catch 记 error 后 `rethrow`（归因到源·KR·期），每期上限三处 `return null` 各补 warn，KR 回填 / 整组复制 / 删目标落 key 行；③ 物品 `items_repository.dart`：建档 / 二次付费 / 回收 / 报废四条财务动作落 key 行（回收与报废翻 `billing` 并冻结决算）；④ **dashboard 有意不铺**——输入已在 L3/L4 数据层留痕，聚合层再记＝双计。测试：新增 `test/l5_log_coverage_test.dart` 4 例并断言 `src` 归类；`tools/l4_test_drains.js` 再纳管 days/goals/items/dashboard 五个用例文件补 31 处末尾 `drainLogTimer`。工装：`tools/run_gate.sh` 写明 sqlite3.dll 的两条相反陷阱（预删反而制造 8 个假红）。${GATE}。 | lib/features/days/data/days_repository.dart, lib/features/goals/data/goals_repository.dart, lib/features/items/data/items_repository.dart, test/l5_log_coverage_test.dart, test/days_ui_test.dart, test/goals_ui_test.dart, test/items_ui_test.dart, test/dashboard_test.dart, test/dashboard_days_items_test.dart, tools/l5_log_patch.js, tools/l5_goal_limit_logs.js, tools/doc_l5_sync.js, tools/run_gate.sh, docs/日志覆盖工单-20260929.md |\n| 2026-09-29 | **L4 日志批：习惯 / 呵护 / 日记笔记 / 收集箱补留痕（只加日志零行为改动）**", 1, "变更日志新行"],
]);

// ---- 3. 交棒话术 §⑤ ----
edit("docs/交棒话术-20260929-r14轮.md", [
  ["**下一步 L5**＝days + goals + items + dashboard（目标/日子计算与聚合异常）。",
   "**L5 已交付（2026-09-29 续批）· 日志工单 L1~L5 全部收口**＝日子派生两处静默失踪 warn＋按变化去重的汇总行、目标汇聚失败归因后照抛＋上限三处 warn＋财务动作 key 行、物品四动作 key 行；`test/l5_log_coverage_test.dart` 4 例。**日志面下一步的两个候选（都要产品点头）**：① §五-2 挂起的「catch 必带日志」架构守护——L1~L5 已铺完，具备启动条件；② 真机走查时顺手用日志页复盘一次账单导入全过程（工单 L3 验收项）。", 1, "§⑤ L5 标记"],
]);
