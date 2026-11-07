// 小工具下架 · 需求清单 / 交接文档 登记（锚点唯一命中·表格行按现有列数）
const fs = require('fs');
function load(f) { const raw = fs.readFileSync(f, 'utf8'); const crlf = raw.includes('\r\n'); return { f, crlf, s: crlf ? raw.replace(/\r\n/g, '\n') : raw }; }
function save(b) { fs.writeFileSync(b.f, b.crlf ? b.s.replace(/\n/g, '\r\n') : b.s); console.log('written ' + b.f); }
function sub(b, o, n) { const k = b.s.split(o).length - 1; if (k !== 1) throw new Error(`${b.f} :: 锚点命中 ${k}: ${o.slice(0, 40)}`); b.s = b.s.replace(o, n); }

/* ① 需求清单：V1.58 追加段（放在决策记录之前） */
{
  const b = load('docs/需求清单.md');
  if (b.s.includes('小工具合集（模块 14）整模块下架')) { console.log('需求清单已登记，跳过'); }
  else {
    sub(b, '### 决策记录（确认门已关闭 · 2026-09-19）',
      '### V1.58 追加 · 小工具合集（模块 14）整模块下架（2026-09-30 · 产品负责人拍板）\n' +
      '- **决定**：「小工具功能全部移除掉，模块价值太低」——V1.47 模块 14 自本日起**整模块下架**，\n' +
      '  批0~批3（首页控制盘 / 四弹层 / 11 件工具屏 / core 验证通道）与验收轮2~轮5 的全部交付一并作废。\n' +
      '  本文与《小工具模块开发计划-20260929.md》的历史条目**保留不删**（需求演进可追溯），以本段为准。\n' +
      '- **摘除面**：`lib/features/kits/**`（35 文件）· 只被它使用的 `core/ai/ai_verify_channel.dart` ·\n' +
      '  `/kits` 路由与 `kitShellRoutes/kitPageRoutes` 注册 · `NavModule.kits` 栏目（底栏栏目池自动少一栏）·\n' +
      '  全部功能宫格「小工具」枚（15→14）· `KitSettings` 与偏好键 `lh.kit`（读到即清，照 `care.rm.lock` 先例）·\n' +
      '  共享面原型 `index.html` 的 p-tools / p-toolDetail 两屏、sheetPlugin 弹层、TOOLS/TOOL_CATS/PLUGINS JS 段、\n' +
      '  NAV_MODS/ICONS/TITLES/D.grid 的 p-tools 项（`tools/kits/r6check.js` 12 断言全绿）。\n' +
      '- **数据口径（已拍板）**：**DB v29→v30 迁移 DROP `kit_usage`/`kit_layout`/`kit_tool_data`/`kit_plugin` 四表**\n' +
      '  （索引随表消失；`DROP IF EXISTS` 保证新装库也走得通，`createStatements` 已不再建这四张表），\n' +
      '  用例 `test/database_schema_test.dart` 两条新断言钉住「删表不波及他表 + 迁移幂等」。\n' +
      '- **留档**：专版原型 `prototype/index-kits.html` 移入 `prototype/archive/`（`kitscheck.js` 改指归档路径，\n' +
      '  不再维护）；计划文档顶部加终止横幅；轮4 验收清单 §0~§3（小工具内）作废，轮5 清单 §2/§3 仍有效。\n' +
      '- **AI 验证两处同名入口的处置**：宫格「AI 验证」枚进的是 AI 模块二级页 `/settings/ai/verify`（**保留**）；\n' +
      '  小工具内那枚「AI API 验证」工具屏（`kit_aiapi`）随模块删除。原型侧原有一枚借道 `openTool(\'aiapi\')`\n' +
      '  的「重新验证」按钮已摘（原型无独立验证屏）——**遗留缺口**：AI 增强页需补一屏 p-sub-aiVerify，已入待排期池。\n' +
      '- **可复用资产找回路径**：纯 Dart 基线 JPEG 编码器 `git show 391edde:lib/features/kits/domain/kit_jpeg.dart`、\n' +
      '  农历引擎已提升为 `shared/calendar/lunar.dart`（日子模块在用，**不随下架**）。\n' +
      '\n' +
      '### 决策记录（确认门已关闭 · 2026-09-19）');
    save(b);
  }
}

/* ② 交接文档：变更日志行（表格在文件末尾·append-only） */
{
  const b = load('docs/交接文档.md');
  if (b.s.includes('小工具合集（模块 14）整模块下架')) { console.log('交接文档已登记，跳过'); }
  else {
    if (!b.s.endsWith('\n')) b.s += '\n';
    b.s += '| 2026-09-30 | **V1.58 · 小工具合集（模块 14）整模块下架（产品负责人拍板「模块价值太低」）** ' +
      '`lib/features/kits/**` 35 文件 + 只被它用的 `core/ai/ai_verify_channel.dart` 删除；`/kits` 路由、`NavModule.kits` 栏目、' +
      '宫格「小工具」枚（15→14）、`KitSettings`/偏好键 `lh.kit`（读到即清）全摘；' +
      '**DB v29→v30 迁移 DROP kit_* 四表**（`createStatements` 不再建表 · `DROP IF EXISTS` 幂等 · 两条新用例钉「不波及他表 + 幂等」）。' +
      '共享面原型 `index.html` 同步摘 p-tools/p-toolDetail 两屏 + sheetPlugin + TOOLS/TOOL_CATS/PLUGINS JS 段 + NAV_MODS/ICONS/TITLES/D.grid 项' +
      '（`tools/kits/r6check.js` **12 断言全绿**·`checkjs.js` 过·逐屏 15 屏无悬空引用）；' +
      '专版原型 `index-kits.html` 移入 `prototype/archive/` 留档不删。' +
      '**AI 验证两处同名入口只删小工具那枚**，宫格「AI 验证」→ `/settings/ai/verify` 保留；' +
      '原型侧借道 `openTool(\'aiapi\')` 的按钮已摘，遗留「AI 增强页缺独立验证屏」入待排期池。' +
      '下架后暴露两条**他批遗留**红灯（本批未代改）：`catch_log_guard` 的 `core/sync/snapshot_service.dart 5>登记4`（`7c36a00` 带入）、' +
      '`size_budget` 的 `todo_edit_sheet.dart 1236>1231`（`32324b2` 遗留）。' +
      '轮4 验收清单 §0~§3 作废；口径见《需求清单》V1.58 追加段与《小工具模块开发计划》顶部终止横幅。 |\n';
    save(b);
  }
}

/* ③ 待排期池：AI 增强页验证屏缺口 */
{
  const b = load('docs/交接文档.md');
  const anchor = '## 7. 待排期池（Backlog，未纳入当前版本）';
  if (!b.s.includes(anchor)) throw new Error('待排期池标题未找到');
  if (b.s.includes('AI 增强页独立验证屏')) { console.log('待排期池已登记，跳过'); }
  else {
    sub(b, anchor + '\n', anchor + '\n' +
      '- （候选 · V1.58 下架带出的缺口）**AI 增强页独立「API 验证」屏**：原型 `index.html` 的 p-sub-ai 里那枚\n' +
      '  「重新验证 / 测试新 Key」按钮原先借道小工具屏 `openTool(\'aiapi\')`，随模块下架已摘；\n' +
      '  实现侧 `/settings/ai/verify`（`ai_page_verify.dart`）是真页，原型需补一屏与之对齐。\n');
    save(b);
  }
}
console.log('OK');
