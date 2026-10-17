/* 把 R14-14 登记进验收清单（锚点＝R14-13 整行，插在其后；表格行首必须为「|」） */
const fs = require("fs");
const F = "docs/真机逐屏验收清单-20260929.md";
let s = fs.readFileSync(F, "utf8");
const anchor = s.split("\n").find((l) => l.startsWith("| R14-13 |"));
if (!anchor) { console.error("!! 找不到 R14-13 行"); process.exit(1); }
const row = "| R14-14 | 今天 › 顶部问候卡 | 「4 个待办 · 2 场安排」「62% 精力」「3/5 · 60%」「¥47.2 · 12 件」全为写死，与演示数据无联动；「今日日程」列表在 V1.52 事件并入 blocks 后恒空；卡内「长按任意卡片可编排顺序」「点一下，记录今天的心情」属教学文案，问候语带 ☀️（产品反馈） | A（假数据 + 空列表 + 已定硬规矩） | 否 | **[原型已改·待逐屏确认]** 新增 `renderHero()` 单一实算出口，挂在 `renderTodos` / `renderItems` / `renderCal` 三条主路上：待办数＝due 以「今天」开头、场安排＝今日 blocks 条数（与「今日日程」列表同源同数，列表一并恢复渲染）、精力占比＝未完成待办落在重要两象限的比例（≥60 状态不错 / ≥40 还能更聚焦 / 否则紧急事偏多）、完成环＝今日已完成/今日总数（含 SVG dasharray）、持有成本＝计费中物品的直线法日均合计（与物品页总览同值同源）；`D.events` 迁移后不再作数据源。教学文案两条摘除（心情提示改为「选中后才出现的状态行」）、☀️ 摘除。校验 `tools/hero144check.js` 13 断言全绿（含改数据即时联动与撤销回落）；回归 protostructcheck 6/6、r1478check 5/5、time52check 31/31。**实算后数字与旧写死值不同，请逐屏确认**：待办 4→2、安排 2→10、成本 ¥47.2→¥927.08（Nike 跑鞋持有 1 天 · ¥899/天 占大头）、计费件数 12→4。同类未动项（属 R14-8 余项）：待办页「长按条目可拖拽排序」「智能筛选 · 选择后自动收起 · 对清单与四象限同时生效」、逾期提示块 ⚠️ 与「临近截止的任务会被自动建议升入紧急象限」 |";
if (row.split("|").length !== 8) { console.error("!! 列数不符（6 列应为 8 段）：" + row.split("|").length); process.exit(1); }
const before = s.length;
s = s.replace(anchor, anchor + "\n" + row);
if (s.length === before) { console.error("!! 未写入"); process.exit(1); }
fs.writeFileSync(F, s);
const bad = s.split("\n").filter((l) => /^\s+\| R14/.test(l));
console.log("已插入 R14-14 · 体积 " + before + " → " + s.length + " · 行首异常残行 " + bad.length);
