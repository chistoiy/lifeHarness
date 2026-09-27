/* V1.52 时间模块原型补丁：三视图点已有事件→统一编辑弹层 + 今天计时语义 + blocks 带日字段 */
const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const EOL = s.indexOf('\r\n') >= 0 ? '\r\n' : '\n';
const fix = (x) => x; /* 统一在 LF 态匹配，写回时整文件转回原行尾 */
s = s.replace(/\r\n/g, '\n');
const size0 = s.length;
const R = [];
function rep(name, a, b) {
  a = fix(a); b = fix(b);
  const i = s.indexOf(a);
  if (i < 0) { console.error('MISS ' + name); process.exit(1); }
  if (s.indexOf(a, i + 1) >= 0) { console.error('DUP ' + name); process.exit(1); }
  s = s.slice(0, i) + b + s.slice(i + a.length);
  R.push(name);
}
function repBlock(name, startLine, endLine, replacement) {
  startLine = fix(startLine); endLine = fix(endLine); replacement = fix(replacement);
  const i = s.indexOf(startLine);
  if (i < 0) { console.error('MISS-B ' + name); process.exit(1); }
  const j = s.indexOf(endLine, i);
  if (j < 0) { console.error('MISS-END ' + name); process.exit(1); }
  const tail = s.indexOf('\n', j) + 1;
  s = s.slice(0, i) + replacement + s.slice(tail);
  R.push(name);
}
const L = (arr) => arr.join('\n');

/* A) 数据模型 + 统一编辑/添加核心函数 */
rep('A-model', L([
  "/* 事件↔时间块同步：D.events(计划⚡)/endedEvs(完成✓) 投影为块，与手动标记同一数据 */",
  "function evBlocks(){return D.events.map((e,i)=>({s:hm2min(e.tm),e:hm2min(e.e),cat:'工作',note:e.t,ev:i}))}",
  "function doneBlocks(){return endedEvs.map((e,i)=>({s:hm2min(e.tm),e:hm2min(e.e),cat:'工作',note:e.t,done:i}))}",
  "function allBlocks(){return blocks.concat(evBlocks(),doneBlocks())}",
  "function blockAt(m){return allBlocks().find(b=>m>=b.s&&m<b.e);}",
]), L([
  "/* V1.52：事件/时间块统一为 blocks 单一数据（day=所在日 · tm=计时中 · dn=已完成）· 轴/块/日/周四视图同一投影 */",
  "const TODAY=19;",
  "const nowMin=()=>{const d=new Date();return d.getHours()*60+d.getMinutes()};",
  "function normB(b){if(b.tm&&b.day===TODAY)b.e=Math.max(b.s,nowMin());return b}",
  "function dayBlocks(d){return blocks.filter(b=>(b.day||TODAY)===d).map(normB)}",
  "function timingBlk(){return blocks.find(b=>b.tm&&b.day===TODAY)||null}",
  "function closeTimingAt(t){const b=timingBlk();if(!b)return null;b.tm=0;b.e=Math.max(b.s,t);return b}",
  "function blockAt(m){return dayBlocks(calDay).find(b=>m>=b.s&&m<b.e)}",
  "function blkColor(b){return b.c||(CATS[b.cat]||'bg-slate-400')}",
  "function migrateEv152(){D.events.forEach(e=>blocks.push({day:TODAY,s:hm2min(e.tm),e:hm2min(e.e),cat:'工作',note:e.t,c:e.c}));",
  " endedEvs.forEach(e=>blocks.push({day:TODAY,s:hm2min(e.tm),e:hm2min(e.e),cat:'工作',note:e.t,dn:1}));",
  " blocks.push({day:28,s:570,e:585,cat:'娱乐',note:'娱乐'});D.events=[];endedEvs=[]}",
  "/* —— 统一添加/编辑弹层核心（V1.52 · 点已有事件与添加同款弹层预填 · 今天支持计时中） —— */",
  "let tpEdit=null,tpTiming=false;",
  "function tpSetWheel(id,i){const w=WHEELS[id];w.i=Math.max(0,Math.min(w.items.length-1,i));renderW(id)}",
  "function tpFoot(){const t=$('#tpFoot');if(!t)return;",
  " t.innerHTML=(tpEdit?`<button onclick=\"tpDel()\" class=\"px-5 py-3 rounded-xl border border-rose-300 text-rose-500 text-sm font-bold\">删除</button>`:`<button onclick=\"tpAdd(1)\" class=\"flex-1 py-3 rounded-xl border border-slate-300 dark:border-slate-700 text-sm font-bold\">继续添加</button>`)",
  "  +(tpTiming?`<button onclick=\"tpEnd()\" class=\"flex-1 py-3 rounded-xl bg-rose-500 text-white text-sm font-extrabold\">■ 结束计时</button>`:'')",
  "  +`<button onclick=\"${tpEdit?'tpSave()':'tpAdd(0)'}\" class=\"flex-1 py-3 rounded-xl grad text-white text-sm font-bold\">${tpEdit?'保存修改':'添加'}</button>`;",
  " const h=$('#tpHintEl');if(h)h.textContent=tpEdit?(tpTiming?'■ 结束计时':'✎ 编辑中 · 修改即保存'):(tpTiming?'● 计时中 · 下次点击可结束':'＋ 添加')}",
  "function openBlockEdit(b){openTimePick(b.day||TODAY,b.s,b.e,b)}",
  "function tpEnd(){if(!tpEdit||!tpEdit.tm)return;const n=nowMin();tpEdit.tm=0;tpEdit.e=Math.max(tpEdit.s,n);closeSheet('sheetTimePick');renderCal();toast('■ 结束计时 · 结束 '+fmt(n)+' · 耗时 '+(n-tpEdit.s)+' 分钟 · 已落账（L4）')}",
  "function tpDel(){if(!tpEdit)return;blocks=blocks.filter(x=>x!==tpEdit);tpEdit=null;closeSheet('sheetTimePick');renderCal();toast('🗑 已删除 · 轴/块/日/周四视图与时间账本同步移除')}",
  "function tpSave(){if(!tpEdit)return;const b=tpEdit,s=tpMin('tpSh')*60+tpMin('tpSm');let e=tpEd();",
  " if(e<=s)e=s+5;",
  " if(b.tm&&e!==nowMin())b.tm=0;",
  " b.day=+WHEELS.tpSd.items[WHEELS.tpSd.i].slice(3);b.s=s;b.e=e;b.cat=tpSel.cat;b.note=$('#tpNote').value.trim()||b.cat;tpEdit=null;",
  " closeSheet('sheetTimePick');renderCal();toast('✔ 已保存 · 轴/块/日/周四视图与时间账本同步（L4）')}",
  "function tpAdd(keep){const sd=+WHEELS.tpSd.items[WHEELS.tpSd.i].slice(3);",
  " let s=tpMin('tpSh')*60+tpMin('tpSm');let e=tpEd();const isNow=sd===TODAY&&s===nowMin();",
  " if(e<=s)e=isNow?s:Math.min(s+60,1439);",
  " const tb=timingBlk();",
  " if(tb&&s>=tb.s){if(sd===TODAY&&e<tb.s){toast('✕ 新事件开始不能早于计时中事件（否则将不再自动结束它）');return}",
  "  const cut=Math.min(isNow?e:s,nowMin());closeTimingAt(Math.max(tb.s,cut))}",
  " else if(tb&&sd===TODAY&&e>tb.s){toast('✕ 补录事件的结束不能晚于计时中事件的开始（'+fmt(tb.s)+'）· 请调整');return}",
  " const name=tpSel.sub||tpSel.cat;",
  " const blk={day:sd,s:s,e:Math.min(1439,e),cat:tpSel.cat,note:$('#tpNote').value.trim()||(name+(tpSel.sub?' · '+tpSel.cat:''))};",
  " if(isNow&&e<=s){blk.tm=1;blk.e=s}",
  " blocks.push(blk);renderCal();",
  " if(isNow&&blk.tm){toast('▶ 已按当前时间开始计时 · 下次点击该事件可「■ 结束计时」');closeSheet('sheetTimePick');return}",
  " const cross=sd!==TODAY?' · 已补录到 9月'+sd+'日':'';",
  " if(keep){$('#tpNote').value='';toast('✔ 已添加 '+fmt(s)+'-'+fmt(Math.min(1439,e))+' · '+name+'（9月'+sd+'日）')}",
  " else{closeSheet('sheetTimePick');toast('✔ 已添加 · 轴/块/日/周四视图与时间账本同步（L4）'+cross)}}",
]));

/* B) 弹层 HTML：标题 id + 底部按钮容器 */
rep('B-title',
  '      <div class="flex items-center"><div class="font-extrabold flex-1">添加事件 / 时间块</div><span id="tpRange" class="text-[10px] text-slate-400"></span></div>',
  '      <div class="flex items-center"><div id="tpTitle" class="font-extrabold flex-1">添加事件 / 时间块</div><span id="tpRange" class="text-[10px] text-slate-400"></span></div>');
rep('B-foot', L([
  '      <div class="mt-2 flex gap-3">',
  '        <button onclick="tpAdd(1)" class="flex-1 py-3 rounded-xl border border-slate-300 dark:border-slate-700 text-sm font-bold">继续添加</button>',
  '        <button onclick="tpAdd(0)" class="flex-1 py-3 rounded-xl grad text-white text-sm font-bold">添加</button>',
  '      </div>',
]), '      <div id="tpFoot" class="mt-2 flex gap-3"></div>');

/* C) openTimePick 重写（今天默认当前 · 编辑预填） */
rep('C-open', L([
  "function openTimePick(d,h,m){tpSel={cat:'工作',sub:null};",
  "  $('#tpNote').value='';$('#tpNoteC').textContent='0/5000';",
  "  const di=Math.max(0,Math.min(7,(d||19)-13));",
  "  wReg('tpSd',TP_DAYS,di,tpUpd);wReg('tpSh',TP_HRS,h||0,tpUpd);wReg('tpSm',TP_MINS,Math.floor((m||0)/5),tpUpd);",
  "  wReg('tpEd',TP_DAYS,di,tpUpd);wReg('tpEh',TP_HRS,Math.min(23,(h||0)+1),tpUpd);wReg('tpEm',TP_MINS,Math.floor((m||0)/5),tpUpd);",
  "  tpCats();tpSubsRender();tpUpd();openSheet('sheetTimePick')}",
]), L([
  "function openTimePick(d,h,m,editBlk){const isNow=h===undefined&&m===undefined;",
  "  tpEdit=editBlk||null;tpTiming=false;tpSel={cat:tpEdit?tpEdit.cat:'工作',sub:null};",
  "  const bl=tpEdit;const sd=bl?(bl.day||TODAY):(d||TODAY);",
  "  let s0=bl?bl.s:(sd===TODAY&&isNow?nowMin():((h||0)*60));",
  "  let e0=bl?bl.e:(sd===TODAY&&isNow?s0:((Math.min(23,(h||0)+1))*60+(m||0)));",
  "  if(bl&&bl.tm){tpTiming=true;e0=nowMin()}",
  "  $('#tpNote').value=bl?(bl.note||''):'';$('#tpNoteC').textContent=($('#tpNote').value.length)+'/5000';",
  "  $('#tpTitle').textContent=bl?'编辑事件 / 时间块':'添加事件 / 时间块';",
  "  const di=Math.max(0,Math.min(7,sd-13));",
  "  wReg('tpSd',TP_DAYS,di,tpUpd);wReg('tpSh',TP_HRS,Math.floor(s0/60),tpUpd);wReg('tpSm',TP_MINS,Math.floor(s0%60/5),tpUpd);",
  "  wReg('tpEd',TP_DAYS,di,tpUpd);wReg('tpEh',TP_HRS,Math.floor(e0/60),tpUpd);wReg('tpEm',TP_MINS,Math.floor(e0%60/5),tpUpd);",
  "  const hint=$('#tpHintEl');if(hint)hint.textContent=bl?(tpTiming?'● 计时中 · 已 '+(e0-bl.s)+' 分钟':'✎ 编辑中 · 修改即保存'):(sd===TODAY&&isNow?'▶ 起止默认当前 · 确认后即为计时中':(sd!==TODAY?'补录 · 完全以所设时间为准':''));",
  "  tpCats();tpSubsRender();tpFoot();tpUpd();openSheet('sheetTimePick')}",
  "function tpNow(){const n=nowMin();tpSetWheel('tpSd',TODAY-13);tpSetWheel('tpSh',Math.floor(n/60));tpSetWheel('tpSm',Math.floor(n%60/5));",
  "  tpSetWheel('tpEd',TODAY-13);tpSetWheel('tpEh',Math.floor(n/60));tpSetWheel('tpEm',Math.floor(n%60/5));tpUpd()}",
]));

/* C2) tpUpd 计时中实时时长 */
rep('C2-upd', L([
  "function tpUpd(){const s=tpMin('tpSh')*60+tpMin('tpSm'),e=tpEd();",
  "  $('#tpRange').textContent=WHEELS.tpSd.items[WHEELS.tpSd.i]+' '+String(tpMin('tpSh')).padStart(2,'0')+':'+String(tpMin('tpSm')).padStart(2,'0')+' → '+WHEELS.tpEd.items[WHEELS.tpEd.i]+' '+String(Math.floor(e/60)%24).padStart(2,'0')+':'+String(e%60).padStart(2,'0')+' · '+(e<s?e+1440-s:e-s)+' 分钟'+(e<s?' · 跨天':'')}",
]), L([
  "function tpUpd(){const s=tpMin('tpSh')*60+tpMin('tpSm'),e=tpEd();",
  "  $('#tpRange').textContent=WHEELS.tpSd.items[WHEELS.tpSd.i]+' '+String(tpMin('tpSh')).padStart(2,'0')+':'+String(tpMin('tpSm')).padStart(2,'0')+' → '+WHEELS.tpEd.items[WHEELS.tpEd.i]+' '+String(Math.floor(e/60)%24).padStart(2,'0')+':'+String(e%60).padStart(2,'0')+' · '+(e<s?e+1440-s:e-s)+' 分钟'+(e<s?' · 跨天':'');",
  "  if(tpTiming){const h=$('#tpHintEl');if(h)h.textContent='● 计时中 · 已 '+(nowMin()-(tpEdit?tpEdit.s:s))+' 分钟 · 点「■ 结束计时」落当前时刻，或改结束时间后保存'}}",
]));

/* D) 删除旧详情弹层 HTML */
rep('D-delsheet', L([
  '  <!-- ===== 统一事件详情弹层（V1.19 · 五视图共用 · 任意状态可查改删） ===== -->',
  '  <div id="sheetEventDetail" class="sheet hidden fixed md:absolute inset-0 z-50 bg-black/40 items-end" onclick="if(event.target===this)closeSheet(\'sheetEventDetail\')">',
  '    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">',
  '      <div class="grabber"></div>',
  '      <div id="evdBody"></div>',
  '    </div>',
  '  </div>',
  '',
]), '');

/* E) 轴视图整函数替换 */
repBlock('E-timeline',
  "function renderTimeline(){const el=$('#timeAxis');if(!el)return;",
  " el.innerHTML=h;}",
  L([
  "function renderTimeline(){const el=$('#timeAxis');if(!el)return;",
  " const list=dayBlocks(calDay).slice().sort((x,y)=>x.s-y.s);",
  " let h='';",
  " if(liveEv){h+=`<div class=\"relative mb-4\"><span class=\"absolute -left-14 top-0 w-12 text-right text-[10px] font-mono text-rose-500 font-bold\">${fmt(liveEv.s)}</span><span class=\"absolute -left-[9px] top-1 w-2.5 h-2.5 rounded-full bg-rose-400 animate-pulse\"></span>",
  "  <div class=\"card !py-2.5 !px-3 live-card flex items-center gap-2 cursor-pointer\" onclick=\"openEventDetail('live')\"><div class=\"flex-1\"><div class=\"text-sm font-bold\">${liveEv.t}</div><div class=\"text-[10px] text-rose-400 mt-0.5\">● 进行中 · ${fmt(liveEv.s)} 开始 · 已 <b id=\"liveDur\">0 分钟</b> · 点卡片可管理</div></div><button class=\"px-3 py-2 rounded-xl bg-rose-500 text-white text-[11px] font-extrabold shrink-0\" onclick=\"event.stopPropagation();endNow()\">■ 结束</button></div></div>`}",
  " h+=list.map(b=>{const id=blocks.indexOf(b);",
  "  if(b.tm)return `<div class=\"relative mb-4\"><span class=\"absolute -left-14 top-0 w-12 text-right text-[10px] font-mono text-rose-500 font-bold\">${fmt(b.s)}</span><span class=\"absolute -left-[9px] top-1 w-2.5 h-2.5 rounded-full bg-rose-400 animate-pulse\"></span>",
  "  <div class=\"card !py-2.5 !px-3 live-card flex items-center gap-2 cursor-pointer\" onclick=\"openBlockEdit(blocks[${id}])\"><div class=\"flex-1 min-w-0\"><div class=\"text-sm font-bold truncate\">${b.note||b.cat}</div><div class=\"text-[10px] text-rose-400 mt-0.5\">● 计时中 · ${fmt(b.s)} 开始 · 已 <b>${Math.max(0,nowMin()-b.s)}</b> 分钟 · 点卡片可结束/修改</div></div><button class=\"px-3 py-2 rounded-xl bg-rose-500 text-white text-[11px] font-extrabold shrink-0\" onclick=\"event.stopPropagation();tpEdit=blocks[${id}];tpTiming=true;tpEnd()\">■ 结束计时</button></div></div>`;",
  "  const sub=b.dn?`✓ 已完成 · ${fmt(b.s)} – ${fmt(b.e)} · 实际 ${b.e-b.s} 分钟 · 已回填 L1 · 入时间账本 L4 · 点卡片仍可修改/删除`:`${b.cat} · ${fmt(b.s)} – ${fmt(b.e)} · ${b.e-b.s} 分钟 · 点卡片修改起止/类型`;",
  "  return `<div class=\"relative mb-4\">",
  "    <span class=\"absolute -left-14 top-0 w-12 text-right text-[10px] font-mono text-slate-400\">${fmt(b.s)}</span>",
  "    <span class=\"absolute -left-[9px] top-1 w-2 h-2 rounded-full ${blkColor(b)}\"></span>",
  "    <div class=\"card !py-2.5 !px-3 ${b.dn?'border-l-4 border-emerald-400 opacity-75':''} cursor-pointer\" onclick=\"openBlockEdit(blocks[${id}])\">",
  "      <div class=\"text-sm font-bold ${b.dn?'line-through decoration-slate-300':''}\">${b.note||b.cat}</div><div class=\"text-[10px] ${b.dn?'text-emerald-500':'text-slate-400'} mt-0.5\">${sub}</div></div></div>`}).join('');",
  " if(!list.length&&!liveEv)h+=`<div class=\"card !py-6 text-center text-xs text-slate-400\">当天暂无安排 · 点空行或右下角 ＋ ${calDay===TODAY?'开始计时':'补录'}</div>`;",
  " if(calDay===TODAY){h+=D.todos.map((t,i)=>({t,i})).filter(x=>x.t.timeMode&&x.t.timeMode!=='all').map(x=>{const t=x.t,i=x.i;",
  "      const run=pomoRun&&pomoRun.i===i;",
  "      return `<div class=\"relative mb-4\"><span class=\"absolute -left-14 top-0 w-12 text-right text-[10px] font-mono text-violet-400\">${t.timeMode==='point'?t.tm:t.tm+'-'+t.te}</span><span class=\"absolute -left-[9px] top-1 w-2 h-2 rounded-full bg-violet-400\"></span>",
  "      <div class=\"card !py-2.5 !px-3 border-l-4 border-violet-400 flex items-center gap-2\"><div class=\"flex-1 min-w-0\"><div class=\"text-sm font-bold ${t.done?'line-through text-slate-400':''} truncate\">🔘 ${t.t}${t.pomo?' 🍅':''}</div><div class=\"text-[10px] text-slate-400 mt-0.5\">定时待办 · ${D.quads[t.q].name}${t.pomo?' · 番茄'+(t.pomo.mode==='down'?t.pomo.min+'分倒计时':'正计时'):''}</div></div>",
  "      ${t.pomo?(run?`<button class=\"px-3 py-2 rounded-xl bg-rose-500 text-white text-[11px] font-extrabold shrink-0\" onclick=\"pomoFinish()\">■ 结束</button>`:`<button class=\"px-3 py-2 rounded-xl bg-rose-500/90 text-white text-[11px] font-extrabold shrink-0\" onclick=\"pomoStart(${i})\">▶ 番茄</button>`)",
  "        :`<button onclick=\"tglTodo('${t.t}')\" class=\"chk ${t.done?'chk-on':''} shrink-0\">${t.done?'✓':''}</button>`}</div></div>`}).join('');",
  " h+=`<div class=\"relative cursor-pointer\" onclick=\"openTimePick(calDay)\"><span class=\"absolute -left-14 w-12 text-right text-[10px] font-mono text-slate-400\">17:00</span><div class=\"text-xs text-slate-300 dark:text-slate-600 py-6 text-center border-2 border-dashed border-slate-200 dark:border-slate-800 rounded-2xl\">空闲 · 点此补录该时段日程</div></div>`}",
  " el.innerHTML=h;}",
]));

/* F) 块视图点已有块 → 编辑弹层 */
rep('F-grid', L([
  "    /* 点事件/完成/进行中块 → 统一详情弹层（五视图同一 CRUD），不走标记面板 */",
  "    if(hit&&hit.ev!==undefined){markSel=null;selA=selB=null;renderGrid();openEventDetail('plan',hit.ev);return}",
  "    if(hit&&hit.done!==undefined){markSel=null;selA=selB=null;renderGrid();openEventDetail('ended',hit.done);return}",
  "    if(hit&&hit.live){markSel=null;selA=selB=null;renderGrid();openEventDetail('live');return}",
]), L([
  "    /* V1.52：点已有块/事件 → 与添加同款弹层直接修改起止/类型（不再走详情层） */",
  "    if(hit){markSel=null;selA=selB=null;renderGrid();openBlockEdit(hit);return}",
]));

/* F2) 选区直标：收口计时 + 带日字段 */
rep('F2-mark',
  "  keep.push({s:st,e:en,cat:cat,note:cat});",
  "  if(calDay===TODAY)closeTimingAt(Math.min(nowMin(),st));\n  keep.push({day:calDay,s:st,e:en,cat:cat,note:cat});");

/* G) 旧详情函数退役（保留 liveEv 兼容路径） */
rep('G-retire',
  "/* —— 统一事件详情弹层（V1.19 · 任意视图任意状态：查看/编辑/删除/开始/结束） —— */",
  "/* V1.52：旧详情弹层仅剩 liveEv（开始/结束事项）兼容路径；plan/ended 已改走 openBlockEdit 统一编辑弹层 */");
rep('G-edit',
  "function editEvent(kind,i){closeSheet('sheetEventDetail');openSheet('sheetAddEvent');toast('编辑表单（模拟）· 保存后五视图与时间账本同步更新')}",
  "function editEvent(kind,i){closeSheet('sheetEventDetail');openSheet('sheetAddEvent');toast('编辑表单（模拟）')}",
);

/* H) 日视图 chips 改统一数据 */
rep('H-day', L([
  "   let chips='';",
  "   if(calDay===19){",
  "    chips+=D.events.map((e,i)=>({e,i})).filter(x=>Math.floor(hm2min(x.e.tm)/60)===hr)",
  "     .map(x=>`<div onclick=\"event.stopPropagation();openEventDetail('plan',${x.i})\" class=\"mb-1 rounded-lg bg-brand-500/90 text-white text-[10px] font-bold px-2 py-1.5 cursor-pointer\">${x.e.tm} ${x.e.t} ›</div>`).join('');",
  "    chips+=endedEvs.map((e,i)=>({e,i})).filter(x=>Math.floor(hm2min(x.e.tm)/60)===hr)",
  "     .map(x=>`<div onclick=\"event.stopPropagation();openEventDetail('ended',${x.i})\" class=\"mb-1 rounded-lg bg-emerald-400/90 text-white text-[10px] font-bold px-2 py-1.5 cursor-pointer\">${x.e.tm} ${x.e.t} ✓ ›</div>`).join('');",
  "    if(liveEv&&Math.floor(liveEv.s/60)===hr)chips+=`<div onclick=\"event.stopPropagation();openEventDetail('live')\" class=\"mb-1 rounded-lg bg-rose-500 text-white text-[10px] font-extrabold px-2 py-1.5 animate-pulse cursor-pointer\">● ${liveEv.t} 进行中 ›</div>`;",
  "   }",
]), L([
  "   let chips='';",
  "   chips+=dayBlocks(calDay).filter(b=>Math.floor(b.s/60)===hr).map(b=>{const id=blocks.indexOf(b);",
  "    const lbl=b.tm?'●':(b.dn?'✓':'');",
  "    return `<div onclick=\"event.stopPropagation();openBlockEdit(blocks[${id}])\" class=\"mb-1 rounded-lg ${b.tm?'bg-rose-500 animate-pulse':(b.dn?'bg-emerald-400/90':blkColor(b))} text-white text-[10px] font-bold px-2 py-1.5 cursor-pointer\">${fmt(b.s)} ${b.note||b.cat} ${lbl} ›</div>`}).join('');",
  "   if(calDay===19&&liveEv&&Math.floor(liveEv.s/60)===hr)chips+=`<div onclick=\"event.stopPropagation();openEventDetail('live')\" class=\"mb-1 rounded-lg bg-rose-500 text-white text-[10px] font-extrabold px-2 py-1.5 animate-pulse cursor-pointer\">● ${liveEv.t} 进行中 ›</div>`;",
]));
rep('H2-row',
  'onclick="addEventAtHour(${hr})"',
  'onclick="openTimePick(calDay,${hr},0)"');
rep('H3-label',
  "  let h=`<div class=\"text-[10px] text-slate-400 mb-1\">🕐 9月${calDay}日 · 点空白小时补录 · 点事件卡管理（与块视图同一数据）</div>`;",
  "  let h=`<div class=\"text-[10px] text-slate-400 mb-1\">🕐 9月${calDay}日${calDay===TODAY?' · 今天'} · 点空白小时${calDay===TODAY?'按当前时间开始计时':'补录'} · 点事件卡修改起止/类型</div>`;");

/* I) 周视图改统一数据 */
rep('I-blocksAt',
  "function blocksAt(m){return allBlocks().filter(b=>m>=b.s&&m<b.e);}",
  "function blocksAt(m,d){return dayBlocks(d===undefined?TODAY:d).filter(b=>m>=b.s&&m<b.e);}");
rep('I2-days',
  "  const days=[13,14,15,16,17,18,19];",
  "  const days=[13,14,15,16,17,18,19];");
rep('I3-cells',
  "   for(const d of days){const m=hr*60;const bs=d===19?blocksAt(m):[];",
  "   for(const d of days){const m=hr*60;const bs=blocksAt(m,d);");
rep('I4-cls', L([
  "     const cls=b.done!==undefined?'bg-emerald-400':b.ev!==undefined?'bg-brand-500/80':(b.live?'animate-pulse ':'')+CATS[b.cat];",
  "     const act=b.ev!==undefined?`openEventDetail('plan',${b.ev})`:b.done!==undefined?`openEventDetail('ended',${b.done})`:`openEventDetail('live')`;",
]), L([
  "     const cls=b.dn?'bg-emerald-400':(b.tm?'animate-pulse ':'')+CATS[b.cat];",
  "     const act=`openBlockEdit(blocks[${blocks.indexOf(b)}])`;",
]));

/* J) 速记块带日 + 收口计时 */
rep('J-quick', L([
  "  const prev=blocks.filter(b=>b.qs===1);prev.forEach(b=>{b.e=Math.max(b.s,nm)});",
  "  blocks.push({s:nm,e:1439,cat:cat,qs:1,note:'速记 · '+cat});",
]), L([
  "  const prev=blocks.filter(b=>b.qs===1);prev.forEach(b=>{b.e=Math.max(b.s,nm)});",
  "  closeTimingAt(nm);",
  "  blocks.push({day:calDay,s:nm,e:1439,cat:cat,qs:1,note:'速记 · '+cat});",
]));

/* K) 种子块补 day */
rep('K-seed',
  "let blocks=[{s:540,e:585,cat:'工作',note:'晨间规划'},{s:1170,e:1230,cat:'运动',note:'腿日'},",
  "let blocks=[{day:19,s:540,e:585,cat:'工作',note:'晨间规划'},{day:19,s:1170,e:1230,cat:'运动',note:'腿日'},");

/* L) FAB：今天默认当前时刻 */
rep('L-fab',
  "'p-calendar':{ico:'＋',act:()=>openTimePick(calDay,(new Date().getHours()+1)%24,0)},",
  "'p-calendar':{ico:'＋',act:()=>openTimePick(calDay)},");

/* M) tick 刷新计时中显示 */
rep('M-tick',
  "function tick(){ const d=new Date(); $('#clock').textContent=d.getHours()+':'+String(d.getMinutes()).padStart(2,'0'); }",
  "function tick(){ const d=new Date(); $('#clock').textContent=d.getHours()+':'+String(d.getMinutes()).padStart(2,'0');\n if(timingBlk()&&document.querySelector('#p-calendar:not(.hidden)')&&!document.querySelector('.sheet.sheet-open'))renderCal(); }");

/* N) 启动迁移 */
rep('N-boot',
  "renderDash(); initDashOrder(); renderChips();",
  "migrateEv152(); renderDash(); initDashOrder(); renderChips();");

fs.writeFileSync(P, EOL === '\r\n' ? s.replace(/\n/g, '\r\n') : s);
console.log('OK ' + R.length + ' patches: ' + R.join(', '));
console.log('size ' + size0 + ' -> ' + s.length);
