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
function cut(t, startSub, endSub) {
  const a = L.findIndex(l => l.indexOf(startSub) >= 0), b = L.findIndex(l => l.indexOf(endSub) >= 0);
  if (a < 0 || b < a) { console.log('CUT MISS', t); fails++; return }
  L = L.slice(0, a).concat(L.slice(b)); S = L.join('\n');
}

/* 1) 顶部卡片里的统计入口移除（顶栏已有） */
rep('hero', `          <button class="ml-auto bg-white/20 rounded-full px-2.5 py-1 font-bold" onclick="navTo('p-habitStat');renderHabitStat()">周 / 月 / 年统计</button>
          <button class="bg-white/20 rounded-full px-2.5 py-1 font-bold" onclick="hbBackfillOpen()">补卡</button>`,
`          <button class="ml-auto bg-white/20 rounded-full px-2.5 py-1 font-bold" onclick="hbBackfillOpen()">补卡</button>`);

/* 2) 打卡设置：弹层 → 独立页面 */
cut('setsheet', '  <!-- ===== 习惯专版 · 打卡设置 ===== -->', '  <!-- ===== 习惯专版 · 分类 / 单位管理器 ===== -->');
before('setpage', '    <!-- ===== P12a 二级：数据与同步 ===== -->', R('hbF_page.txt').concat(['']));
rep('setopen', "function hbSetOpen(){hbSetRender();openSheet('sheetHabitSet')}",
 "function hbSetOpen(){navTo('p-habitSet');hbSetRender()}\nfunction hbSetReset(){Object.assign(HB_SET,{spanFromStart:true,autoChk:true,remindAll:true,weekStart:0,rateBase:0});hbSetRender();hbSetAfter('spanFromStart')}");
rep('titles', "'p-habitStat':['习惯统计','周 / 月 / 年 · 记录量 · 排行 · 纪录墙']",
 "'p-habitStat':['习惯统计','周 / 月 / 年 · 记录量 · 排行 · 纪录墙'],'p-habitSet':['打卡设置','统计口径 · 提醒 · 分类与单位']");

/* 3) 统计范围 */
before('scopejs', '/* 分类 / 单位自定义（同一套管理器） */', R('hbF_js.txt').concat(['']));
before('scopemk', '      <div class="mt-3 grad rounded-3xl p-4 text-white shadow-lg shadow-indigo-500/20">', R('hbF_scope.txt').concat(['']));
rep('agg', "function hbAgg(dim,off){const book=hbBook();", "function hbAgg(dim,off){const book=hbScopeBook();");
rep('stat', "function renderHabitStat(){const book=hbBook(),dim=hsDim", "function renderHabitStat(){const book=hbScopeBook(),dim=hsDim");
rep('timeagg', "function hbTimeAgg(dim,off){const book=hbBook(),bk=", "function hbTimeAgg(dim,off){const book=hbScopeBook(),bk=");
rep('refresh', " hbTimeRender(dim,off);", " hbTimeRender(dim,off);if(typeof hsScopeRender==='function')hsScopeRender();");

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
