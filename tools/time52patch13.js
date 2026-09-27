/* V1.52 第五轮排查修复：月历圆点实算 · 轴视图补录行传小时 · 跨天事件 · 周视图跨月塌列 */
const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const R = [];
function rep(name, a, b, cnt) {
  const n = s.split(a).length - 1;
  if (n !== (cnt || 1)) { console.error('MISS/DUP ' + name + ' count=' + n); process.exit(1); }
  s = s.split(a).join(b);
  R.push(name);
}
const L = a => a.join('\n');

/* ① 月历圆点由 blocks 实算（不再用写死 DAY_STATUS） */
rep('dots', L([
  "const DAY_STATUS={3:'done',9:'done',15:'done',22:'done',28:'plan',19:'plan'}; /* 圆点状态：done绿/plan蓝/live红脉冲 */",
  "function dayHasEv(d){return !!DAY_STATUS[d]||(liveEv&&d===19)||(d===19&&D.events.length>0)}",
  "function dotCls(d){if(liveEv&&d===19)return 'bg-rose-400 animate-pulse';return DAY_STATUS[d]==='done'?'bg-emerald-400':'bg-brand-400'}",
]), L([
  "/* V1.52：月历圆点随 blocks 实算（进行中>已完成>计划中 优先级）· 与轴/块/日/周同一数据 */",
  "function dayStatus(d){const bs=dayBlocks(d);if(!bs.length)return null;",
  " if(bs.some(b=>b.tm)||(d===TODAY&&liveEv))return 'live';",
  " return bs.every(b=>b.dn)?'done':'plan'}",
  "function dayHasEv(d){return !!dayStatus(d)}",
  "function dotCls(d){const st=dayStatus(d);return st==='live'?'bg-rose-400 animate-pulse':st==='done'?'bg-emerald-400':'bg-brand-400'}",
]));

/* ② 轴视图「空闲·点此补录该时段」按该行小时打开 */
rep('axis-empty', 'onclick="openTimePick(calDay)"><span class="absolute -left-14 w-12',
  'onclick="openTimePick(calDay,17,0)"><span class="absolute -left-14 w-12');

/* ③ 跨天事件：结束日滚轮真正参与计算 */
rep('tpEd-abs',
  "function tpEd(){return tpMin('tpEh')*60+tpMin('tpEm')}",
  "function tpEd(){const sd=+WHEELS.tpSd.items[WHEELS.tpSd.i].slice(3),ed=+WHEELS.tpEd.items[WHEELS.tpEd.i].slice(3);return (ed-sd)*1440+tpMin('tpEh')*60+tpMin('tpEm')}");
rep('tpUpd', L([
  "function tpUpd(){const s=tpMin('tpSh')*60+tpMin('tpSm'),e=tpEd();",
  "  $('#tpRange').textContent=WHEELS.tpSd.items[WHEELS.tpSd.i]+' '+String(tpMin('tpSh')).padStart(2,'0')+':'+String(tpMin('tpSm')).padStart(2,'0')+' → '+WHEELS.tpEd.items[WHEELS.tpEd.i]+' '+String(Math.floor(e/60)%24).padStart(2,'0')+':'+String(e%60).padStart(2,'0')+' · '+(e<s?e+1440-s:e-s)+' 分钟'+(e<s?' · 跨天':'');",
]), L([
  "function tpUpd(){const s=tpMin('tpSh')*60+tpMin('tpSm'),e=tpEd();",
  "  const sdW=WHEELS.tpSd.items[WHEELS.tpSd.i],edW=WHEELS.tpEd.items[WHEELS.tpEd.i],cross=sdW!==edW;",
  "  $('#tpRange').textContent=sdW+' '+String(tpMin('tpSh')).padStart(2,'0')+':'+String(tpMin('tpSm')).padStart(2,'0')+' → '+(cross?edW+' ':'')+String(Math.floor(e/60)%24).padStart(2,'0')+':'+String(e%60).padStart(2,'0')+' · '+(e>=s?e-s:e+1440-s)+' 分钟'+(cross?' · 跨天':'');",
]));
rep('open-wreg',
  "  wReg('tpEd',TP_DAYS,di,tpUpd);wReg('tpEh',TP_HRS,Math.floor(e0/60),tpUpd);wReg('tpEm',TP_MINS,e0%60,tpUpd);",
  "  const eOff=bl?Math.floor(Math.max(0,e0)/1440):0;\n  wReg('tpEd',TP_DAYS,Math.min(29,di+eOff),tpUpd);wReg('tpEh',TP_HRS,Math.floor(e0%1440/60),tpUpd);wReg('tpEm',TP_MINS,e0%1440%60,tpUpd);");
rep('add-store',
  " const blk={day:sd,s:s,e:Math.min(1439,e),cat:tpSel.cat,note:$('#tpNote').value.trim()||(name+(tpSel.sub?' · '+tpSel.cat:''))};",
  " const blk={day:sd,s:s,e:e,cat:tpSel.cat,note:$('#tpNote').value.trim()||(name+(tpSel.sub?' · '+tpSel.cat:''))};");
rep('add-toast',
  " if(keep){$('#tpNote').value='';toast('✔ 已添加 '+fmt(s)+'-'+fmt(Math.min(1439,e))+' · '+name+'（9月'+sd+'日）')}",
  " if(keep){$('#tpNote').value='';toast('✔ 已添加 '+fmt(s)+'-'+fmt(e)+(e>=1440?'（次日）':'')+' · '+name+'（9月'+sd+'日）')}");
rep('add-clamp',
  " if(e<=s)e=isNow?s:Math.min(s+60,1439);",
  " if(e<=s)e=isNow?s:s+60;");

/* ④ 周视图固定 7 列 · 跨月日期显示为惰性列 */
rep('week-days',
  "  const wkStart=calDay-((calDay+1)%7),days=[];for(let k=0;k<7;k++){const d=wkStart+k;if(d>=1&&d<=30)days.push(d)}",
  "  const wkStart=calDay-((calDay+1)%7),days=[];for(let k=0;k<7;k++)days.push(wkStart+k);\n  const inR=days.filter(d=>d>=1&&d<=30);");
rep('week-title',
  "  let h='<div class=\"text-[10px] text-slate-400 mb-1\">🗓 9/'+days[0]+' - 9/'+days[days.length-1]+' · 空格子 → 添加时间段 · 已添加 → 点进去修改/拆分/合并</div>';",
  "  let h='<div class=\"text-[10px] text-slate-400 mb-1\">🗓 9/'+inR[0]+' - 9/'+inR[inR.length-1]+' · 空格子 → 添加时间段 · 已添加 → 点进去修改/拆分/合并</div>';");
rep('week-head',
  "  h+='<span></span>'+days.map(d=>`<span class=\"text-center text-[9px] ${d===19?'text-brand-500 font-extrabold':'text-slate-400'}\">${d===19?'今':WDS[(d+1)%7]}</span>`).join('');",
  "  h+='<span></span>'+days.map(d=>{const inM=d>=1&&d<=30,lb=inM?(d===TODAY?'今':WDS[(d+1)%7]):(d<1?'8/'+(31+d):'10/'+(d-30));\n   return `<span class=\"text-center text-[9px] ${d===TODAY?'text-brand-500 font-extrabold':(inM?'text-slate-400':'text-slate-300 dark:text-slate-700')}\">${lb}</span>`}).join('');");
rep('week-cell',
  "   for(const d of days){const m=hr*60;const bs=blocksHour(d,m,m+60);\n    if(!bs.length){",
  "   for(const d of days){const m=hr*60;const inM=d>=1&&d<=30;const bs=inM?blocksHour(d,m,m+60):[];\n    if(!inM){h+='<div class=\"wk-cell bg-slate-50 dark:bg-slate-900/40\"></div>';continue}\n    if(!bs.length){");

fs.writeFileSync(P, s);
console.log('OK ' + R.length + ': ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
