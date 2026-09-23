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
function after(t, sub, ins) {
  const i = L.findIndex(l => l.indexOf(sub) >= 0);
  if (i < 0) { console.log('AFTER MISS', t); fails++; return }
  L = L.slice(0, i + 1).concat(ins, L.slice(i + 1)); S = L.join('\n');
}

/* ---- 新弹层与新 JS ---- */
before('sheets', '  <!-- ===== 主题市场 ===== -->', R('hbK_sheets.txt').concat(['']));
before('js', '/* ================= 插件中心（大模块插件化） ================= */', R('hbK_js.txt').concat(['function heGoalFromChg(){}\n']));

/* ---- 打卡备注 ---- */
before('notemk', '      <div class="mt-2 text-center" id="hlRule"></div>',
 ['      <div class="mt-2 flex items-center gap-2 text-[11px]"><span class="text-slate-400 shrink-0">备注</span><input id="hlNote" class="inp flex-1 !py-1.5" placeholder="可选 · 今天的情况"></div>']);
rep('noteopen', " hbLogRender();openSheet('sheetHabitLog')}",
 " const ni=document.getElementById('hlNote');if(ni)ni.value=(h.nt&&h.nt[6])||'';\n hbLogRender();openSheet('sheetHabitLog')}");
rep('notesave', " h.at=h.at||['','','','','','',''];if(!h.at[6])h.at[6]=hbNow();",
 " h.at=h.at||['','','','','','',''];if(!h.at[6])h.at[6]=hbNow();\n const ni=document.getElementById('hlNote');if(ni&&ni.value.trim()){h.nt=h.nt||{};h.nt[6]=ni.value.trim()}");
rep('getnote', "at:(h.at&&h.at[k])||'',bf:!!(h.bf&&h.bf[k])}", "at:(h.at&&h.at[k])||'',bf:!!(h.bf&&h.bf[k]),note:(h.nt&&h.nt[back])||''}");
rep('getnote2', "return {ok:!!e.ok,val:h.group?(e.sv||[]):((+e.v)||0),at:e.at||'',bf:!!e.bf}}", "return {ok:!!e.ok,val:h.group?(e.sv||[]):((+e.v)||0),at:e.at||'',bf:!!e.bf,note:e.note||''}}");
rep('setnote', "   if(meta.at!=null){h.at=h.at||['','','','','','',''];h.at[k]=meta.at}",
 "   if(meta.at!=null){h.at=h.at||['','','','','','',''];h.at[k]=meta.at}\n   if(meta.note!=null){h.nt=h.nt||{};h.nt[back]=meta.note}");
rep('setnote2', "   if(meta.at!=null)e.at=meta.at;if(meta.bf)e.bf=1}}", "   if(meta.at!=null)e.at=meta.at;if(meta.note!=null)e.note=meta.note;if(meta.bf)e.bf=1}}");
rep('flownote', "<span class=\"flex-1 min-w-0 truncate \${h.type==='neg'?'text-rose-500':'text-slate-500'}\">\${h.type==='neg'?'未触发':(val?val+' '+(h.group?'项次':(h.unit||'次')):'已打卡')}</span>",
 "<span class=\"flex-1 min-w-0 truncate \${h.type==='neg'?'text-rose-500':'text-slate-500'}\">\${h.type==='neg'?'未触发':(val?val+' '+(h.group?'项次':(h.unit||'次')):'已打卡')}\${g.note?' · '+g.note:''}</span>");

/* ---- 目标变更历史 ---- */
before('goalfrom', '        <div class="mt-1 text-[10px] text-slate-400" id="heValHint"></div>',
 ['        <div class="mt-2 flex items-center gap-2 text-xs"><span class="text-slate-400 shrink-0">目标生效</span><input id="heGoalFrom" type="date" class="sel !py-1.5 flex-1" max="2026-09-19" value="2026-09-19" onchange="heGoalFromChg()"><span class="text-[9.5px] text-slate-400 shrink-0">可指定日期</span></div>']);
rep('goalhist', " if(h){Object.assign(h,{n:v,ic:heIcon,type:heType,cat:heCat,cycle:heCycle,days:days,remind:heRemind==='on'?heRemindVal:'',src:heSrc.slice(),group:grp,subs:grp?subs:undefined,rule:grp?heRule:undefined,unit:unit,goal:goal});",
 " if(h){const gf=(document.getElementById('heGoalFrom')||{}).value||'2026-09-19';\n if(heValMode!=='off'&&((+h.goal||0)!==goal||(h.unit||'')!==(unit||'')||grp&&(h.subs||[]).length!==subs.length)){h.goalHist=h.goalHist||[];\n   if(!h.goalHist.some(x=>x.from===gf))h.goalHist.push({from:gf,goal:goal,unit:unit,subs:grp?subs.length:0});h.goalHist.sort((a,b)=>a.from<b.from?-1:1)}\n  Object.assign(h,{n:v,ic:heIcon,type:heType,cat:heCat,cycle:heCycle,days:days,remind:heRemind==='on'?heRemindVal:'',src:heSrc.slice(),group:grp,subs:grp?subs:undefined,rule:grp?heRule:undefined,unit:unit,goal:goal});");

/* ---- 宽限卡 ---- */
rep('setkeys', "const HB_SET={spanFromStart:true,autoChk:true,remindAll:true,weekStart:0,rateBase:0};",
 "const HB_SET={spanFromStart:true,autoChk:true,remindAll:true,weekStart:0,rateBase:0,grace:1,autoMode:0,nightRemind:true,nightAt:1,dnd:1};");
rep('setitems', " ['catMgr','分类管理','自定义习惯分类 · 改名 / 排序 / 删除前迁移','nav',\"hbMgrOpen('cat')\"],",
 " ['grace','每月宽限次数','断签时用一张宽限保住连续 · 一天抵消一次','seg',['不用','1 张','2 张','3 张']],\n ['autoMode','自动达成方式','番茄 / 阅读计时 / 日程达成后的处理','seg',['直接打卡','需我确认']],\n ['nightRemind','晚间未打卡提醒','到点仍未打卡时补一次提醒','sw'],\n ['nightAt','晚间提醒时间','仅在开启晚间提醒时生效','seg',['18:00','20:00','21:30','22:30']],\n ['dnd','免打扰时段','该区间内不推送任何习惯提醒','seg',['关闭','22:00-08:00','23:00-07:00']],\n ['arch','已归档习惯','归档纪录仍保留 · 点击进入归档筛选','nav','hbArchGoto()'],\n ['catMgr','分类管理','自定义习惯分类 · 改名 / 排序 / 删除前迁移','nav',\"hbMgrOpen('cat')\"],");
rep('freezebtn', `<button class="w-9 h-9 rounded-xl border border-slate-200 dark:border-slate-700 text-slate-400 flex items-center justify-center shrink-0" title="详情与统计"`,
 `\${(!ok&&hbGl(h)>0&&(h.streak||0)>0)?'<button class="px-3 !py-2 rounded-xl bg-sky-50 dark:bg-sky-500/15 text-sky-600 dark:text-sky-400 text-xs font-extrabold shrink-0" onclick="event.stopPropagation();hbFreeze('+i+')">宽限 '+hbGl(h)+'</button>':''}<button class="w-9 h-9 rounded-xl border border-slate-200 dark:border-slate-700 text-slate-400 flex items-center justify-center shrink-0" title="详情与统计"`);
rep('dotfz', `<span class="hb-dot \${h.type==='pos'?`, `<span class="hb-dot \${h.fz&&h.fz[i]?'ring-1 ring-sky-400 ':''}\${h.type==='pos'?`);
rep('detailrule', `<div class="flex justify-between"><span class="text-slate-400">开始跟踪</span><b>\${h.start||'2026-08'} · 已跟踪 \${hbSpanD(h)} 天</b></div></div>`,
 `<div class="flex justify-between"><span class="text-slate-400">开始跟踪</span><b>\${h.start||'2026-08'} · 已跟踪 \${hbSpanD(h)} 天</b></div>
     <div class="flex justify-between"><span class="text-slate-400">宽限卡</span><b>\${h.type==='pos'?hbGl(h)+' 张可用 · 本月已用 '+((h.fz||[]).filter(v=>v).length)+' 张':'不适用'}</b></div>
     \${(h.goalHist||[]).length?'<div class="mt-1 text-[10px] text-slate-400 leading-4">目标变更：'+h.goalHist.map(g=>g.from+' 起 '+(g.subs?(g.subs+' 项子项'):((g.goal||0)+(g.unit||'次')))).join(' · ')+'</div>':''}</div>`);

/* ---- 自动达成待确认 ---- */
rep('pendsync', " if(!h){renderHabits();return}\n if(h.w[6]){renderHabits();return}",
 " if(!h){renderHabits();return}\n if(h.w[6]){renderHabits();return}\n if(HB_SET.autoMode){h.pend=h.pend||[];h.pend.push({src:(h.src||[]).find(s=>s!=='手动打卡')||'自动达成',t:hbNow(),val:0});renderHabits();toast('「'+h.n+'」来源已达成 · 待你确认');return}");
rep('pendhero', `onclick="hbSrcOpen()">\${hbi('flame'`, `onclick="\${HB_SET.autoMode?'hbPendOpen()':'hbSrcOpen()'}">\${hbi(HB_SET.autoMode?'undo':'flame'`);
rep('pendhero2', ` 今日自动达成 \${auto.length} 项 · 查看来源`, ` \${HB_SET.autoMode?('待确认 '+(auto.reduce((a,h)=>a+(h.pend||[]).length,0))+' 项 · 逐条确认'):('今日自动达成 '+auto.length+' 项 · 查看来源')}`);
rep('simbtn', `      <button class="mt-4 w-full py-2.5 rounded-xl card text-xs font-bold" onclick="closeSheet('sheetHabitSrc')">完成</button>`,
 `      <button id="hsSim" class="hidden mt-3 w-full py-2.5 rounded-xl grad text-white text-xs font-bold" onclick="hbPendSim()">模拟一次自动达成</button>
      <button class="mt-3 w-full py-2.5 rounded-xl card text-xs font-bold" onclick="closeSheet('sheetHabitSrc')">完成</button>`);
rep('simshow', " openSheet('sheetHabitSrc')}", " const bt=document.getElementById('hsSim');if(bt)bt.classList.toggle('hidden',!HB_SET.autoMode);\n openSheet('sheetHabitSrc')}");

/* ---- 模板库入口 ---- */
after('tplbtn', `<input id="heName" class="inp w-full mt-3" placeholder="习惯名称，如：晨间跑步 30 分钟" oninput="heName=this.value">`,
 [`      <div class="mt-2 flex items-center gap-2"><button class="chip !text-[10px]" onclick="hbTplOpen()">从模板填充</button><span class="text-[9.5px] text-slate-400">带出分类 / 频率 / 目标量 / 提醒</span></div>`]);

/* ---- 分享长图入口 ---- */
rep('sharehdr', " else if(p==='p-habitStat')html=hbHdrBtn('cog','打卡设置','hbSetOpen()');",
 " else if(p==='p-habitStat')html=hbHdrBtn('doc','分享长图','hbShareOpen()')+hbHdrBtn('cog','打卡设置','hbSetOpen()');");

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED K');
