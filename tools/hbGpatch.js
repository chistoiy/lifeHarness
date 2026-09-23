const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const R = f => fs.readFileSync('tools/' + f, 'utf8').replace(/\r\n/g, '\n').replace(/\s+$/, '').split('\n');
let L = S.split('\n'), fails = 0;
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length); L = S.split('\n');
}
function before(t, sub, ins) {
  const i = L.findIndex(l => l.indexOf(sub) >= 0);
  if (i < 0) { console.log('BEFORE MISS', t); fails++; return }
  L = L.slice(0, i).concat(ins, L.slice(i)); S = L.join('\n');
}

/* 1) 统计页热力图卡片 */
before('heatmk', '      <div class="mt-3 card"><div class="row-title">分类构成</div>',
[`      <div class="mt-3 card"><div class="flex items-center gap-2"><div class="row-title">打卡热力图</div><span class="ml-auto text-[10px] text-slate-400" id="hstHeatTip"></span></div>`,
 `        <div class="mt-2 overflow-x-auto no-scrollbar" id="hstHeat"></div>`,
 `        <div class="mt-2 flex items-center gap-1 text-[9px] text-slate-400" id="hstHeatLegend"></div>`,
 `      </div>`]);
rep('heatjs', " hbTimeRender(dim,off);if(typeof hsScopeRender==='function')hsScopeRender();",
 " hbTimeRender(dim,off);hbHeatRender();if(typeof hsScopeRender==='function')hsScopeRender();");

/* 2) 补卡弹层：补卡记录 */
before('bflogmk', '      <div id="bfValWrap" class="hidden mt-3 card !py-2.5 !px-3">',
[`      <div class="mt-3 card !py-2.5 !px-3">`,
 `        <div class="flex items-center gap-2"><span class="text-[11px] font-bold text-slate-500 flex-1">补卡记录</span><span class="text-[9.5px] text-slate-400" id="bfLogN"></span></div>`,
 `        <div class="mt-2 space-y-1.5" id="bfLogList"></div>`,
 `        <div class="mt-1.5 text-[9.5px] text-slate-400">撤销后该天的打卡与数值一并取消</div>`,
 `      </div>`]);
rep('bflogjs', " bfAtRender();", " bfAtRender();bfLogRender(h);");

/* 3) 热力图 / 补卡记录 JS */
before('gjs', '/* 分类 / 单位自定义（同一套管理器） */', R('hbG_js.txt').concat(['']));

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
