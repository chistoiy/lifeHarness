// 小工具整模块下架 · 共享面原型 index.html 摘除（产品负责人 2026-09-30 拍板）
// 自底向上按行删（行号互不影响）；区间首尾行必须命中给定标记，防行号漂移误删。
const fs = require('fs');
const f = 'prototype/index.html';
const src = fs.readFileSync(f, 'utf8');
let L = src.split('\n');
const snap = L.length;
function cut(from, to, first, last, must) {
  if (from > to) throw new Error('区间反了');
  if (!L[from - 1].includes(first)) throw new Error(`首行不符 ${from}: ${L[from - 1].trim().slice(0, 70)}`);
  if (!L[to - 1].includes(last)) throw new Error(`尾行不符 ${to}: ${L[to - 1].trim().slice(0, 70)}`);
  const blk = L.slice(from - 1, to).join('\n');
  for (const m of (must || [])) if (!blk.includes(m)) throw new Error(`锚点未命中 ${from}-${to}: ${m}`);
  L.splice(from - 1, to - from + 1);
  console.log(`cut ${from}-${to} (${to - from + 1} 行)`);
}
function sub1(oldS, newS, tag) {
  const s = L.join('\n');
  const n = s.split(oldS).length - 1;
  if (n !== 1) throw new Error(`anchor ${tag} hits=${n}`);
  L = s.replace(oldS, newS).split('\n');
  console.log('sub ' + tag);
}

/* ① 小工具 JS 段（4130 段标题 → 4237 收尾 }；4239 起是 V1.53 AI 使用记录段） */
cut(4130, 4237, '/* ================= 小工具合集 ================= */', '}',
  ['const TOOLS={', 'function openTool(k){', 'function renderPlugins()', 'function imgzGo()']);

/* ② boot 调用摘干净 */
sub1('renderTools(); renderPlugins(); ', '', 'boot-calls');

/* ③ NAV_MODS 去「工具」栏 */
sub1("['p-goals','目标',''],['p-tools','工具',''],['p-profile','我的','fix']",
  "['p-goals','目标',''],['p-profile','我的','fix']", 'nav-mods');

/* ④ ICONS 去 p-tools */
cut(2627, 2627, "'p-tools':'<rect", "'p-tools':'<rect");

/* ⑤ TITLES 去两屏标题 */
sub1("'p-tools':['小工具合集','本地轻工具 · 可插件拓展'],'p-toolDetail':['小工具','本地计算 · 无需联网'],",
  '', 'titles');

/* ⑥ D.grid：摘小工具枚；AI 验证枚改指 p-sub-ai（实现里另有 /settings/ai/verify 二级页） */
sub1("['🧰','小工具','p-tools'],['🍼','母婴','p-care'],['🧩','插件中心','p-pstore'],['🤖','AI 验证','p-tools']",
  "['🍼','母婴','p-care'],['🧩','插件中心','p-pstore'],['🤖','AI 验证','p-sub-ai']", 'grid');

/* ⑦ sheetPlugin 弹层（2427 注释 → 2440 收尾 div） */
cut(2427, 2440, '<!-- ===== 加载插件 ===== -->', '</div>', ['id="sheetPlugin"', 'onclick="plgInstall()"']);

/* ⑧ AI 增强页借用小工具屏的「重新验证」按钮（原型无独立验证屏·缺口已登记待补） */
cut(1472, 1472, "openTool('aiapi')", "openTool('aiapi')");

/* ⑨ p-tools + p-toolDetail 两屏（905 注释 → 923 收尾 </section>；925 是 P5 收集箱注释） */
cut(905, 923, '<!-- ===== P4e 小工具合集 ===== -->', '</section>',
  ['id="p-tools"', 'id="p-toolDetail"', 'id="toolGrid"', 'id="pluginList"']);
if (!L[905].includes('P5 收集箱')) throw new Error('P5 注释位置异常：' + L[905].trim().slice(0, 60));

fs.writeFileSync(f, L.join('\n'));
const out = fs.readFileSync(f, 'utf8');
for (const bad of ['p-tools', 'p-toolDetail', 'renderTools', 'renderPlugins', 'TOOL_CATS', 'sheetPlugin', 'openTool', 'plgInstall', 'toolGrid', 'pluginList']) {
  const n = out.split(bad).length - 1;
  if (n !== 0) throw new Error(`残留 ${bad} = ${n}`);
}
console.log(`lines ${snap} -> ${L.length} · chars ${src.length} -> ${out.length}`);
