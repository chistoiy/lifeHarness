const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
let fails = 0;
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t, a.slice(0, 40)); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length);
}
const NL = s => s.replace(/\n/g, '\r\n');

// ---- 聚合口径：按真实达成率折算，不再用周记录 ×51.6 ----
rep('agg', `function hbSubTot(h,dim){if(!h.group)return [];const f=dim==='w'?1:dim==='m'?4.3:12*4.3;
  const base=(h.sv||[]).reduce((a,row)=>{row.forEach((v,k)=>a[k]=(a[k]||0)+v);return a},[]);
  return h.subs.map((s,k)=>({n:s.n,unit:s.unit,val:Math.round((base[k]||0)*f),goal:s.goal*(dim==='w'?7:dim==='m'?30:365)}))}
function hbTot(h,dim){const arr=dim==='w'?h.w:hbHist(h);const cnt=arr.filter(v=>v).length;
  const f=dim==='w'?1:dim==='m'?4.3:12*4.3;
  let val=0;
  if(h.group){val=hbSubTot(h,dim).reduce((a,x)=>a+x.val,0)}
  else if(h.unit){val=Math.round((h.v||[]).reduce((a,v)=>a+(+v||0),0)*f)}
  const days=dim==='w'?7:dim==='m'?30:365;
  const done=dim==='w'?cnt:Math.round(cnt*(dim==='m'?4.3:50));
  return {cnt:done,dayN:days,val:val,avg:done?Math.round(val/done):0,rate:Math.round(done/days*100),
    base:dim==='w'?'本周':dim==='m'?'本月':'本年',unit:h.group?'项次合计':(h.unit||'次')}}`,
`function hbDimDays(dim){return dim==='w'?7:dim==='m'?30:365}
function hbCnt(h,dim){const days=hbDimDays(dim);
 if(h.type==='neg')return Math.round((h.triggers||0)*(dim==='w'?1:dim==='m'?4.3:52));
 const wk=h.w.filter(v=>v).length;
 const r=dim==='w'?wk/7:dim==='m'?Math.min(1,(h.mDone||0)/30):Math.max(.12,Math.min(1,wk/7-.06));
 return Math.round(days*r)}
function hbAvgPer(h){if(h.group){const rows=(h.sv||[]).filter(r=>r&&r.some(v=>+v));
   return rows.length?Math.round(rows.reduce((a,r)=>a+r.reduce((x,y)=>x+(+y||0),0),0)/rows.length):h.subs.reduce((a,s)=>a+(+s.goal||0),0)}
 if(h.unit){const a=(h.v||[]).filter(v=>+v);return a.length?Math.round(a.reduce((x,y)=>x+(+y||0),0)/a.length):(+h.goal||0)}
 return 0}
function hbSubAvg(h){if(!h.group)return [];const rows=(h.sv||[]).filter(r=>r&&r.some(v=>+v));
 return h.subs.map((s,k)=>rows.length?Math.round(rows.reduce((a,r)=>a+(+r[k]||0),0)/rows.length):(+s.goal||0))}
function hbSubTot(h,dim){if(!h.group)return [];const c=hbCnt(h,dim),a=hbSubAvg(h),days=hbDimDays(dim);
 return h.subs.map((s,k)=>({n:s.n,unit:s.unit,val:c*a[k],goal:(+s.goal||0)*days}))}
function hbTot(h,dim){const days=hbDimDays(dim),cnt=hbCnt(h,dim),per=hbAvgPer(h);
 return {cnt:cnt,dayN:days,val:cnt*per,avg:per,rate:Math.min(100,Math.round(cnt/days*100)),
   base:dim==='w'?'本周':dim==='m'?'本月':'本年',unit:h.group?'项次':(h.unit||'次')}}
function hbRecN(h,dim){if(h.group)return (h.sv||[]).filter(r=>r&&r.some(v=>+v)).length;
 return (h.v||[]).filter(v=>+v).length}`);

rep('yearbars', `function hbYearBars(h){const out=[];for(let m=0;m<12;m++){const seed=hbHash(h.id+'y'+m);const cnt=10+seed%20;out.push({mo:m+1,cnt:cnt,val:Math.round(cnt*hbUnitGoal(h)*(m<9?1:.35)),now:m<9})}return out}`,
`function hbYearBars(h){const per=hbAvgPer(h)||hbUnitGoal(h),r=Math.max(.12,Math.min(1,h.w.filter(v=>v).length/7-.06));const out=[];
 for(let m=0;m<12;m++){const cnt=Math.round(30*r)+hbHash(h.id+'y'+m)%4-2;out.push({mo:m+1,cnt:Math.max(0,cnt),val:Math.max(0,cnt)*per,now:m<9})}return out}`);

// ---- 工作台副标题：不再跨单位求和 ----
rep('hero', ` const wk=book.reduce((a,h)=>a+hbTot(h,'w').val,0);
 const hs=document.getElementById('hbHeroSub');if(hs)hs.textContent='已打卡 '+done+' / 应打卡 '+t.length+' · 本周记录量合计 '+wk+(book.some(h=>h.unit||h.group)?' 项次':'')+' · 负向剩余 '+book.filter(h=>h.type==='neg').reduce((a,h)=>a+hbNegLeft(h),0)+' 次';`,
` const rec=book.reduce((a,h)=>a+hbRecN(h,'w'),0),left=book.filter(h=>h.type==='neg').reduce((a,h)=>a+hbNegLeft(h),0);
 const hs=document.getElementById('hbHeroSub');if(hs)hs.textContent='已打卡 '+done+' / 应打卡 '+t.length+(rec?' · 本周已记数值 '+rec+' 条':'')+' · 负向剩余额度 '+left+' 次';`);

// ---- 组习惯卡片按钮文案压缩 ----
rep('short', `function hbTap(i){const h=HABITS[i];if(hbHasVal(h)){hbLogOpen(i);return}hbCheck(i)}`,
`function hbValShort(h,i){if(h.group){const r=(h.sv&&h.sv[i])||[];return h.subs.map((s,k)=>(r[k]||0)+s.unit).join(' / ')}
 const v=hbV(h,i);return v?v+' '+(h.unit||'次'):''}
function hbTap(i){const h=HABITS[i];if(hbHasVal(h)){hbLogOpen(i);return}hbCheck(i)}`);
rep('shortbtn', `'今日 '+hbValTxt(h,6)+' · 点击修改'`, `'今日 '+hbValShort(h,6)+' · 点击修改'`);

// ---- 统计页：卡片口径 + 负向按年折算 ----
rep('hscards', `if(cards)cards.innerHTML=[['打卡次数',cnt,'次'],['记录量合计',val,'项次'],['日均',Math.round(cnt/days),'次/天']].map`,
`if(cards)cards.innerHTML=[['打卡次数',cnt,'次'],['数值记录',recN,'条'],['日均打卡',(days?Math.round(cnt/days*10)/10:0),'次/天']].map`);
rep('hsvars', ` let cnt=0,val=0,days=dim==='w'?7:dim==='m'?30:365;
 book.forEach(h=>{const t=hbTot(h,dim);cnt+=t.cnt;val+=t.val});`,
` let cnt=0,val=0,recN=0,days=hbDimDays(dim);
 book.forEach(h=>{const t=hbTot(h,dim);cnt+=t.cnt;val+=t.val;recN+=hbRecN(h,dim)});`);
rep('hssub', `+' 个跟踪中习惯 · 打卡 '+cnt+' 次 · 记录量合计 '+val+' 项次 · 负向触发 '`,
 `+' 个跟踪中习惯 · 打卡 '+cnt+' 次 · 数值记录 '+recN+' 条 · 负向触发 '`);
rep('hsneg', "未做 ${(dim==='w'?h.w.filter(v=>v).length:Math.round((h.mAvoid||0)*4.3))} 天",
 "未做 ${(dim==='w'?h.w.filter(v=>v).length:dim==='m'?(h.mAvoid||0):(h.mAvoid||0)*12)} 天");

// ---- 详情页：标签口径 ----
rep('lbl', "${hbHasVal(h)?'总'+T.unit:'无记量'}", "${hbHasVal(h)?(h.group?'总记录量':'总'+T.unit):'未记量'}");
rep('lbl2', "${T.base} · 日均 ${T.avg}${T.unit}", "${T.base} · ${T.cnt} 次 · 每次均 ${T.avg}${T.unit}");

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK') } catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
