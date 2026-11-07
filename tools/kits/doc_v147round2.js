/* 落档验收轮2：变更单新增 §六 + C5 行改「已拍板」；需求清单同步状态
 * 用法：node tools/kits/doc_v147round2.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const CH = 'docs/变更单-小工具专版共享面-20260927.md', RQ = 'docs/需求清单.md';
const read = f => { const raw = fs.readFileSync(path.resolve(f), 'utf8'); return { raw, nl: raw.includes('\r\n') ? '\r\n' : '\n' }; };
const A = read(CH), B = read(RQ);
let bad = 0;
const EDITS = [
  { f: A, id: 'C5 行改已拍板',
    from: '| C5 | 底栏栏目池 `NAV_MODS` | `工具` 与 `插件` 两栏并存易混 | 建议 `插件` 归入设置二级；保留 `工具` 一栏（等产品拍板后改） |',
    to: '| C5 | 底栏栏目池 `NAV_MODS` | `工具` 与 `插件` 两栏并存易混 | **已拍板（2026-09-29 验收轮2）**：底栏栏目池摘除 `插件`（两份原型都改）；插件中心入口**只留在小工具合集页的拓展卡设置位**，不放「我的」设置列表 |' },
  { f: A, id: '未动项更正',
    from: '- 未动项：C5 底栏「插件」栏归置仍待产品拍板；',
    to: '- 未动项：C5 已于验收轮2 拍板并落地（见 §六）；' },
  { f: B, id: '需求清单：走查后仍挂',
    from: '- **走查后仍挂**：A4 专版「全部功能」宫格待主原型 R14-7/8 SVG 版定稿后回灌；C5 底栏「插件」栏归置待拍板。二者不阻塞 Flutter 侧开工（写区已在变更单登记）。',
    to: '- **走查后仍挂**：A4 专版「全部功能」宫格待主原型 R14 系列定稿后回灌。**C5 已拍板并落地**（2026-09-29 验收轮2：底栏摘除「插件」栏位，插件入口只留小工具页拓展卡设置位）。不阻塞 Flutter 侧开工（写区已在变更单登记）。' },
];
for (const e of EDITS) {
  const from = e.from.replace(/\n/g, e.f.nl), to = e.to.replace(/\n/g, e.f.nl);
  const n = e.f.raw.split(from).length - 1;
  if (n !== 1) { console.error('!! ' + e.id + ' 命中 ' + n); bad++; continue; }
  e.f.raw = e.f.raw.replace(from, to); console.log('PASS ' + e.id);
}
const SEC = [
  '',
  '## 六、验收轮2 改刀（2026-09-29 · 用户截图三条）',
  '',
  '| # | 反馈 | 落地 | 复验 |',
  '|---|---|---|---|',
  '| B1 | 尺子应**全屏展示**，比较时尺上要有**可滑动游标**，滑到位置自动显示长度 | 新增全屏舞台 `#rulerStage`（LH-KIT-RULER）：横向尺条铺满量程 + **红色游标**与**紫色零点**两根可拖把手（pointerdown/move/up，1mm 吸附，方向键微调，Esc/✕ 退出）；读数=游标−零点，大号主读数 + 长边/短边与量程副读；`openTool(\'ruler\')` 进屏即全屏，页面内 52vh 竖尺退役（保留隐藏节点供回归） | `kitscheck` 新增 3 例：舞台开启与量程一致 / 游标拖动即自动读数 / 零点可挪且读数=游标−零点；`tools/kits/rulerproof.js` 真实视口复验 |',
  '| B2 | 小工具**图标卡片太大**（附截图） | ① 工具卡由白底大卡改紧凑原语 `.kit-tile`（30px 图标块 + 9.5px 名称 + 8px 次数，★ 收藏角标）；② 首页由「每分类各自成网格」改为**全分类合并的单一网格 `.kgrid`**（flex 20% 定宽），每行稳定 5 枚；分类归属看筛选 chips；③ 拓展插件并入同一网格，右上「插件」小标签区分 | `tools/kits/gridproof.js` 实测 `全部工具: 5/15 枚同行 · 单枚 94px · 行宽 472px`；`kitscheck` 断言「每行可排 5 枚」（宽度比 + 同行计数 + min-width:0） |',
  '| B3 | 底栏「插件」归位：**不放「我的」设置列表，放小工具合集页卡片的设置位** | 两份原型 `NAV_MODS` 摘除 `p-pstore` 栏位；两份原型「我的」页摘除插件中心行；小工具页拓展卡保留「插件中心 · 安装 / 更新 / 回滚 / 权限 ›」入口（=设置位） | 运行期断言：`NAV_MODS` 无「插件」；`#p-profile` 无「插件中心」文案 |',
  '',
  '- 过程坑（留档）：① 首版 `.kit-tile` 未设 `min-width:0`，`1fr` 轨道被名称固有宽度撑到 96px 间距，5 列挤成 2 列——量具读数（`gridTemplateColumns` vs 子项 `left` 间距）比截图可信；② 每分类各自成网格时「每行 2 枚」是**分组结构**问题不是尺寸问题，必须合并网格才提密度；③ 批量替换整函数时，替换块末尾要含原函数闭合行，否则残留孤儿行直接炸语法（本轮 `renderPlugins()}` 事故，靠 `protojscheck` 秒级定位）。',
  '- 工装新增：`patch_v147round2/3/4/5/6/7/8/8b.js`、`patch_kitscheck_r2/b/c/d/e.js`、`rulerproof.js`、`rsprobe.js`、`rsgeom.js`、`gridproof.js`、`rsshots.js`；改前快照 `tools/kits/snap/index-kits.2026-09-29-10-35.pre-round2.html`。',
  '- 复跑口径：`node tools/protojscheck.js prototype/index-kits.html` → `node --experimental-websocket tools/kits/kitscheck.js --shots`（**83/83**）→ `tools/kits/dlcheck.js`（22/22）→ 主原型 `r1478check`(5) / `protostructcheck`(6) / `time52check`(31) / `aiprovcheck`(12) / `aiusagecheck`(20) 全绿。',
  '',
].join(A.nl);
A.raw = A.raw.replace(/\s*$/, '') + A.nl + SEC;
if (bad) { console.error('!! 有不符项，零写入'); process.exit(1); }
if (!DRY) {
  fs.writeFileSync(path.resolve(CH), A.raw + A.nl);
  fs.writeFileSync(path.resolve(RQ), B.raw);
  console.log('已写入 ' + CH + ' , ' + RQ);
} else console.log('dry-run');
