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
function after(t, sub, ins) {
  const i = L.findIndex(l => l.indexOf(sub) >= 0);
  if (i < 0) { console.log('AFTER MISS', t); fails++; return }
  L = L.slice(0, i + 1).concat(ins, L.slice(i + 1)); S = L.join('\n');
}

/* 时刻 / 时段分析 JS */
rep('js', '/* 补卡 */', R('hbA_js.txt').join('\n') + '\n/* 补卡 */');
/* 统计页时段卡片 */
rep('card', `      <div class="mt-3 card"><div class="row-title">分类构成</div>`,
`      <div class="mt-3 card"><div class="flex items-center gap-2"><div class="row-title">打卡时段分析</div><span class="ml-auto text-[10px] text-slate-400" id="hstTimeTip"></span></div><div class="mt-2" id="hstTime"></div></div>
      <div class="mt-3 card"><div class="row-title">分类构成</div>`);
rep('call', " const wall=document.getElementById('hstWall');", " hbTimeRender(dim,off);\n const wall=document.getElementById('hstWall');");
/* 详情页打卡流水 */
after('flow', '<i class="w-1.5 h-1.5 rounded-full bg-brand-500 ml-1.5"></i>有数值<span class="ml-auto">点日期可补记 · 今天可直接打卡</span>',
 [`   <div class="mt-2.5 text-[10px] font-bold text-slate-500">打卡流水 · 近 14 天</div>`, `   \${hbFlowHtml(h)}`]);
/* 记量面板显示今日时刻 */
rep('hlsub', " hbLogRender();openSheet('sheetHabitLog')}",
 " const _hl=document.getElementById('hlSub');if(_hl&&h.w[6]){const _at=hbAtOf(h,6);_hl.textContent+=' · 今日 '+(_at||'时刻未记')+(hbIsBf(h,6)?' · 补记':'')}\n hbLogRender();openSheet('sheetHabitLog')}");
/* 打卡时刻记录 */
rep('chk', "function hbCheck(i){const h=HABITS[i];h.w[6]=h.w[6]?0:1;",
 "function hbCheck(i){const h=HABITS[i];h.w[6]=h.w[6]?0:1;h.at=h.at||['','','','','','',''];h.at[6]=h.w[6]?hbNow():'';h.bf=h.bf||[0,0,0,0,0,0,0];h.bf[6]=0;");
rep('avoid', "function hbAvoid(i){const h=HABITS[i];if(h.w[6]){toast('今天已计入未触发');return}h.w[6]=1;",
 "function hbAvoid(i){const h=HABITS[i];if(h.w[6]){toast('今天已计入未触发');return}h.w[6]=1;h.at=h.at||['','','','','','',''];h.at[6]=hbNow();");
rep('logsave', " if(!h.w[6]){h.w[6]=1;h.streak=(h.streak||0)+1;h.mDone=(h.mDone||0)+1;if(h.streak>h.best)h.best=h.streak}",
 " if(!h.w[6]){h.w[6]=1;h.streak=(h.streak||0)+1;h.mDone=(h.mDone||0)+1;if(h.streak>h.best)h.best=h.streak}\n h.at=h.at||['','','','','','',''];if(!h.at[6])h.at[6]=hbNow();");
rep('slipat', "{dt:'09-19',rs:tgR||'未填情境',note:note,amt:amt+' '+(h.unit||'次')}", "{dt:'09-19',at:hbNow(),rs:tgR||'未填情境',note:note,amt:amt+' '+(h.unit||'次')}");
rep('slipshow', "<div class=\"flex-1 min-w-0\"><b>\${s.dt}</b> · \${s.rs||'未填情境'}", "<div class=\"flex-1 min-w-0\"><b>\${s.dt}</b>\${s.at?' '+s.at:''} · \${s.rs||'未填情境'}");
/* 详情页不再显示右下角 FAB（顶栏已有编辑 / 更多） */
rep('fab', "Object.assign(FAB_CFG,{'p-habits':{ico:'＋',act:()=>heOpen()},'p-habitDetail':{ico:'✎',act:()=>heOpen(hbCur)}});",
 "Object.assign(FAB_CFG,{'p-habits':{ico:'＋',act:()=>heOpen()}});");

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
S = L.join('\n');
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
