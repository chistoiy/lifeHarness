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
function span(t, aSub, bSub, ins) {
  const a = L.findIndex(l => l.indexOf(aSub) >= 0);
  const b = a < 0 ? -1 : L.findIndex((l, k) => k >= a && l.indexOf(bSub) >= 0);
  if (a < 0 || b < 0) { console.log('SPAN MISS', t, a, b); fails++; return }
  L = L.slice(0, a).concat(ins, L.slice(b + 1)); S = L.join('\n');
}
function before(t, sub, ins) {
  const i = L.findIndex(l => l.indexOf(sub) >= 0);
  if (i < 0) { console.log('BEFORE MISS', t); fails++; return }
  L = L.slice(0, i).concat(ins, L.slice(i)); S = L.join('\n');
}

/* 热力图维度切换 */
before('hearseg', '        <div class="mt-2 overflow-x-auto no-scrollbar" id="hstHeat"></div>',
 ['        <div class="mt-2 flex gap-1.5" id="hstHeatSeg"></div>']);
span('head', "function hbHeatRender(){const el=document.getElementById('hstHeat')", ' const lead=(today.getDay()+6)%7;', R('hbL_a.txt'));
span('cell', 'const dt=hbDateOf(back);let n=0,bf=0;', '"></button>`}', R('hbL_b.txt'));
rep('heatlegend', " if(lg)lg.innerHTML='<span>少</span>",
 " if(!lg)return;\n if(hbHeatMode===2){lg.innerHTML='<span>时段</span><i class=\"w-[9px] h-[9px] rounded-[2px] bg-violet-300 dark:bg-violet-500/35\"></i><span>凌晨</span><i class=\"w-[9px] h-[9px] rounded-[2px] bg-sky-300 dark:bg-sky-500/35 ml-1.5\"></i><span>上午</span><i class=\"w-[9px] h-[9px] rounded-[2px] bg-amber-300 dark:bg-amber-500/35 ml-1.5\"></i><span>下午</span><i class=\"w-[9px] h-[9px] rounded-[2px] bg-indigo-400 dark:bg-indigo-500/70 ml-1.5\"></i><span>晚上</span>';return}\n lg.innerHTML='<span>少</span>");
rep('heattip', " if(tip)tip.textContent='近 '+W+' 周 · 每格为一天达成习惯数';",
 " if(tip)tip.textContent='近 '+W+' 周 · '+(hbHeatMode===0?'每格为一天达成习惯数':hbHeatMode===1?'深浅为一天记录量':'颜色为一天主要打卡时段');");

/* 三态视图 + 紧凑行 + 全达成横幅 */
rep('viewcycle', "function hbViewT(){hbView=hbView==='list'?'grid':'list';renderHabits();toast(hbView==='list'?'列表视图 · 看每日明细':'方块视图 · 看完成度与打卡')}",
 "const HB_VIEWS=[['list','列表 · 明细与操作'],['compact','紧凑 · 一行一个'],['grid','方块 · 完成度']];\nfunction hbViewT(){const i=HB_VIEWS.findIndex(v=>v[0]===hbView);hbView=HB_VIEWS[(i+1)%HB_VIEWS.length][0];renderHabits();toast('切到'+HB_VIEWS[(i+1)%HB_VIEWS.length][1])}");
rep('viewicon', "vb.innerHTML=hbi(hbView==='list'?'grid':'list','w-[15px] h-[15px]');vb.title=hbView==='list'?'切到方块视图':'切到列表视图'",
 "vb.innerHTML=hbi(hbView==='grid'?'list':hbView==='compact'?'chart':'grid','w-[15px] h-[15px]');vb.title='当前 '+(hbView==='list'?'列表':hbView==='compact'?'紧凑':'方块')+' · 点击切换视图'");
rep('viewcls', "el.className=hbView==='list'?'mt-3 space-y-3':'mt-3 grid grid-cols-2 gap-2';el.innerHTML=list.length?(hbView==='list'?list.map(h=>hbCard(h)).join(''):list.map(h=>hbTile(h)).join('')):'<div class=\"card text-[11px] text-slate-400 text-center !py-8\">该筛选下暂无习惯 · <button class=\"link-act\" onclick=\"heOpen()\">新建一个</button></div>';",
 "el.className=hbView==='grid'?'mt-3 grid grid-cols-2 gap-2':'mt-3 space-y-2';el.innerHTML=(t.length&&t.every(h=>h.w[6])?'<div class=\"rounded-2xl grad text-white p-3 text-[12px] font-extrabold flex items-center gap-2\">'+hbi('flame','w-[15px] h-[15px]')+' 今日应打卡 '+t.length+' 项全部达成 · 连续纪录继续推进</div>':'')+(list.length?(hbView==='grid'?list.map(h=>hbTile(h)).join(''):list.map(h=>hbView==='compact'?hbCardMini(h):hbCard(h)).join('')):'<div class=\"card text-[11px] text-slate-400 text-center !py-8\">该筛选下暂无习惯 · <button class=\"link-act\" onclick=\"heOpen()\">新建一个</button></div>');");
span('mini', 'function hbTileTap(i){', 'function hbTileTap(i){', R('hbL_c.txt'));

/* 待确认弹层按钮 id */
rep('hpall', '<button class="mt-4 w-full py-2.5 rounded-xl card text-xs font-bold" onclick="hbPendAll()">全部确认</button>',
 '<button id="hpAll" class="mt-4 w-full py-2.5 rounded-xl card text-xs font-bold" onclick="hbPendAll()">全部确认</button>');

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK js=' + ms[ms.length - 1][1].length) }
catch (e) { fs.writeFileSync('tools/_dbg.html', S); console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED L');
