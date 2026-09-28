const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const R = f => fs.readFileSync('tools/' + f, 'utf8').replace(/\r\n/g, '\n').replace(/\s+$/, '').split('\n');
let L = S.split('\n');
let fails = 0;
function find(sub, from) { const i = L.findIndex((l, k) => k >= (from || 0) && l.indexOf(sub) >= 0); if (i < 0) { console.log('FIND MISS', sub.slice(0, 40)); fails++ } return i }
function spliceLines(a, b, ins) { L = L.slice(0, a).concat(ins, L.slice(b)) }

/* A) 补卡弹层：月历 + 习惯选择 + 子项数值 */
(function () {
  const a = find('  <!-- ===== 习惯专版 · 补卡 ===== -->');
  const b = find('  <!-- ===== 习惯专版 · 记一次触发（负向） ===== -->');
  if (a >= 0 && b > a) spliceLines(a, b, R('hb9_bf.txt'));
})();

/* B) 补卡 JS + 月历公共组件 */
(function () {
  const a = find('/* 补卡 */'), b = find('/* 触发记录 */');
  if (a >= 0 && b > a) spliceLines(a, b, R('hb9_cal.txt').concat([''], R('hb9_js.txt')));
})();

/* C) 详情页近 30 天 → 打卡日历 */
(function () {
  const a = find('row-title">近 30 天');
  const b = find('全局统计</button></div></div>', a);
  if (a >= 0 && b >= a) spliceLines(a, b + 1, R('hb9_detail.txt'));
})();

/* D) 移除与顶栏重复的「编辑习惯 / 更多」按钮行 */
(function () {
  const i = find('onclick="heOpen(\'${h.id}\')">编辑习惯</button>');
  if (i >= 0) L[i] = '   </div>`;';
})();

/* E) hbHist 读取补记标记（对象化后判 .ok） */
(function () {
  const i = find('function hbHist(h){');
  if (i >= 0) L[i] = L[i].replace("if(h.ex&&h.ex[29-i]){out.push(1);continue}",
    "if(h.ex&&h.ex[29-i]&&h.ex[29-i].ok){out.push(1);continue}");
})();

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
S = L.join('\n');
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { const ln = /SYNTAX|:(\d+)/.exec(e.stack || ''); console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED lines=' + L.length);
