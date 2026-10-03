/* govnav.js · 屏单一归属兜底机制注入器（治理批 动刀批 §3-4：navTo 兜底 toast＋重定向表）。
 * 用法：node tools/govnav.js <原型文件名> [--dry]     （文件名如 index.html，不带路径）
 * 幂等：LH-GOV-START 至 LH-GOV-END 哨兵块整体重生成；三处守卫锚点带 LH-GOV-G 标记，已存在则跳过。
 * 护栏（AGENTS 脚本纪律）：每个锚点必须命中 1 次否则 rc=1 不写盘；写后校验体积单调增。
 * 重定向表来源：prototype/_modules.json（屏 home 不在本文件 → 跳新家；status=dropped 且本文件有副本/引用 → 下架 toast；collision/deferred 不进表）。
 */
const fs = require('fs');

const args = process.argv.slice(2);
const dry = args.includes('--dry');
const f = args.find(a => !a.startsWith('--'));
if (!f) { console.log('用法: node tools/govnav.js <原型文件名> [--dry]'); process.exit(2); }

const reg = JSON.parse(fs.readFileSync('prototype/_modules.json', 'utf8'));
const modByFile = {};
for (const m of reg.modules) modByFile[m.file] = m.name;

const p = 'prototype/' + f;
let html = fs.readFileSync(p, 'utf8');
const before = html.length;
const fail = msg => { console.error('FAIL ' + msg); process.exit(1); };

/* 1. 重定向表（=注册表 violations 中本文件名下的越权副本）与下架集 */
const RED = {}, DROP = {};
for (const v of (reg.violations || [])) {
  if (v.exempt || v.file !== f) continue;
  const s = reg.screens.find(x => x.id === v.id);
  if (!s || s.status === 'collision' || s.status === 'deferred' || !s.home) continue;
  RED[v.id] = [s.home, modByFile[s.home] || s.home];
}
for (const s of reg.screens) {
  if (s.status === 'dropped' && ((s.files && s.files[f]) || html.includes('"' + s.id + '"') || html.includes("'" + s.id + "'"))) DROP[s.id] = 1;
}

/* 2. 守卫插入：navTo / setPage / openSheet */
function guardOnce(anchor, replacement, mark, name) {
  if (html.includes(mark)) return 'skip';
  const n = html.split(anchor).length - 1;
  if (n !== 1) fail(name + ' 锚点命中 ' + n + ' 次（须恰 1）: ' + JSON.stringify(anchor));
  html = html.replace(anchor, replacement);
  return 'ok';
}
const r1 = guardOnce(
  'function navTo(p){',
  'function navTo(p){/*LH-GOV-G*/if(!document.getElementById(p)){lhGone(p);return;}',
  '/*LH-GOV-G*/if(!document.getElementById(p)){lhGone(p)', 'navTo');
const r2 = guardOnce(
  'function setPage(p){',
  'function setPage(p){/*LH-GOV-G2*/if(!document.getElementById(p)){lhGone(p);return;}',
  '/*LH-GOV-G2*/', 'setPage');
const r3 = guardOnce(
  "function openSheet(id){ const s=$('#'+id);",
  "function openSheet(id){ const s=$('#'+id);/*LH-GOV-G3*/ if(!s){lhGone(id);return;}",
  '/*LH-GOV-G3*/', 'openSheet');

/* 3. 主块（哨兵内，重生成） */
const START = '/*LH-GOV-START*/', END = '/*LH-GOV-END*/';
const block = '<script>' + START + '\n' +
  '/* 屏单一归属·navTo 兜底与深链重定向（治理批 2026-10-03）。本块由 tools/govnav.js 生成，禁手改。 */\n' +
  '(function(){\n' +
  'var RED=window.LH_REDIRECTS=' + JSON.stringify(RED) + ';\n' +
  'var DROP=window.LH_DROPPED=' + JSON.stringify(DROP) + ';\n' +
  'window.lhGone=function(id){var r=RED[id];\n' +
  "  if(r){try{toast('「'+((typeof TITLES!=='undefined'&&TITLES[id]&&TITLES[id][0])||id)+'」现居「'+r[1]+'」· 跳转中');}catch(e){}" +
  'setTimeout(function(){location.href=r[0]+\'#\'+id;},700);return;}\n' +
  "  if(DROP[id]){try{toast('该功能已下架 · 演示已移除');}catch(e){}return;}\n" +
  "  console.warn('[lh-gov] 目标不在本版:',id);\n" +
  '};\n' +
  "function boot(){var h='';try{h=decodeURIComponent((location.hash||'').slice(1));}catch(e){}\n" +
  "  if(!h)return;var el=document.getElementById(h);\n" +
  "  if(el){if(el.classList.contains('page')&&!el.classList.contains('active')&&typeof navTab==='function')navTab(h);return;}\n" +
  '  var r=RED[h];if(r)location.replace(r[0]+\'#\'+h);}\n' +
  "window.lhBoot=function(){try{boot();}catch(e){window.__lhBootErr=String(e&&e.stack||e);}};\n" +
  'window.lhBoot();\n' +
  "window.addEventListener('load',function(){window.lhBoot();});\n" +
  '})();\n' + END + '</script>';
const reBlock = new RegExp('<script>' + START.replace(/[*]/g, '\\$&') + '[\\s\\S]*?' + END.replace(/[*]/g, '\\$&') + '</script>');
if (reBlock.test(html)) html = html.replace(reBlock, block);
else {
  const i = html.lastIndexOf('</body>');
  if (i < 0) fail('缺 </body>');
  html = html.slice(0, i) + block + '\n' + html.slice(i);
}

/* 4. 校验与写盘：改写幅度须可解释（哨兵块重生成可增可减，超界视为跑飞） */
if (Math.abs(html.length - before) > 60000) fail('体积变化异常（' + before + '→' + html.length + '）');
if (!html.includes(START) || !html.includes(END) || html.lastIndexOf('</body>') < 0) fail('结构校验失败');
const rep = { file: f, redirects: Object.keys(RED).length, dropped: Object.keys(DROP).length, guards: [r1, r2, r3].join(','), size: before + '→' + html.length };
console.log(JSON.stringify(rep));
if (dry) { console.log('DRY：未写盘'); process.exit(0); }
fs.writeFileSync(p, html, 'utf8');
console.log('WROTE ' + p);
