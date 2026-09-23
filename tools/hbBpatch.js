const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const R = f => fs.readFileSync('tools/' + f, 'utf8').replace(/\r\n/g, '\n').replace(/\s+$/, '').split('\n');
let L = S.split('\n'), fails = 0;
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length);
  L = S.split('\n');
}
function after(t, sub, ins) {
  const i = L.findIndex(l => l.indexOf(sub) >= 0);
  if (i < 0) { console.log('AFTER MISS', t); fails++; return }
  L = L.slice(0, i + 1).concat(ins, L.slice(i + 1)); S = L.join('\n');
}

/* ---- A. 统计口径：从开始跟踪日起算 ---- */
rep('cnt', "function hbCnt(h,dim,off){off=off||0;const days=hbDimDays(dim);",
 "function hbCnt(h,dim,off){off=off||0;const days=Math.min(hbDimDays(dim),hbEffDays(h,dim,off));if(days<=0)return 0;");
rep('tot', "function hbTot(h,dim,off){off=off||0;const days=hbDimDays(dim),cnt=",
 "function hbTot(h,dim,off){off=off||0;const days=Math.max(1,Math.min(hbDimDays(dim),hbEffDays(h,dim,off))),cnt=");
rep('subtot', "const c=hbCnt(h,dim,off),a=hbSubAvg(h,off),days=hbDimDays(dim);",
 "const c=hbCnt(h,dim,off),a=hbSubAvg(h,off),days=Math.max(1,Math.min(hbDimDays(dim),hbEffDays(h,dim,off)));");
rep('rate', "function hbRate(h){const tot=h.cycle==='month'?(h.targetM||1):7,",
 "function hbRate(h){const tot=h.cycle==='month'?(h.targetM||1):hbDueDays(h),");
rep('agg', `function hbAgg(dim,off){const book=hbBook();let cnt=0,val=0,rec=0;const days=hbDimDays(dim);
 book.forEach(h=>{const t=hbTot(h,dim,off);cnt+=t.cnt;val+=t.val;rec+=hbRecN(h,dim,off)});
 return {cnt:cnt,val:val,rec:rec,days:days,n:book.length,rate:Math.min(100,Math.round(cnt/Math.max(1,book.length*days)*100))}}`,
 `function hbAgg(dim,off){const book=hbBook();let cnt=0,val=0,rec=0,dspan=0;
 book.forEach(h=>{const t=hbTot(h,dim,off);cnt+=t.cnt;val+=t.val;rec+=hbRecN(h,dim,off);dspan+=t.dayN});
 const avg=book.length?dspan/book.length:1;
 return {cnt:cnt,val:val,rec:rec,days:avg,span:dspan,n:book.length,rate:Math.min(100,Math.round(cnt/Math.max(1,dspan)*100))}}`);
rep('hours', " const c=hbCnt(h,dim,off),maxBack=dim==='w'?6:dim==='m'?29:364;",
 " const c=hbCnt(h,dim,off),maxBack=Math.min(dim==='w'?6:dim==='m'?29:364,Math.max(0,hbEffDays(h,dim,off)-1));");
rep('tag', `        <button id="hsBtnA" class="seg-pill" onclick="hsPick('a')">本年</button>
      </div>`,
 `        <button id="hsBtnA" class="seg-pill" onclick="hsPick('a')">本年</button>
        <span id="hsBaseTag" class="ml-auto self-center text-[9px] px-2 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-500 shrink-0">按开始跟踪日</span>
      </div>`);
after('tagjs', "const st=document.getElementById('hstSub');if(st)st.textContent=",
 [" const bt=document.getElementById('hsBaseTag');if(bt){bt.textContent=HB_SET.spanFromStart?'按开始跟踪日':'按周期天数';bt.title='打卡设置可切换'}"]);

/* ---- B. 打卡设置弹层 ---- */
rep('setsheet', '  <!-- ===== 习惯专版 · 分类 / 单位管理器 ===== -->', R('hbB_sheet.txt').join('\n') + '\n  <!-- ===== 习惯专版 · 分类 / 单位管理器 ===== -->');
rep('setjs', '/* 待办 / 计时回写 */', R('hbB_set.txt').join('\n') + '\n/* 待办 / 计时回写 */');
rep('hdr', ` if(p==='p-habits')html=hbHdrBtn('chart','周 / 月 / 年统计',"navTo('p-habitStat');renderHabitStat()")+hbHdrBtn('plus','新建习惯','heOpen()');`,
 ` if(p==='p-habits')html=hbHdrBtn('chart','周 / 月 / 年统计',"navTo('p-habitStat');renderHabitStat()")+hbHdrBtn('cog','打卡设置','hbSetOpen()')+hbHdrBtn('plus','新建习惯','heOpen()');
 else if(p==='p-habitStat')html=hbHdrBtn('cog','打卡设置','hbSetOpen()');`);
rep('ops', "const HO_OPS=[['编辑习惯','pen'],['分类管理','cog']", "const HO_OPS=[['编辑习惯','pen'],['打卡设置','cog'],['分类管理','cog']");
rep('opsrun', " else if(k==='分类管理')hbMgrOpen('cat');", " else if(k==='打卡设置')hbSetOpen();\n else if(k==='分类管理')hbMgrOpen('cat');");
rep('autochk', "function syncHabit(name){const key=",
 "function syncHabit(name){if(!HB_SET.autoChk){toast('自动打卡已关闭 · 请到习惯页手动打卡');return}const key=");

/* ---- C. 习惯开始跟踪日期 ---- */
rep('state', "let heValMode='off',heRule='all',heSubs=[],heUnit='分钟',heGoal='30',heRemindVal='07:00';",
 "let heValMode='off',heRule='all',heSubs=[],heUnit='分钟',heGoal='30',heRemindVal='07:00',heStart='2026-09-19';");
rep('open1', "  heUnit=h.unit||'分钟';heGoal=String(h.goal||30)}", "  heUnit=h.unit||'分钟';heGoal=String(h.goal||30);heStart=h.start||'2026-09-19'}");
rep('open2', "heSubs=[];heUnit='分钟';heGoal='30'}", "heSubs=[];heUnit='分钟';heGoal='30';heStart='2026-09-19'}");
rep('render', " const vmodes=[['off','只打卡不记量'],['one','记单一数值'],['group','分成一组子项']];",
 " const sd=document.getElementById('heStart');if(sd){sd.value=heStart;sd.max='2026-09-19'}\n const vmodes=[['off','只打卡不记量'],['one','记单一数值'],['group','分成一组子项']];");
rep('layout', " document.getElementById('heWheelWrap').classList.toggle('hidden',heRemind!=='on');",
 " document.getElementById('heStartWrap').classList.toggle('hidden',!heId);\n const sh=document.getElementById('heStartHint');if(sh&&heId)sh.textContent='已跟踪 '+hbSpanD(HABITS.find(x=>x.id===heId)||{start:heStart})+' 天 · 日均与达成率按此起算（可在打卡设置切换）';\n document.getElementById('heWheelWrap').classList.toggle('hidden',heRemind!=='on');");
rep('save', "arch:false,start:'09-19',group:grp", "arch:false,start:heStart,group:grp");
rep('startrow', `<div class="flex justify-between"><span class="text-slate-400">开始跟踪</span><b>\${h.start||'2026-08'}</b></div></div>`,
 `<div class="flex justify-between"><span class="text-slate-400">开始跟踪</span><b>\${h.start||'2026-08'} · 已跟踪 \${hbSpanD(h)} 天</b></div></div>`);

/* ---- D. 补记标记可见 ---- */
rep('dots', `title="周\${HB_WD[i]}\${h.v&&h.v[i]?' · '+hbValTxt(h,i):''}"`, `title="周\${HB_WD[i]}\${h.v&&h.v[i]?' · '+hbValTxt(h,i):''}\${(h.bf&&h.bf[i])?' · 补记':''}\${h.at&&h.at[i]?' · '+h.at[i]:''}"`);
rep('cardbf', `<span class="ml-auto font-extrabold \${rate>=70?'text-emerald-500':rate>=40?'text-sun':'text-rose-500'}">\${rate}%</span></div>`,
 `<span class="ml-auto font-extrabold \${rate>=70?'text-emerald-500':rate>=40?'text-sun':'text-rose-500'}">\${rate}%</span></div>
  \${(h.bf&&h.bf.some?h.bf.filter(v=>v).length:0)?'<div class="mt-1 text-[9px] text-slate-400">本周含补记 '+h.bf.filter(v=>v).length+' 天</div>':''}`);

/* ---- E. 开始跟踪日期控件 + 周起始日生效 ---- */
rep('startmarkup', `      <div class="mt-3 text-[11px] font-bold text-slate-500">提醒时间</div>`,
`      <div id="heStartWrap" class="hidden mt-3 card !py-2.5 !px-3">
        <div class="flex items-center gap-2 text-xs"><span class="flex-1">开始跟踪</span><input id="heStart" type="date" class="sel !py-1.5" max="2026-09-19" onchange="heStartChg()"></div>
        <div class="mt-1 text-[10px] text-slate-400" id="heStartHint"></div>
      </div>
      <div class="mt-3 text-[11px] font-bold text-slate-500">提醒时间</div>`);
rep('wdidx', "function hbWdIdx(d){return (d.getDay()+6)%7}", "function hbWdIdx(d){return (d.getDay()+(HB_SET.weekStart?0:6))%7}");
rep('wdbf', "document.getElementById('bfHead').innerHTML=['一','二','三','四','五','六','日'].map",
 "document.getElementById('bfHead').innerHTML=hbWdHead().map");
rep('wddc', `<div class="mt-2 grid grid-cols-7 gap-1 text-center text-[9px] text-slate-400">\${['一','二','三','四','五','六','日'].map`,
 `<div class="mt-2 grid grid-cols-7 gap-1 text-center text-[9px] text-slate-400">\${hbWdHead().map`);

/* ---- F. 统计入口移到顶部卡片 ---- */
rep('heroentry', `          <button class="ml-auto bg-white/20 rounded-full px-2.5 py-1 font-bold" onclick="hbBackfillOpen()">补卡</button>`,
`          <button class="ml-auto bg-white/20 rounded-full px-2.5 py-1 font-bold" onclick="navTo('p-habitStat');renderHabitStat()">周 / 月 / 年统计</button>
          <button class="bg-white/20 rounded-full px-2.5 py-1 font-bold" onclick="hbBackfillOpen()">补卡</button>`);
(function () {
  const i = L.findIndex(l => l.indexOf('查看周 / 月 / 年统计') >= 0);
  if (i < 0) { console.log('MISS bottomlink'); fails++ } else L.splice(i, 1);
  S = L.join('\n');
})();

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
S = L.join('\n');
rep('startchg', "function hbSetT(k){", "function heStartChg(){heStart=document.getElementById('heStart').value||heStart;heLayout()}\nfunction hbSetT(k){");
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
