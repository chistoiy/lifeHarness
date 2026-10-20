// 交接文档 §5 变更日志：追加反馈轮5 行（append-only·表格在文件末尾）
const fs = require('fs');
const f = 'docs/交接文档.md';
let s = fs.readFileSync(f, 'utf8');
const before = s.split('\n').length;
if (!/\| 2026-09-30 \|\s*\*\*真机复验挖出的 R15-1/.test(s)) throw new Error('末行锚点未命中');
const row =
  '| 2026-09-30 | **反馈轮5 · 共享面入口去重与记录段深链（V1.58 · 原型+实现同批 · 未推送）** 产品负责人真机走查原话「移除掉图1中圈起来的，图二日记、笔记；阅读点击后应该自动切换记录模块对应视图才对」三条：' +
  '① 「我的」页 `小工具合集 · 本地工具 · 插件拓展` 入口行摘除（与今天页宫格重复；`/kits` 路由、`NavModule.kits`、模块开关全留）；' +
  '② 全部功能宫格摘「日记」「笔记」两枚（记录页 ⇄ 四段菜单才是正式入口），17→15 枚；' +
  '③ 宫格「阅读」带段深链 `/journal?tab=book` → `journalShellRoutes()` 读 `queryParameters[\'tab\']` → `JournalPage(initialTab:)`（改 `ConsumerStatefulWidget`：本帧 `_linkTab` 防闪默认段 + 微任务同步 `recordTabProvider`，⇄ 菜单选段清覆盖可反压深链；无参/非法段名不改段）。' +
  '**跨模块不 import 对方 provider（守 R1），R6 对 `?query` 目标自动剥参**。' +
  '原型先行：`prototype/index.html`（`D.grid` 摘两枚 + 元组第 4 位段名 + 点击处理 `switchRecord`）· `node tools/kits/r5check.js` **18 断言全绿** + `checkjs.js` 过 + 取证图 `prototype/shots/r5/`。' +
  '实现：新增 `test/journal_deeplink_test.dart` 6 例，`g2_entry_wiring` ②③ 两条断言随改版同步；' +
  '`dart analyze` 四改动文件零 issue · `architecture/journal/dashboard/home_order/dashboard_days_items/dash_edit_event/v154_ui_fidelity/kit_home` 合跑 **89 绿**。' +
  '口径落《需求清单》V1.58 修订记录，验收清单 `docs/真机逐屏验收清单-20260930-反馈轮5.md`（与轮4 合并一次走查）。**未 push**（对外推送需产品负责人明确同意）。 |\n';
if (!s.endsWith('\n')) s += '\n';
s += row;
fs.writeFileSync(f, s);
const after = s.split('\n').length;
console.log('lines ' + before + ' -> ' + after + ' · row appended');
