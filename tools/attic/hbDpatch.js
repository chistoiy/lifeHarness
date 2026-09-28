const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const R = f => fs.readFileSync('tools/' + f, 'utf8').replace(/\r\n/g, '\n').replace(/\s+$/, '').split('\n');
let L = S.split('\n'), fails = 0;
function idx(sub, from) { const i = L.findIndex((l, k) => k >= (from || 0) && l.indexOf(sub) >= 0); if (i < 0) { console.log('MISS', sub.slice(0, 40)); fails++ } return i }
function cut(a, b, ins) { L = L.slice(0, a).concat(ins, L.slice(b + 1)); S = L.join('\n') }

/* 1) 两行 chips → 两个下拉 + 视图切换 */
(function () {
  const a = idx('<div class="mt-2.5 flex gap-2 overflow-x-auto no-scrollbar pb-0.5" id="hbSeg"></div>');
  const b = idx('<div class="mt-2 flex gap-1.5 overflow-x-auto no-scrollbar pb-0.5" id="hbCatRow"></div>');
  if (a >= 0 && b >= a) cut(a, b, R('hbD_bar.txt'));
})();

/* 2) renderHabits：下拉填充 + 视图分支 */
(function () {
  const a = idx("const segs=[['all',"), b = idx("const sg=document.getElementById('hbSeg')");
  if (a >= 0 && b >= a) cut(a, b, R('hbD_fill.txt'));
  const c = idx(' hbCatRow();'); if (c >= 0) { L.splice(c, 1); S = L.join('\n') }
  const d = idx("el.innerHTML=list.length?list.map(h=>hbCard(h)).join('')");
  if (d >= 0) { L[d] = R('hbD_list.txt')[0]; S = L.join('\n') }
})();

/* 3) 删除 hbCatRow（分类管理入口已进设置） */
(function () {
  const a = idx('function hbCatRow(){const el=document.getElementById(\'hbCatRow\')');
  const b = idx("分类管理</button>`}");
  if (a >= 0 && b >= a) { L.splice(a, b - a + 1); S = L.join('\n') }
})();

/* 4) 视图 JS + grid 图标 */
(function () {
  const a = idx('/* 补卡 */');
  L = L.slice(0, a).concat(R('hbD_js.txt'), [''], L.slice(a)); S = L.join('\n');
})();
(function () {
  const i = idx("list:'<path");
  if (i >= 0) L[i] = L[i].replace("list:'", "grid:'<rect x=\"3.5\" y=\"3.5\" width=\"7\" height=\"7\" rx=\"1.5\"/><rect x=\"13.5\" y=\"3.5\" width=\"7\" height=\"7\" rx=\"1.5\"/><rect x=\"3.5\" y=\"13.5\" width=\"7\" height=\"7\" rx=\"1.5\"/><rect x=\"13.5\" y=\"13.5\" width=\"7\" height=\"7\" rx=\"1.5\"/>',list:'");
  else { console.log('MISS gridicon'); fails++ }
  S = L.join('\n');
})();

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
