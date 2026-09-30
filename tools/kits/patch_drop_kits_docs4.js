// 小工具下架 · 验收清单与计划 §5 状态回写（幂等：已登记则跳过）
const fs = require('fs');
function load(f) { const raw = fs.readFileSync(f, 'utf8'); const crlf = raw.includes('\r\n'); return { f, crlf, s: crlf ? raw.replace(/\r\n/g, '\n') : raw }; }
function save(b) { fs.writeFileSync(b.f, b.crlf ? b.s.replace(/\n/g, '\r\n') : b.s); console.log('written ' + b.f); }
function sub(b, o, n, tag) { const k = b.s.split(o).length - 1; if (k !== 1) throw new Error(`${b.f} :: 锚点[${tag}]命中 ${k}: ${o.slice(0, 40)}`); b.s = b.s.replace(o, n); }

const banner = (scope) => '> ⛔ **2026-09-30 更新：小工具合集整模块下架**（产品负责人拍板「模块价值太低」）。\n' +
  '> ' + scope + ' 口径见《需求清单》V1.58 追加段与《小工具模块开发计划》顶部终止横幅。\n\n';

/* ① 轮4 清单：小工具内三节作废 */
{
  const b = load('docs/真机逐屏验收清单-20260930-kits反馈轮4.md');
  if (b.s.includes('小工具合集整模块下架')) console.log('轮4 清单已标，跳过');
  else {
    sub(b, '# 真机逐屏验收清单 · 小工具反馈轮4（2026-09-30）\n\n',
      '# 真机逐屏验收清单 · 小工具反馈轮4（2026-09-30）\n\n' + banner('本清单 **§0~§3（尺子 / 提词器 / 摘除复核）随模块下架一并作废**，不必再走；轮5 清单的共享面条目仍有效。'),
      'top');
    save(b);
  }
}

/* ② 批3 清单：整份作废 */
{
  const f = 'docs/真机逐屏验收清单-20260930-kits批3.md';
  if (!fs.existsSync(f)) console.log('批3 清单不存在，跳过');
  else {
    const b = load(f);
    if (b.s.includes('小工具合集整模块下架')) console.log('批3 清单已标，跳过');
    else {
      const first = b.s.split('\n')[0];
      sub(b, first + '\n', first + '\n\n' + banner('本清单全部条目（8 屏 + 首页 + 弹层）随模块下架**整份作废**。'), 'top');
      save(b);
    }
  }
}

/* ③ 批4 交棒话术：作废 */
{
  const f = 'docs/交棒话术-20260930-kits批4.md';
  if (!fs.existsSync(f)) console.log('批4 交棒话术不存在，跳过');
  else {
    const b = load(f);
    if (b.s.includes('整模块下架')) console.log('批4 交棒已标，跳过');
    else {
      const first = b.s.split('\n')[0];
      sub(b, first + '\n', first + '\n\n> ⛔ **本工单已作废（2026-09-30）**：小工具合集整模块下架，批4（管理屏 + 统计屏）不再开发。\n\n', 'top');
      save(b);
    }
  }
}

/* ④ 轮5 清单：宫格枚数与小工具条目随下架改写 */
{
  const b = load('docs/真机逐屏验收清单-20260930-反馈轮5.md');
  if (b.s.includes('小工具合集整模块下架')) console.log('轮5 清单已标，跳过');
  else {
    sub(b, '| 1-4 | 功能未摘 | 「今天」页全部功能宫格点「小工具」→ 正常进小工具首页（本轮只摘重复入口，不动功能） |',
      '| 1-4 | ~~功能未摘~~ | **2026-09-30 更新：小工具整模块已下架**，宫格不再有这一枚（本条按新基线复验：找不到「小工具」字样） |', '1-4');
    sub(b, '| 2-1 | 枚数与排布 | 共 **15 枚**（原 17 去掉「日记」「笔记」），四列网格排布紧凑，无空位、无占位灰块 |',
      '| 2-1 | 枚数与排布 | 共 **14 枚**（原 17 去掉「日记」「笔记」，再随模块下架去掉「小工具」），四列网格排布紧凑，无空位、无占位灰块 |', '2-1');
    sub(b, '收集箱 → 记账 → 物品 → 日子 → 健康(灰) → 习惯 → 目标 → 小工具 → 呵护',
      '收集箱 → 记账 → 物品 → 日子 → 健康(灰) → 习惯 → 目标 → 呵护', '2-2 顺序');
    sub(b, '| 2-4 | 其余瓦片 | 点「待办」进待办 tab、点「小工具」进小工具、点「健康」给「规划 V1.0」提示条 —— 未带段参的枚数行为与改前一致 |',
      '| 2-4 | 其余瓦片 | 点「待办」进待办 tab、点「健康」给「规划 V1.0」提示条 —— 未带段参的枚数行为与改前一致（「小工具」枚已随下架消失） |', '2-4');
    sub(b, '# 真机逐屏验收清单 · 反馈轮5（2026-09-30 · 共享面入口去重与记录段深链）\n',
      '# 真机逐屏验收清单 · 反馈轮5（2026-09-30 · 共享面入口去重与记录段深链）\n\n' +
      '> ⛔ **2026-09-30 追加：小工具合集整模块下架**（产品负责人拍板「模块价值太低」）。' +
      '本清单 §1~§2 涉及小工具的基线已按新口径改写（宫格 14 枚），§3 记录段深链与 §4 回归面**仍有效**。\n', 'top');
    save(b);
  }
}

/* ⑤ 计划 §5 表：加下架行 */
{
  const b = load('docs/小工具模块开发计划-20260929.md');
  if (b.s.includes('整模块下架（本表终止）')) console.log('计划 §5 已登记，跳过');
  else {
    sub(b, '| 批4~批6 | ⏳ 待做 | — | 见 §3（批4 管理屏 + 统计屏 / 批5 插件中心 / 批6 在线安装） | — |',
      '| ~~批4~批6~~ | ⛔ **不再开发** | — | 整模块下架，批4~批6 一并取消 | — |\n' +
      '| **整模块下架（本表终止）** | ✅ 已交付（未推送） | 本批 | 产品负责人拍板「小工具功能全部移除掉，模块价值太低」：`lib/features/kits/**` 35 文件 + `core/ai/ai_verify_channel.dart`（只被 kit_aiapi 用）删除 · `/kits` 路由与 `kitShellRoutes/kitPageRoutes` 注册摘 · `NavModule.kits` 栏目去（底栏栏目池自动少一栏）· 宫格「小工具」枚摘（15→14）· `KitSettings` 与偏好键 `lh.kit` 读到即清 · **DB v29→v30 迁移 DROP kit_* 四表**（`createStatements` 不再建表）· 共享面原型 `index.html` 摘 p-tools/p-toolDetail + sheetPlugin + TOOLS/TOOL_CATS/PLUGINS JS 段 + NAV_MODS/ICONS/TITLES/D.grid 项 · 专版原型 `index-kits.html` 移入 `prototype/archive/`（`kitscheck.js` 改指归档）· AI 验证两处同名入口只删小工具那枚（宫格 → `/settings/ai/verify` 保留） | 原型 `tools/kits/r6check.js` **12 断言全绿**（符号/DOM 归零 · 栏目池无「工具」· 宫格 14 枚 · AI 验证枚落 p-sub-ai · 逐屏 15 屏无悬空引用 · 零 console/exception）· `checkjs.js` 过 · `dart analyze lib` 零新增 issue · `database_schema_test` 两条新用例（删表不波及他表 + 幂等）· 联动回归绿 |',
      '§5 行');
    save(b);
  }
}
console.log('OK');
