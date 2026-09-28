/* 轮6-B：liveEv 残留清理 · 计时轻量刷新 · 轴视图空隙可点 · 跨天尾巴 · 合并间隙阈值 · 撤销 */
const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const R = [];
function rep(name, a, b) {
  const n = s.split(a).length - 1;
  if (n !== 1) { console.error('MISS/DUP ' + name + ' count=' + n); process.exit(1); }
  s = s.split(a).join(b); R.push(name);
}
const L = a => a.join('\n');

/* ① boot 里 liveEv 秒级刷新 → 计时中块的时长文本刷新（不整页重绘） */
rep('live-interval',
  "if(liveEv&&timerSecsOK()){const now=new Date();const nm=now.getHours()*60+now.getMinutes();const el=$('#liveDur');if(el)el.textContent=Math.max(0,nm-liveEv.s)+' 分钟'}},1000);",
  "if(timingBlk()&&timerSecsOK()){document.querySelectorAll('.tmDur').forEach(function(el){el.textContent=Math.max(0,nowMin()-(+el.dataset.s))+' 分钟'})}},1000);");
rep('live-tick',
  " if(timingBlk()&&document.querySelector('#p-calendar:not(.hidden)')&&!document.querySelector('.sheet.sheet-open'))renderCal(); }",
  " }");
rep('tm-span',
  "● 计时中 · ${fmt(b.s)} 开始 · 已 <b>${Math.max(0,nowMin()-b.s)}</b> 分钟",
  "● 计时中 · ${fmt(b.s)} 开始 · 已 <b class=\"tmDur\" data-s=\"${b.s}\">${Math.max(0,nowMin()-b.s)}</b> 分钟");

/* ② toast 支持撤销按钮 */
rep('toast',
  "function toast(msg){ const t=$('#toast'); t.textContent=msg; t.classList.remove('hidden'); clearTimeout(toastTimer); toastTimer=setTimeout(()=>t.classList.add('hidden'),2200); }",
  L([
  "function toast(msg,act){ const t=$('#toast'); t.innerHTML=''; const sp=document.createElement('span'); sp.textContent=msg; t.appendChild(sp);",
  " if(act){const b=document.createElement('button'); b.textContent=act+' · 撤销'; b.className='ml-3 text-white/95 font-extrabold underline'; b.onclick=()=>{undoAct();t.classList.add('hidden')}; t.appendChild(b)}",
  " t.classList.remove('hidden'); clearTimeout(toastTimer); toastTimer=setTimeout(()=>t.classList.add('hidden'),2800); }",
  "let undoStack=[];",
  "function snap(msg){undoStack.push({t:JSON.stringify(blocks),msg:msg});if(undoStack.length>20)undoStack.shift()}",
  "function undoAct(){const u=undoStack.pop();if(!u){toast('没有可撤销的操作');return}blocks=JSON.parse(u.t);tpEdit=null;closeSheet('sheetTimePick');renderCal();toast('↩ 已撤销：'+u.msg)}",
  ]));

/* ③ 删除/拆分/合并前快照 + toast 带撤销 */
rep('del-undo',
  "blocks=blocks.filter(x=>x!==tpEdit);tpEdit=null;closeSheet('sheetTimePick');renderCal();toast('🗑 已删除 · 轴/块/日/周四视图与时间账本同步移除')}",
  "snap('删除「'+(tpEdit.note||tpEdit.cat)+'」');blocks=blocks.filter(x=>x!==tpEdit);tpEdit=null;closeSheet('sheetTimePick');renderCal();toast('🗑 已删除 · 四视图与账本同步移除','↩')");
rep('split-undo',
  " const nb=Object.assign({},b,{s:mid,e:bend(b)});b.e=mid;blocks.push(nb);tpEdit=null;closeSheet('sheetTimePick');renderCal();",
  " snap('对半拆分');const nb=Object.assign({},b,{s:mid,e:bend(b)});b.e=mid;blocks.push(nb);tpEdit=null;closeSheet('sheetTimePick');renderCal();");
rep('split-toast',
  " toast('✂ 已对半拆分为两段 · '+fmt(b.s)+'-'+fmt(mid)+' / '+fmt(mid)+'-'+fmt(b.e)+' · 四视图与账本同步')}",
  " toast('✂ 已对半拆分为两段 · '+fmt(b.s)+'-'+fmt(mid)+' / '+fmt(mid)+'-'+fmt(b.e),'↩')}");
rep('merge-undo',
  " blocks=blocks.filter(x=>x!==gone);tpEdit=null;closeSheet('sheetTimePick');renderCal();",
  " snap('合并两段');blocks=blocks.filter(x=>x!==gone);tpEdit=null;closeSheet('sheetTimePick');renderCal();");
rep('merge-toast',
  " toast('⇄ 已合并为 '+fmt(keep.s)+'-'+fmt(keep.e)+' · '+(keep.note||keep.cat)+' · 另一段已并入（四视图与账本同步）')}",
  " toast('⇄ 已合并为 '+fmt(keep.s)+'-'+fmt(keep.e)+' · '+(keep.note||keep.cat),'↩')}");

/* ④ 合并间隙阈值 30 分钟 */
rep('nbof',
  "function nbOf(b,d){const list=dayBlocks(b.day||TODAY).filter(x=>x!==b&&!x.tm);return d<0?list.filter(x=>x.e<=b.s).sort((p,q)=>q.s-p.s)[0]:list.filter(x=>x.s>=bend(b)).sort((p,q)=>p.s-q.s)[0]}",
  "const MERGE_GAP=30;\nfunction nbOf(b,d){const list=dayBlocks(b.day||TODAY).filter(x=>x!==b&&!x.tm);\n return d<0?list.filter(x=>x.e<=b.s&&(b.s-x.e)<=MERGE_GAP).sort((p,q)=>q.s-p.s)[0]:list.filter(x=>x.s>=bend(b)&&(x.s-bend(b))<=MERGE_GAP).sort((p,q)=>p.s-q.s)[0]}");

/* ⑤ 跨天尾巴：dayBlocks 含前一日溢出段 */
rep('dayblocks',
  "function dayBlocks(d){return blocks.filter(b=>(b.day||TODAY)===d).map(normB)}",
  L([
  "function dayBlocks(d){const out=[];blocks.forEach(b=>{const bd=b.day||TODAY;",
  "  if(bd===d)out.push(normB(b));",
  "  else if(bd===d-1&&b.e>1439)out.push(Object.assign({},b,{s:0,e:b.e-1440,day:d,tailOf:b}));});",
  "  return out}/* 段身份用 srcOf(b) 取回原块 */",
  "function srcOf(b){return b.tailOf||b}",
  ]));
s = s.split("blocks.indexOf(b)").join("blocks.indexOf(srcOf(b))");
R.push('indexOf-srcOf');

/* ⑥ 轴视图空隙可点（每段 ≥15 分钟的空档都出补录条） */
rep('gap-fn',
  "function blkColor(b){return b.c||(CATS[b.cat]||'bg-slate-400')}",
  L([
  "function blkColor(b){return b.c||(CATS[b.cat]||'bg-slate-400')}",
  "function gapHtml(a,b){const e=Math.min(1439,b);if(e-a<15)return '';",
  " return `<div class=\"relative cursor-pointer mb-3\" onclick=\"openTimePick(calDay,${Math.floor(a/60)},${a%60})\"><span class=\"absolute -left-14 w-12 text-right text-[10px] font-mono text-slate-300\">${fmt(a)}</span><div class=\"text-[11px] text-slate-300 dark:text-slate-600 py-3 text-center border-2 border-dashed border-slate-200 dark:border-slate-800 rounded-2xl\">空闲 ${fmt(a)} – ${fmt(e)} · 点此补录</div></div>`}",
  ]));
rep('gap-emit',
  " h+=list.map(b=>{const id=blocks.indexOf(srcOf(b));",
  " let prevEnd=0;\n h+=list.map(b=>{const id=blocks.indexOf(srcOf(b));let gap='';\n  if(b.s-prevEnd>=15)gap=gapHtml(prevEnd,b.s);\n  prevEnd=Math.max(prevEnd,bend(b));");
rep('gap-card',
  "  return `<div class=\"relative mb-4\">\n    <span class=\"absolute -left-14 top-0 w-12 text-right text-[10px] font-mono text-slate-400\">${fmt(b.s)}</span>",
  "  return gap+`<div class=\"relative mb-4\">\n    <span class=\"absolute -left-14 top-0 w-12 text-right text-[10px] font-mono text-slate-400\">${fmt(b.s)}</span>");
rep('gap-tail',
  " h+=`<div class=\"relative cursor-pointer\" onclick=\"openTimePick(calDay,17,0)\"><span class=\"absolute -left-14 w-12 text-right text-[10px] font-mono text-slate-400\">17:00</span><div class=\"text-xs text-slate-300 dark:text-slate-600 py-6 text-center border-2 border-dashed border-slate-200 dark:border-slate-800 rounded-2xl\">空闲 · 点此补录该时段日程</div></div>`}",
  " h+=gapHtml(prevEnd,1439)}");
/* 计时中卡片也参与空隙推进 */
rep('gap-tm',
  "  if(b.tm)return `<div class=\"relative mb-4\">",
  "  if(b.tm){prevEnd=Math.max(prevEnd,bend(b));return `<div class=\"relative mb-4\">");
rep('gap-tm-end',
  "onclick=\"event.stopPropagation();tpEdit=blocks[${id}];tpTiming=true;tpEnd()\">■ 结束计时</button></div></div>`;",
  "onclick=\"event.stopPropagation();tpEdit=blocks[${id}];tpTiming=true;tpEnd()\">■ 结束计时</button></div></div>`}");

/* ⑦ 跨天段标注 */
rep('tail-tag',
  "      <div class=\"text-sm font-bold ${b.dn?'line-through decoration-slate-300':''}\">${b.note||b.cat}</div>",
  "      <div class=\"text-sm font-bold ${b.dn?'line-through decoration-slate-300':''}\">${b.tailOf?'（续昨日）':''}${b.note||b.cat}</div>");

/* ⑧ openTimePick 显式传分钟时按精确分钟起算 */
rep('s0-precise',
  "  let s0=bl?bl.s:(sd===TODAY&&isNow?nowMin():((h||0)*60));",
  "  let s0=bl?bl.s:(sd===TODAY&&isNow?nowMin():((h||0)*60+(m||0)));");

/* ⑨ 选区直标只作用于当前日（原实现会切到其他日的同名时段） */
rep('markrange-day',
  "  const keep=[];blocks.forEach(b=>{\n    if(b.tm||b.e<=st||b.s>=en){keep.push(b);return}",
  "  const keep=[];blocks.forEach(b=>{\n    if((b.day||TODAY)!==calDay||b.tm||b.e<=st||b.s>=en){keep.push(b);return}");
rep('markrange-push',
  "  keep.push({day:calDay,s:st,e:en,cat:cat,note:cat});\n  keep.sort((x,y)=>x.s-y.s);",
  "  keep.push({day:calDay,s:st,e:en,cat:cat,note:cat});\n  keep.sort((x,y)=>(x.day-y.day)||(x.s-y.s));");

fs.writeFileSync(P, s);
console.log('OK ' + R.length + ': ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
