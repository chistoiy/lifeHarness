/* 轮6-A：统一「进行中」为单一计时块 · 删旧新建日程/格子标记弹层 · 删冲突提示条 · 速记列改开计时 */
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
function cut(name, startMark, endMark) {
  const i = s.indexOf(startMark), j = s.indexOf(endMark, i + startMark.length);
  if (i < 0 || j < 0) { console.error('CUT FAIL ' + name); process.exit(1); }
  s = s.slice(0, i) + s.slice(j); R.push(name);
}
const L = a => a.join('\n');

/* ① 删两个退役弹层（新建日程 sheetAddEvent + 格子标记 sheetGridMark） */
cut('sheets', '<!-- ===== 新建日程 =====', '<!-- ===== 统一添加事件/时间块弹层');

/* ② 删冲突提示条 HTML + 绑定 + 切换调用 */
cut('conflict-html', '      <div id="conflictTip"', '\n      <!-- ① 轴视图');
rep('conflict-bind',
  " ['#calAxisView','#calBlockView','#calDayHourView','#calWeekGrid','#conflictTip'].forEach(s=>{const t=$(s);if(t)t.addEventListener('pointerdown',e=>{if(e.target.closest('button,a,input,select,.toggle,.grid-cell,.wk-cell'))return;collapseMonth()},{passive:true})})",
  " ['#calAxisView','#calBlockView','#calDayHourView','#calWeekGrid'].forEach(s=>{const t=$(s);if(t)t.addEventListener('pointerdown',e=>{if(e.target.closest('button,a,input,select,.toggle,.grid-cell,.wk-cell'))return;collapseMonth()},{passive:true})})");
rep('conflict-switch',
  " $('#conflictTip').classList.add('hidden');\n", "");

/* ③ 删 startNow/endNow（旧 liveEv 机制） */
cut('startend', '/* —— 进行中事项：现在就开始 / 结束', 'function renderTimeline()');

/* ④ 删旧详情弹层函数群（openEventDetail/startPlan/editEvent/delEvent） */
cut('detailfns', '/* V1.52：旧详情弹层仅剩 liveEv', '/* —— 日视图：0-23 小时刻度');

/* ⑤ 删 doMark/delMark（格子标记弹层已移除） */
cut('domark', "function doMark(){if(!markSel)return;", "/* —— 右侧分类速记列");

/* ⑥ liveEv 变量与残留引用清理 */
rep('var', "let calDay=19, monthExpanded=true, liveEv=null, endedEvs=[];",
  "let calDay=19, monthExpanded=true, endedEvs=[];");
rep('daystatus',
  " if(bs.some(b=>b.tm)||(d===TODAY&&liveEv))return 'live';",
  " if(bs.some(b=>b.tm))return 'live';");
rep('label',
  "function updateDayLabel(){const el=$('#dayLabel');if(el)el.textContent=`9月${calDay}日 · 周${WDS[(calDay+1)%7]}${calDay===19?' · 今天':''}${liveEv&&calDay===19?' · 1 项进行中':''}`}",
  "function updateDayLabel(){const el=$('#dayLabel');if(el)el.textContent=`9月${calDay}日 · 周${WDS[(calDay+1)%7]}${calDay===TODAY?' · 今天':''}${timingBlk()?' · 1 项计时中':''}`}");
rep('axis-live',
  L([
  " if(liveEv){h+=`<div class=\"relative mb-4\"><span class=\"absolute -left-14 top-0 w-12 text-right text-[10px] font-mono text-rose-500 font-bold\">${fmt(liveEv.s)}</span><span class=\"absolute -left-[9px] top-1 w-2.5 h-2.5 rounded-full bg-rose-400 animate-pulse\"></span>",
  "  <div class=\"card !py-2.5 !px-3 live-card flex items-center gap-2 cursor-pointer\" onclick=\"openEventDetail('live')\"><div class=\"flex-1\"><div class=\"text-sm font-bold\">${liveEv.t}</div><div class=\"text-[10px] text-rose-400 mt-0.5\">● 进行中 · ${fmt(liveEv.s)} 开始 · 已 <b id=\"liveDur\">0 分钟</b> · 点卡片可管理</div></div><button class=\"px-3 py-2 rounded-xl bg-rose-500 text-white text-[11px] font-extrabold shrink-0\" onclick=\"event.stopPropagation();endNow()\">■ 结束</button></div></div>`}",
  ]), "");
rep('axis-empty-cond',
  " if(!list.length&&!liveEv)h+=`<div class=\"card !py-6 text-center text-xs text-slate-400\">当天暂无安排 · 点空行或右下角 ＋ ${calDay===TODAY?'开始计时':'补录'}</div>`;",
  " if(!list.length)h+=`<div class=\"card !py-6 text-center text-xs text-slate-400\">当天暂无安排 · 点空隙或右下角 ＋ ${calDay===TODAY?'开始计时':'补录'}</div>`;");
rep('day-live',
  "   if(calDay===19&&liveEv&&Math.floor(liveEv.s/60)===hr)chips+=`<div onclick=\"event.stopPropagation();openEventDetail('live')\" class=\"mb-1 rounded-lg bg-rose-500 text-white text-[10px] font-extrabold px-2 py-1.5 animate-pulse cursor-pointer\">● ${liveEv.t} 进行中 ›</div>`;\n", "");

/* ⑦ 速记列：未选中时单点开「计时中」块（与 ＋ 添加同一状态机） */
rep('quickmark',
  L([
  "function quickMark(cat){const now=new Date();const nm=now.getHours()*60+now.getMinutes();",
  "  const prev=blocks.filter(b=>b.qs===1);prev.forEach(b=>{b.e=Math.max(b.s,nm)});",
  "  closeTimingAt(nm);",
  "  blocks.push({day:calDay,s:nm,e:1439,cat:cat,qs:1,note:'速记 · '+cat});",
  "  renderCal();",
  "  toast('📝 已记「'+cat+'」从 '+fmt(nm)+' 起'+(prev.length?'（上一段已截止 '+fmt(nm)+'）':'')+' · 点下一分类自动接龙 · 与块/账本同步');}",
  ]),
  L([
  "function quickMark(cat){if(calDay!==TODAY){toast('仅今天可速记开始计时 · 其他日期请用 ＋ 补录');return}",
  "  const nm=nowMin();const prev=timingBlk();closeTimingAt(nm);",
  "  blocks.push({day:TODAY,s:nm,e:nm,cat:cat,tm:1,note:cat});",
  "  renderCal();",
  "  toast((prev?'▶ 上一段「'+prev.cat+'」已截止 '+fmt(nm)+' · ':'')+'开始计时「'+cat+'」· 点该块「■ 结束计时」或点其他分类自动接龙');}"]));

/* ⑧ qs 字段退役：markRange 保留判断改 tm */
rep('markrange',
  "    if(b.live||b.qs===1||b.e<=st||b.s>=en){keep.push(b);return}",
  "    if(b.tm||b.e<=st||b.s>=en){keep.push(b);return}");
rep('markmerge',
  "    if(l&&l.cat===b.cat&&l.e===b.s&&!l.live&&l.qs===undefined&&l.note===b.note){l.e=b.e}else out.push(b)});",
  "    if(l&&l.cat===b.cat&&l.e===b.s&&!l.tm&&!b.tm&&l.note===b.note){l.e=b.e}else out.push(b)});");

/* ⑨ 标记面板配套函数退役（#markCats 已随弹层删除） */
cut('rendercats', "function renderCats(){$('#markCats')", "function renderGrid(){");
rep('boot-cats2', "renderCats(); renderGrid(); initGrid();", "renderGrid(); initGrid();");

fs.writeFileSync(P, s);
console.log('OK ' + R.length + ': ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
