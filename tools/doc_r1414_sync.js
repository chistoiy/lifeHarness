/* 交棒话术 §⑤ 与交接文档变更行同步 R14-14 */
const fs = require("fs");
function edit(F, pairs) {
  let s = fs.readFileSync(F, "utf8");
  for (const [old_, neu] of pairs) {
    const n = s.split(old_).length - 1;
    if (n !== 1) { console.error("!! [" + F + "] 命中 " + n + " 次：" + old_.slice(0, 60)); process.exit(1); }
    s = s.replace(old_, neu);
  }
  fs.writeFileSync(F, s);
  console.log("已更新 " + F);
}

const HAND = "docs/交棒话术-20260929-r14轮.md";
const old2 = "2. **R14-12/13 落 Flutter（原型已改·待确认后开发）**：我的页「编辑资料」半屏弹层（昵称/签名·空昵称报错，保存后同步头像字·副标题·顶栏副标题·今天页问候语）与三卡联动（完成任务=127+D.todos 已完成数、连续记录天=52+日记去重天数、在册书籍=13+D.books 条数；待办「已完成」chip 同源）——Flutter 侧对应 `lib/features/settings/**` 的 profile 卡与统计行，需先确认是否引入用户资料表或仅用设置项存昵称。";
const new2 = "2. **R14-12/13/14 落 Flutter（原型已改·待确认后开发）**：\n   - **R14-12/13 我的页**：「编辑资料」半屏弹层（昵称/签名·空昵称报错，保存后同步头像字·副标题·顶栏副标题·今天页问候语）与三卡联动（完成任务=127+D.todos 已完成数、连续记录天=52+日记去重天数、在册书籍=13+D.books 条数；待办「已完成」chip 同源）——Flutter 侧对应 `lib/features/settings/**` 的 profile 卡与统计行，需先确认是否引入用户资料表或仅用设置项存昵称。\n   - **R14-14 今天页问候卡**：五处写死数字改实算（今日待办数/场安排数/重要象限精力占比/完成环/持有成本），并修「今日日程」列表在 V1.52 事件并入 blocks 后恒空；Flutter 侧对应 `lib/features/dashboard/**`，需按真库口径确认三件事：① 「今日待办」谓词（截止日=今天？含逾期？）② 「场安排」取日程事件还是时间块（原型＝今日 blocks 条数，与列表同源）③ 持有成本与物品页合计必须同一函数出数（原型＝计费中物品直线法日均求和，Nike 跑鞋持有 1 天 ¥899/天 会主导合计，真库是否按「持有满 N 天才计费」需产品定）。原型侧工装可复用：`tools/hero144check.js`（13 断言·含联动与撤销回落）、`tools/proto_dash_hero*.js`（命中断言式补丁）。";
edit(HAND, [
  [old2, new2],
  ["3. **L2 日志批**（core/notifications + core/ai + core/media）。", "3. **L2 日志批**（core/notifications + core/ai + core/media）—— **[进行中]**。"],
]);

edit("docs/交接文档.md", [
  ["| 2026-09-29 | **我的页两条保真缺口补口（原型先行·R14-12/13）**",
   "| 2026-09-29 | **今天页问候卡联动 + 心情提示去教学化（原型先行·R14-14）** 产品走查反馈：顶部问候卡「4 个待办 · 2 场安排 / 62% 精力 / 3/5 · 60% / ¥47.2 · 12 件」全为写死。新增 `renderHero()` 单一实算出口并挂进 `renderTodos`/`renderItems`/`renderCal` 三条主路：今日待办数（due 以「今天」开头）、场安排数（今日 blocks 条数，与「今日日程」列表同源同数——顺带修该列表在 V1.52 事件并入 blocks 后恒空）、重要象限精力占比（未完成待办落 q0/q1 比例，三档措辞）、完成环（含 SVG dasharray）、持有成本（计费中物品直线法日均合计，物品页总览同值同源）。删两条教学文案（「长按任意卡片可编排顺序」「点一下，记录今天的心情」→ 心情提示改为选中后才出现的状态行）、问候语 ☀️ 摘除。守护：`tools/hero144check.js` 13/13（含改数据即时联动与撤销回落）、protostructcheck 6/6、r1478check 5/5、time52check 31/31、内联 JS 语法 OK；截图 `prototype/shots/r1414_*.png`。**实算后数字与旧写死值不同（待办 4→2、安排 2→10、成本 ¥47.2→¥927.08、件数 12→4），待逐屏确认后再落 Flutter。** | prototype/index.html, tools/proto_dash_hero.js, tools/proto_dash_hero2.js, tools/proto_dash_hero3.js, tools/hero144check.js, docs/真机逐屏验收清单-20260929.md, docs/交棒话术-20260929-r14轮.md |\n| 2026-09-29 | **我的页两条保真缺口补口（原型先行·R14-12/13）**"],
]);
