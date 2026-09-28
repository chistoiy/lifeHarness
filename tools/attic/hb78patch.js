const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const R = f => fs.readFileSync('tools/' + f, 'utf8').replace(/\r\n/g, '\n').replace(/\s+$/, '') + '\n';
let fails = 0;
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length);
}
function reg(t, a, b, ins) {
  const i = S.indexOf(a), j = i < 0 ? -1 : S.indexOf(b, i);
  if (i < 0 || j < 0) { console.log('REG MISS', t, i, j); fails++; return }
  S = S.slice(0, i) + ins + S.slice(j);
}

/* ===== A. 分类 / 单位可自定义 ===== */
rep('let-cats', "const HB_CATS=['健康'", "let HB_CATS=['健康'");
rep('let-units', "const HB_UNITS=['分钟'", "let HB_UNITS=['分钟'");
// 列表页分类筛选条
rep('catrow', `      <div class="mt-2.5 flex gap-2 overflow-x-auto no-scrollbar pb-0.5" id="hbSeg"></div>`,
`      <div class="mt-2.5 flex gap-2 overflow-x-auto no-scrollbar pb-0.5" id="hbSeg"></div>
      <div class="mt-2 flex gap-1.5 overflow-x-auto no-scrollbar pb-0.5" id="hbCatRow"></div>`);
// 管理器弹层
rep('mgrsheet', '  <!-- ===== 主题市场 ===== -->', R('hb7_cats.txt') + '  <!-- ===== 主题市场 ===== -->');
// 管理器 JS
rep('mgrjs', '/* 待办 / 计时回写 */', R('hb7_js.txt') + '/* 待办 / 计时回写 */');
// 列表按分类过滤
rep('catfilter', ` if(hbSeg==='grp')list=book.filter(h=>h.group);if(hbSeg==='neg')list=book.filter(h=>h.type==='neg');if(hbSeg==='arch')list=HABITS.filter(h=>h.arch);`,
` if(hbSeg==='grp')list=book.filter(h=>h.group);if(hbSeg==='neg')list=book.filter(h=>h.type==='neg');if(hbSeg==='arch')list=HABITS.filter(h=>h.arch);
 if(hbCatF!=='全部')list=list.filter(h=>h.cat===hbCatF);
 hbCatRow();`);
// 编辑表单：分类 chips 加自定义入口
rep('hecats', ` document.getElementById('heCats').innerHTML=HB_CATS.map(c=>heChip(c,heCat,"hePick('cat','"+c+"')",'!text-[10px]')).join('');`,
` document.getElementById('heCats').innerHTML=HB_CATS.map(c=>heChip(c,heCat,"hePick('cat','"+c+"')",'!text-[10px]')).join('')+'<button class="chip !text-[10px]" onclick="hbMgrOpen(\\'cat\\')">＋ 自定义</button>';`);
// 编辑表单：单位 select → 可自定义 chips
rep('hemarkup', `          <select id="heUnit" class="sel flex-1" onchange="heUnitChg()"></select>`,
`          <div class="flex-1 min-w-0 flex gap-1.5 flex-wrap justify-end" id="heUnits"></div>`);
rep('herender', " document.getElementById('heUnit').innerHTML=HB_UNITS.map(u=>`<option ${u===heUnit?'selected':''}>${u}</option>`).join('');",
" document.getElementById('heUnits').innerHTML=HB_UNITS.map(u=>heChip(u,heUnit,\"heUnitChg('\"+u+\"')\",'!text-[10px]')).join('')+'<button class=\"chip !text-[10px]\" onclick=\"hbMgrOpen(\\'unit\\')\">＋ 自定义</button>';");
rep('heunitchg', "function heUnitChg(){heUnit=document.getElementById('heUnit').value}",
"function heUnitChg(u){heUnit=u||heUnit;heRender()}");
rep('hesave', " const unit=heValMode==='one'?document.getElementById('heUnit').value:'';",
" const unit=heValMode==='one'?heUnit:'';");
// 操作菜单加管理入口
rep('ops', "const HO_OPS=[['编辑习惯','pen'],['复制到新分类','plus']",
"const HO_OPS=[['编辑习惯','pen'],['分类管理','cog'],['单位管理','cog'],['复制到新分类','plus']");
rep('opsrun', " else if(k==='删除习惯'){",
" else if(k==='分类管理')hbMgrOpen('cat');\n else if(k==='单位管理')hbMgrOpen('unit');\n else if(k==='删除习惯'){");

/* ===== B. 统计：指定周 / 月 / 年 + 同比环比 ===== */
rep('period', `      <div class="mt-3 grad rounded-3xl p-4 text-white shadow-lg shadow-indigo-500/20">`,
`      <div class="mt-2 card !py-2 !px-2.5 flex items-center gap-1.5">
        <button class="w-7 h-7 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-500 flex items-center justify-center shrink-0" onclick="hsStep(-1)" title="更早一期"><svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M15 19l-7-7 7-7"/></svg></button>
        <button class="flex-1 min-w-0 text-center text-[12px] font-extrabold" id="hsPeriod" onclick="hsTogglePick()">本周</button>
        <button id="hsNext" class="w-7 h-7 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-500 flex items-center justify-center shrink-0" onclick="hsStep(1)" title="更近一期"><svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5l7 7-7 7"/></svg></button>
        <span id="hsNowTag" class="text-[9px] px-1.5 py-0.5 rounded-full font-bold shrink-0 bg-slate-100 dark:bg-slate-800 text-slate-400">当前</span>
      </div>
      <div id="hsPickWrap" class="hidden mt-2 card !py-2 !px-3"><div class="flex items-center justify-center" id="hsPickRow"></div></div>
      <div class="mt-3 grad rounded-3xl p-4 text-white shadow-lg shadow-indigo-500/20">`);
rep('cmp', `      <div class="mt-3 card"><div class="row-title">分类构成</div>`,
`      <div class="mt-3 card"><div class="flex items-center gap-2"><div class="row-title">同期对比</div><span class="ml-auto text-[10px] text-slate-400" id="hsCmpTip"></span></div><div class="mt-2 grid grid-cols-3 gap-2" id="hsCmp"></div></div>
      <div class="mt-3 card"><div class="row-title">分类构成</div>`);
rep('ranktip', `id="hstSortTip">按完成率<`, `id="hstSortTip">按记录量 · 行内含环比<`);
reg('agg', 'function hbDimDays(dim){', 'function hbYearBars(h){', R('hb8_agg.txt'));
reg('stat', 'function renderHabitStat(){', '/* 顶栏页内动作 */', R('hb8_stat.txt'));

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED size=' + S.length);
