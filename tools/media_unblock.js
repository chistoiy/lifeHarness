/* media_unblock.js · 影音游解禁落档（产品令 2026-10-07「影音游解禁可以开发」）
 * 用法：node tools/media_unblock.js
 * 三件：AGENTS「已下架勿复活」改口 · 需求清单模块 10 标回现行 · 注册表 media 解冻并定家。
 * 注册表改动：modules.media status=deferred→current、file 指回现行原型、note 去掉「冻结不动」、
 *             screens 里 p-pstore / sheetPlugin 两枚（插件中心已删屏）整条作废——影音游不承接插件演示。
 */
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const P = f => path.join(ROOT, f);
const log = [];

/* 1 · AGENTS */
let a = fs.readFileSync(P('AGENTS.md'), 'utf8');
const aOld = '- 已下架勿复活：小工具模块（V1.58 整模块作废）、影音游模块（延后裁定）、Legado 书源（V1.55 撤销）。';
const aNew = '- 已下架勿复活：小工具模块（V1.58 整模块作废）、Legado 书源（V1.55 撤销）、插件中心屏（2026-10-07 产品拍板删屏）。\n'
  + '  影音游模块**已于 2026-10-07 产品令解禁并开工**（此前「延后裁定」作废；规格＝`prototype/index-media.html`＋《影音游模块开发计划-20260922.md》）。';
if (a.split(aOld).length - 1 !== 1) throw new Error('AGENTS 锚点命中异常——中止');
fs.writeFileSync(P('AGENTS.md'), a.replace(aOld, aNew), 'utf8');
log.push('AGENTS');

/* 2 · 需求清单 模块 10 标题 */
let r = fs.readFileSync(P('docs/需求清单.md'), 'utf8');
const rOld = '### 模块 10 · 影音游（生活记录）【V1.25 已并入模块 3「记录」第四 tab，不再独立模块】';
const rNew = '### 模块 10 · 影音游（生活记录）【V1.25 已并入模块 3「记录」第四 tab，不再独立模块 · **2026-10-07 产品令解禁并开工**，四类＝电影/剧集/音乐/游戏（综艺并入剧集·播客留 V1.x）；专版事实源 `prototype/index-media.html`，落地口径＝《docs/影音游模块开发计划-20260922.md》】';
if (r.split(rOld).length - 1 !== 1) throw new Error('需求清单锚点命中异常——中止');
fs.writeFileSync(P('docs/需求清单.md'), r.replace(rOld, rNew), 'utf8');
log.push('需求清单');

/* 3 · 注册表 */
const REGF = P('prototype/_modules.json');
const reg = JSON.parse(fs.readFileSync(REGF, 'utf8'));
const m = reg.modules.find(x => x.id === 'media');
if (!m) throw new Error('注册表里没有 media 模块——中止');
m.status = 'current';
m.file = 'index-media.html';
m.rep = 'm-shelf';
m.aliases = Array.from(new Set([].concat(m.aliases || [], ['影音游', '电影', '剧集', '音乐', '游戏', '片单'])));
delete m.note;
const dropped = [];
reg.screens = reg.screens.filter(s => {
  if (s.id === 'p-pstore' || s.id === 'sheetPlugin') { dropped.push(s.id); return false }
  return true;
});
if (dropped.length !== 2) throw new Error('插件中心条目摘除数=' + dropped.length + '——中止');
if (Array.isArray(reg.frozen)) reg.frozen = reg.frozen.filter(f => f !== 'index-media.html');
fs.writeFileSync(REGF, JSON.stringify(reg, null, 2) + '\n', 'utf8');
log.push('注册表(media=current·家=m-shelf·摘 ' + dropped.join(',') + '·frozen 去 index-media)');
console.log('DONE ' + log.join(' ｜ '));
