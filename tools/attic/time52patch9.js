/* V1.52 第二轮：周视图按小时重叠渲染+动态周 + 编辑弹层对半拆分/与上一下一个合并（仅已结束） + 轴视图去起止时间 + 日/周格显名与时长 */
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
const L = (arr) => arr.join('\n');

/* 1) 轴视图副行去掉起止时间（时间轴刻度即开始时间） */
rep('axis-sub',
  "const sub=b.dn?`✓ 已完成 · ${fmt(b.s)} – ${fmt(bend(b))} · 实际 ${bend(b)-b.s} 分钟 · 已回填 L1 · 入时间账本 L4 · 点卡片仍可修改/删除`:`${b.cat} · ${fmt(b.s)} – ${fmt(bend(b))} · ${bend(b)-b.s} 分钟 · 点卡片修改起止/类型`;",
  "const sub=b.dn?`✓ 已完成 · ${b.cat} · 实际 ${bend(b)-b.s} 分钟 · 已回填 L1 · 入时间账本 L4 · 点卡片仍可修改/删除`:`${b.cat} · ${bend(b)-b.s} 分钟 · 点卡片修改起止/类型`;");

/* 2) 日视图小时行：块 chips 加时长 */
rep('day-chip',
  'class="mb-1 rounded-lg ${b.tm?\'bg-rose-500 animate-pulse\':(b.dn?\'bg-emerald-400/90\':blkColor(b))} text-white text-[10px] font-bold px-2 py-1.5 cursor-pointer">${fmt(b.s)} ${b.note||b.cat} ${lbl} ›</div>',
  'class="mb-1 rounded-lg ${b.tm?\'bg-rose-500 animate-pulse\':(b.dn?\'bg-emerald-400/90\':blkColor(b))} text-white text-[10px] font-bold px-2 py-1.5 cursor-pointer flex items-center gap-2"><span class="flex-1 min-w-0 truncate">${fmt(b.s)} ${b.note||b.cat} ${lbl}</span><span class="shrink-0 opacity-80">${bend(b)-b.s}分</span></div>');

/* 3) 周视图：动态取 calDay 所在周 + 按小时重叠分段 + 格内显名称与时长 */
rep('week-head',
  "function renderWeekGrid(){const el=$('#calWeekGrid');if(!el)return;\n  const days=[13,14,15,16,17,18,19];",
  "function renderWeekGrid(){const el=$('#calWeekGrid');if(!el)return;\n  const wkStart=calDay-((calDay+1)%7),days=[];for(let k=0;k<7;k++){const d=wkStart+k;if(d>=1&&d<=30)days.push(d)}");
rep('week-title',
  "  let h='<div class=\"text-[10px] text-slate-400 mb-1\">🗓 9/13 - 9/19 · 空格子 → 添加时间段 · 已添加 → 点进去查看/编辑</div>';",
  "  let h='<div class=\"text-[10px] text-slate-400 mb-1\">🗓 9/'+days[0]+' - 9/'+days[days.length-1]+' · 空格子 → 添加时间段 · 已添加 → 点进去修改/拆分/合并</div>';");
rep('week-body', L([
  "  for(let hr=0;hr<24;hr++){h+=`<span class=\"text-slate-400 text-right text-[8px] font-mono pr-0.5 pt-0.5\">${hr}</span>`;",
  "   for(const d of days){const m=hr*60;const bs=blocksAt(m,d);",
  "    if(!bs.length){h+=`<div class=\"wk-cell bg-slate-100 dark:bg-slate-800\" title=\"9月${d}日 ${hr}:00 空\" onclick=\"openTimePick(${d},${hr},0)\"></div>`;continue}",
  "    h+='<div class=\"wk-cell flex bg-slate-100 dark:bg-slate-800 gap-px items-stretch\">'+weekCellSegments(bs).map(s=>{",
  "     const b=s.b;",
  "     const cls=b.dn?'bg-emerald-400':(b.tm?'animate-pulse ':'')+CATS[b.cat];",
  "     const act=`openBlockEdit(blocks[${blocks.indexOf(b)}])`;",
  "     const ti=(b.note||b.cat)+' '+fmt(b.s)+'-'+fmt(b.e);",
  "     return `<div class=\"flex-1 min-w-0 rounded-[4px] relative ${cls}\" title=\"${ti}\" onclick=\"event.stopPropagation();${act}\">${s.n>1?`<span class=\"absolute inset-0 flex items-center justify-center text-white text-[8px] font-extrabold leading-none\">+${s.n}</span>`:''}</div>`}).join('')+'</div>'}}",
]), L([
  "  for(let hr=0;hr<24;hr++){h+=`<span class=\"text-slate-400 text-right text-[8px] font-mono pr-0.5 pt-0.5\">${hr}</span>`;",
  "   for(const d of days){const m=hr*60;const bs=blocksHour(d,m,m+60);",
  "    if(!bs.length){h+=`<div class=\"wk-cell bg-slate-100 dark:bg-slate-800\" title=\"9月${d}日 ${hr}:00 空\" onclick=\"openTimePick(${d},${hr},0)\"></div>`;continue}",
  "    h+='<div class=\"wk-cell flex bg-slate-100 dark:bg-slate-800 gap-px items-stretch\">'+weekCellSegments(bs).map(s=>{",
  "     const b=s.b;",
  "     const cls=b.dn?'bg-emerald-400':(b.tm?'bg-rose-500 animate-pulse ':'')+CATS[b.cat];",
  "     const act=`openBlockEdit(blocks[${blocks.indexOf(b)}])`;",
  "     const ti=(b.note||b.cat)+' '+fmt(b.s)+'-'+fmt(bend(b))+(b.tm?' · 计时中':'');",
  "     const inHour=Math.min(bend(b),m+60)-Math.max(b.s,m);",
  "     return `<div class=\"min-w-0 rounded-[4px] relative overflow-hidden ${cls}\" style=\"flex:${Math.max(1,Math.round(inHour/6))}\" title=\"${ti}\" onclick=\"event.stopPropagation();${act}\">${s.n>1?`<span class=\"absolute inset-0 flex items-center justify-center text-white text-[8px] font-extrabold leading-none\">+${s.n}</span>`:`<span class=\"absolute left-0.5 top-0.5 text-white text-[7px] font-bold leading-none truncate max-w-[calc(100%-3px)]\">${b.note||b.cat}</span><span class=\"absolute left-0.5 bottom-0.5 text-white/85 text-[7px] leading-none\">${bend(b)-b.s}分</span>`}</div>`}).join('')+'</div>'}}",
]));

/* 4) 小时重叠取块 */
rep('blocksHour',
  "function blocksAt(m,d){return dayBlocks(d===undefined?TODAY:d).filter(b=>m>=b.s&&m<bend(b));}",
  "function blocksAt(m,d){return dayBlocks(d===undefined?TODAY:d).filter(b=>m>=b.s&&m<bend(b));}\nfunction blocksHour(d,a,b){return dayBlocks(d).filter(x=>x.s<b&&bend(x)>a).sort((x,y)=>x.s-y.s)}");

/* 5) 编辑弹层：对半拆分 / 与上一个合并 / 与下一个合并（仅已结束块显示） */
rep('sm-html',
  '      <div id="tpFoot" class="mt-2 flex gap-3"></div>',
  '      <div id="tpSM" class="mt-2 hidden gap-2"></div>\n      <div id="tpFoot" class="mt-2 flex gap-3"></div>');
rep('sm-fns',
  "function openBlockEdit(b){openTimePick(b.day||TODAY,b.s,b.e,b)}",
  L([
  "function openBlockEdit(b){openTimePick(b.day||TODAY,b.s,b.e,b)}",
  "function nbOf(b,d){const list=dayBlocks(b.day||TODAY).filter(x=>x!==b&&!x.tm);return d<0?list.filter(x=>x.e<=b.s).sort((p,q)=>q.s-p.s)[0]:list.filter(x=>x.s>=bend(b)).sort((p,q)=>p.s-q.s)[0]}",
  "function tpSplit(){const b=tpEdit;if(!b||b.tm)return;const mid=Math.floor((b.s+bend(b))/2);if(mid<=b.s||mid>=bend(b)){toast('✕ 时长不足 2 分钟 · 无法对半拆分');return}",
  " const nb=Object.assign({},b,{s:mid,e:bend(b)});b.e=mid;blocks.push(nb);tpEdit=null;closeSheet('sheetTimePick');renderCal();",
  " toast('✂ 已对半拆分为两段 · '+fmt(b.s)+'-'+fmt(mid)+' / '+fmt(mid)+'-'+fmt(b.e)+' · 四视图与账本同步')}",
  "function tpMerge(d){const b=tpEdit;if(!b||b.tm)return;const o=nbOf(b,d);if(!o){toast(d<0?'✕ 上方没有可合并的已结束事件':'✕ 下方没有可合并的已结束事件');return}",
  " const a=d<0?o:b,c=d<0?b:o;const keep=blocks.indexOf(a)>-1?a:c;const gone=keep===a?c:a;",
  " keep.s=Math.min(a.s,c.s);keep.e=Math.max(bend(a),bend(c));keep.note=keep.note||keep.cat;keep.dn=0;",
  " blocks=blocks.filter(x=>x!==gone);tpEdit=null;closeSheet('sheetTimePick');renderCal();",
  " toast('⇄ 已合并为 '+fmt(keep.s)+'-'+fmt(keep.e)+' · '+(keep.note||keep.cat)+' · 另一段已并入（四视图与账本同步）')}",
  ]));
rep('sm-foot',
  " const h=$('#tpHintEl');if(h)h.textContent=tpEdit?(tpTiming?'■ 结束计时':'✎ 编辑中 · 修改即保存'):(tpTiming?'● 计时中 · 下次点击可结束':'＋ 添加')}",
  L([
  " const h=$('#tpHintEl');if(h)h.textContent=tpEdit?(tpTiming?'■ 结束计时':'✎ 编辑中 · 修改即保存'):(tpTiming?'● 计时中 · 下次点击可结束':'＋ 添加');",
  " const sm=$('#tpSM');if(sm){const can=tpEdit&&!tpTiming;sm.classList.toggle('hidden',!can);",
  "  if(can){const pv=nbOf(tpEdit,-1),nx=nbOf(tpEdit,1);",
  "   sm.classList.add('flex');sm.innerHTML=`<button onclick=\"tpSplit()\" class=\"flex-1 py-2.5 rounded-xl border border-slate-300 dark:border-slate-700 text-[11px] font-bold\">✂ 对半拆分</button>`",
  "    +`<button onclick=\"tpMerge(-1)\" class=\"flex-1 py-2.5 rounded-xl border text-[11px] font-bold ${pv?'border-slate-300 dark:border-slate-700':'border-slate-200 dark:border-slate-800 text-slate-300 dark:text-slate-600'}\">⇧ 与上一个合并</button>`",
  "    +`<button onclick=\"tpMerge(1)\" class=\"flex-1 py-2.5 rounded-xl border text-[11px] font-bold ${nx?'border-slate-300 dark:border-slate-700':'border-slate-200 dark:border-slate-800 text-slate-300 dark:text-slate-600'}\">⇩ 与下一个合并</button>`}else sm.classList.remove('flex')}}",
  ]));

fs.writeFileSync(P, s);
console.log('OK ' + R.length + ': ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
