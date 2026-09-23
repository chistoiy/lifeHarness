const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
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
function after(t, sub, ins) {
  const i = L.findIndex(l => l.indexOf(sub) >= 0);
  if (i < 0) { console.log('AFTER MISS', t); fails++; return }
  L = L.slice(0, i + 1).concat(ins, L.slice(i + 1)); S = L.join('\n');
}

/* 1) 组习惯不再跨单位合计 */
rep('tot', ` return {cnt:cnt,dayN:days,val:cnt*per,avg:per,rate:Math.min(100,Math.round(cnt/days*100)),
   base:hbBaseTxt(dim,off),unit:h.group?'项次':(h.unit||'次')}}`,
 ` return {cnt:cnt,dayN:days,val:h.group?null:cnt*per,avg:per,rate:Math.min(100,Math.round(cnt/days*100)),
   base:hbBaseTxt(dim,off),unit:h.group?'':(h.unit||'次')}}`);
rep('card', " · 量 <b class=\"text-brand-500\">\${tw.val}</b>\${tw.unit}",
 " · \${h.group?('子项 <b class=\"text-brand-500\">'+((h.sv&&h.sv[6]||[]).filter((v,k)=>v>=(h.subs[k].goal||0)).length)+'/'+h.subs.length+'</b> 达标'):('量 <b class=\"text-brand-500\">'+tw.val+'</b>'+tw.unit)}");
rep('detail', `<div class="card !py-2.5"><b class="text-base text-brand-500">\${hbHasVal(h)?T.val:'—'}</b><div class="text-slate-400">\${hbHasVal(h)?(h.group?'总记录量':'总'+T.unit):'未记量'}</div></div>`,
 `<div class="card !py-2.5"><b class="text-base text-brand-500">\${h.group?h.subs.length+' 项':(hbHasVal(h)?T.val:'—')}</b><div class="text-slate-400">\${h.group?'子项分别统计':(hbHasVal(h)?'总'+T.unit:'未记量')}</div></div>`);
rep('rank', `\${hbHasVal(h)?t.val+' '+t.unit:hbRate(h)+'%'}`, `\${h.group?'按子项':(hbHasVal(h)?t.val+' '+t.unit:hbRate(h)+'%')}`);

/* 2) 统计口径：正向与负向分开 */
rep('agg', `function hbAgg(dim,off){const book=hbScopeBook();let cnt=0,val=0,rec=0,dspan=0;
 book.forEach(h=>{const t=hbTot(h,dim,off);cnt+=t.cnt;val+=t.val;rec+=hbRecN(h,dim,off);dspan+=t.dayN});
 const avg=book.length?dspan/book.length:1;
 return {cnt:cnt,val:val,rec:rec,days:avg,span:dspan,n:book.length,rate:Math.min(100,Math.round(cnt/Math.max(1,dspan)*100))}}`,
 `function hbAgg(dim,off){const book=hbScopeBook(),pos=book.filter(h=>h.type==='pos');let cnt=0,val=0,rec=0,dspan=0;
 pos.forEach(h=>{const t=hbTot(h,dim,off);cnt+=t.cnt;val+=t.val||0;rec+=hbRecN(h,dim,off);dspan+=t.dayN});
 const avg=pos.length?dspan/pos.length:1;
 return {cnt:cnt,val:val,rec:rec,days:avg,span:dspan,n:pos.length,all:book.length,rate:Math.min(100,Math.round(cnt/Math.max(1,dspan)*100))}}`);
rep('agguse', "const A=hbAgg(dim,off),P=hbAgg(dim,off+1),Y=hbAgg(dim,off+(dim==='a'?1:dim==='m'?12:52));",
 "const A=hbAgg(dim,off),P=hbAgg(dim,off+1),Y=hbAgg(dim,off+(dim==='a'?1:dim==='m'?12:52)),posBook=book.filter(h=>h.type==='pos');");
rep('sub', "book.length+' 个跟踪中习惯 · 打卡 '+A.cnt+' 次 · 数值记录 '+A.rec+' 条 · 负向触发 '",
 "A.all+' 个跟踪中习惯（正向 '+posBook.length+' · 负向 '+(A.all-posBook.length)+'）· 正向打卡 '+A.cnt+' 次 · 数值记录 '+A.rec+' 条 · 负向触发 '");
rep('rankpos', "if(rk)rk.innerHTML=book.slice().sort((a,b)=>hbTot(b,dim,off).cnt-hbTot(a,dim,off).cnt||hbRate(b)-hbRate(a)).map((h,i)=>{const t=hbTot(h,dim,off),pv=hbTot(h,dim,off+1);",
 "if(rk)rk.innerHTML=posBook.slice().sort((a,b)=>hbTot(b,dim,off).cnt-hbTot(a,dim,off).cnt||hbRate(b)-hbRate(a)).map((h,i)=>{const t=hbTot(h,dim,off),pv=hbTot(h,dim,off+1);");
rep('rankempty', "hbDlt(t.cnt,pv.cnt,h.type==='pos')}<b class=\"w-16 text-right text-[11.5px] text-brand-500\">",
 "hbDlt(t.cnt,pv.cnt,true)}<b class=\"w-16 text-right text-[11.5px] text-brand-500\">");

/* 3) 统计页折叠 */
before('more', '      <div class="mt-3 card"><div class="flex items-center gap-2"><div class="row-title">打卡时段分析</div>',
 ['      <button id="hsMoreBtn" class="mt-3 w-full card !py-2.5 text-[11px] font-bold text-slate-500" onclick="hsMoreT()">展开更多分析 · 时段 / 热力 / 分类 / 排行 / 组构成 / 纪录墙</button>',
  '      <div id="hsMore" class="hidden">']);
after('moreend', '<div class="mt-3 card"><div class="row-title">连续纪录墙</div>', ['      </div>']);
rep('morejs', "function hsStep(d){", "function hsMoreT(){const w=document.getElementById('hsMore'),b=document.getElementById('hsMoreBtn');if(!w||!b)return;\n const on=w.classList.contains('hidden');w.classList.toggle('hidden',!on);\n b.textContent=on?'收起更多分析':'展开更多分析 · 时段 / 热力 / 分类 / 排行 / 组构成 / 纪录墙';if(on)renderHabitStat()}\nfunction hsStep(d){");

/* 4) 记量步进档位 */
rep('step1', "onclick=\"hbLogStep(${k},-${Math.max(1,Math.round(goal/4))})\"", "onclick=\"hbLogStep(${k},-hbStepOf(goal))\"");
rep('step2', "onclick=\"hbLogStep(${k},${Math.max(1,Math.round(goal/4))})\"", "onclick=\"hbLogStep(${k},hbStepOf(goal))\"");
rep('stepfn', "function hbLogStep(k,d){", "function hbStepOf(g){const L2=[1,2,5,10,15,20,25,30,50,60,100,150,200,300,500,1000];\n for(let i=0;i<L2.length;i++)if(L2[i]>=Math.max(1,Math.round((+g||10)/4)))return L2[i];return 1000}\nfunction hbLogStep(k,d){");

/* 5) 管理器删除守卫：自动展开迁移面板 */
rep('panel', "function hbMgrPanel(i){const el=document.getElementById('hmMv'+i);if(!el)return;\n const on=el.classList.contains('flex');el.classList.toggle('hidden',on);el.classList.toggle('flex',!on)}",
 "function hbMgrPanel(i,force){const el=document.getElementById('hmMv'+i);if(!el)return;\n const on=force?false:el.classList.contains('flex');el.classList.toggle('hidden',on);el.classList.toggle('flex',!on);\n if(force)el.scrollIntoView({block:'nearest'})}");
rep('guard', "if(cfg.used(c)){hbMgrPanel(i);toast(", "if(cfg.used(c)){hbMgrPanel(i,1);toast(");

/* 6) 回看日：组子项与周点按查看日高亮 */
rep('subchips', "function hbSubChips(h){if(!h.group)return '';const cur=(h.sv&&h.sv[6]&&h.sv[6].some(v=>v))?h.sv[6]:null;",
 "function hbSubChips(h){if(!h.group)return '';const vi=6+hbDayOff;const cur=(h.sv&&h.sv[vi]&&h.sv[vi].some(v=>v))?h.sv[vi]:null;");
rep('dots', "${h.type==='pos'?(v?'✓':''):(v?'':'!')}", "${i===6+hbDayOff?'ring-1 ring-brand-500 ring-offset-1 dark:ring-offset-slate-900 ':''}${h.type==='pos'?(v?'✓':''):(v?'':'!')}");

/* 7) 筛选文案缩短 */
rep('segs', "const segs=[['all','全部'],['todo','待打卡'],['ok','已达成'],['grp','分组习惯'],['neg','负向控制'],['arch','已归档']];",
 "const segs=[['all','全部'],['todo','待打卡'],['ok','已达成'],['grp','分组'],['neg','负向'],['arch','归档']];");

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED J');
