/* 轮6-D：时间账本 L4 统计屏（p-timeStats · blocks 实算）+ 仪表盘分布卡改实算 + 时间页入口 */
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

/* ① 统计页 section（挂在分类管理页之后） */
rep('page-html', '    <!-- ===== P12d 二级：分类管理', L([
  '    <!-- ===== 时间账本（L4 · 分类时长统计 · 与轴/块/日/周同一份 blocks） ===== -->',
  '    <section id="p-timeStats" class="page px-5 safe-pb no-scrollbar">',
  '      <div class="flex items-center gap-2 mt-3">',
  '        <span class="seg"><button id="tsScopeW" class="seg-on" onclick="tsSet(\'w\')">本周</button><button id="tsScopeM" onclick="tsSet(\'m\')">本月</button></span>',
  '        <span class="ml-auto text-[10px] text-slate-400" id="tsMeta"></span>',
  '      </div>',
  '      <div class="grad rounded-3xl p-4 text-white shadow-lg shadow-indigo-500/20 mt-3" id="tsHero"></div>',
  '      <div class="card mt-3"><div class="row-title">分类占比</div><div class="flex items-center gap-4 mt-3" id="tsDonut"></div></div>',
  '      <div class="card mt-3"><div class="row-title">分类时长排行</div><div id="tsRank" class="mt-2 space-y-2"></div></div>',
  '      <div class="card mt-3"><div class="row-title">按日趋势</div><div id="tsDays" class="mt-3 flex items-end gap-1 h-24"></div></div>',
  '      <div class="mt-2 text-[10px] text-slate-400 text-center leading-5">数据源 = 时间块表 · 轴/块/日/周 与账本同一份 · 计时中按已耗时实时计入</div>',
  '    </section>',
  '',
  '    <!-- ===== P12d 二级：分类管理',
]));

/* ② 实算聚合 + 渲染 */
rep('fns', '/* —— 分类管理（V1.19 · 两级树 · 长按拖拽换父组/排序 · 添加分类页） —— */', L([
  "/* ================= 时间账本 L4（blocks 实算 · 本周/本月） ================= */",
  "let tsScope='w';",
  "const TS_HEX={工作:'#6366f1',学习:'#8b5cf6',运动:'#f59e0b',餐饮:'#fb923c',娱乐:'#f472b6',睡眠:'#3730a3',清洁:'#2dd4bf',其他:'#94a3b8',吃饭:'#fb923c',休息:'#b45309',路上:'#64748b'};",
  "function tsColor(c){return TS_HEX[c]||'#94a3b8'}",
  "function tsRange(){if(tsScope==='w'){const a=TODAY-((TODAY+1)%7);return {from:Math.max(1,a),to:Math.min(30,a+6)}}return {from:1,to:30}}",
  "function tsAgg(fr,to){const byCat={},byDay={};",
  " blocks.forEach(b=>{const d0=b.day||TODAY,e=bend(b);const parts=[[d0,Math.min(e,1439)]];if(e>1439)parts.push([d0+1,e-1440]);",
  "  parts.forEach(([d,end])=>{const mins=Math.max(0,end-b.s);if(!mins||d<fr||d>to)return;byCat[b.cat]=(byCat[b.cat]||0)+mins;byDay[d]=(byDay[d]||0)+mins})});",
  " return {byCat,byDay}}",
  "function tsHM(m){const h=Math.floor(m/60),r=m%60;return h?h+' 时 '+(r?r+' 分':''):r+' 分'}",
  "function tsSet(k){tsScope=k;renderTimeStats()}",
  "function tsDonutSvg(entries,total,size){const C=100;let off=0;",
  " return `<svg viewBox=\"0 0 42 42\" class=\"shrink-0 -rotate-90\" style=\"width:${size}px;height:${size}px\"><circle cx=\"21\" cy=\"21\" r=\"15.9\" fill=\"none\" stroke=\"#e2e8f0\" stroke-width=\"6\" class=\"dark:opacity-10\"/>`",
  "  +entries.map(([c,m])=>{const pct=total?m/total*100:0;const seg=`<circle cx=\"21\" cy=\"21\" r=\"15.9\" fill=\"none\" stroke=\"${tsColor(c)}\" stroke-width=\"6\" stroke-dasharray=\"${pct.toFixed(1)} ${(100-pct).toFixed(1)}\" stroke-dashoffset=\"${(-off).toFixed(1)}\"/>`;off+=pct;return seg}).join('')+'</svg>'}",
  "function renderTimeStats(){const hero=$('#tsHero');if(!hero)return;",
  " $('#tsScopeW').className=(tsScope==='w'?'seg-on':'')+' px-3 py-1 rounded-lg text-xs font-bold';",
  " $('#tsScopeM').className=(tsScope==='m'?'seg-on':'')+' px-3 py-1 rounded-lg text-xs font-bold';",
  " const {from,to}=tsRange();const {byCat,byDay}=tsAgg(from,to);",
  " const entries=Object.entries(byCat).sort((a,b)=>b[1]-a[1]);const total=entries.reduce((t,e)=>t+e[1],0);",
  " const ndays=to-from+1;const tm=timingBlk();",
  " $('#tsMeta').textContent='9/'+from+' - 9/'+to+' · '+(total?entries.length+' 个分类':'暂无数据');",
  " hero.innerHTML=`<div class=\"flex items-end justify-between\"><div><div class=\"text-[11px] opacity-80\">${tsScope==='w'?'本周':'本月'}总时长</div><div class=\"text-2xl font-extrabold leading-tight\">${tsHM(total)}</div></div>",
  "  <div class=\"text-right text-[11px] opacity-90\">日均 ${tsHM(Math.round(total/ndays))}<br>记录 ${blocks.filter(b=>(b.day||TODAY)>=from&&(b.day||TODAY)<=to).length} 段</div></div>",
  "  <div class=\"mt-2 flex items-center gap-2 text-[10px]\">${tm?`<span class=\"bg-white/20 rounded-full px-2 py-1\">● 计时中 · ${tm.cat} ${tsHM(Math.max(0,nowMin()-tm.s))}</span>`:'<span class=\"bg-white/15 rounded-full px-2 py-1\">无计时中事件</span>'}</div>`;",
  " const dn=$('#tsDonut');",
  " dn.innerHTML=total?tsDonutSvg(entries,total,96)+`<div class=\"text-xs space-y-1.5 flex-1\">`+entries.map(([c,m])=>`<div class=\"flex items-center gap-2\"><i class=\"dot\" style=\"background:${tsColor(c)}\"></i><span class=\"flex-1\">${c}</span><b>${Math.round(m/total*100)}%</b><span class=\"text-slate-400 text-[10px]\">${tsHM(m)}</span></div>`).join('')+`</div>`",
  "   :'<span class=\"text-xs text-slate-400\">该时段还没有时间块 · 去时间页记几段吧</span>';",
  " const mx=entries.length?entries[0][1]:1;",
  " $('#tsRank').innerHTML=entries.length?entries.map(([c,m])=>`<div><div class=\"flex justify-between text-[11px] mb-1\"><span><i class=\"dot\" style=\"background:${tsColor(c)}\"></i> ${c}</span><b>${tsHM(m)} · ${Math.round(m/total*100)}%</b></div><div class=\"h-2 rounded-full bg-slate-100 dark:bg-slate-800 overflow-hidden\"><div class=\"h-full rounded-full\" style=\"width:${(m/mx*100).toFixed(1)}%;background:${tsColor(c)}\"></div></div></div>`).join('')",
  "   :'<div class=\"text-xs text-slate-400\">暂无排行</div>';",
  " const dmax=Math.max(1,...Object.values(byDay));",
  " $('#tsDays').innerHTML=Array.from({length:ndays},(_,i)=>{const d=from+i,v=byDay[d]||0;",
  "   return `<div class=\"flex-1 flex flex-col items-center gap-1 justify-end h-full\"><span class=\"text-[8px] text-slate-400\">${v?Math.round(v/60*10)/10:''}</span><div class=\"w-full rounded-t-md ${d===TODAY?'bg-brand-500':'bg-brand-400/60'}\" style=\"height:${Math.max(2,Math.round(v/dmax*72))}px\"></div><span class=\"text-[8px] text-slate-400\">${d}</span></div>`}).join('');}",
  "function renderDashDist(){const el=$('#dashTimeDist');if(!el)return;",
  " const a=TODAY-((TODAY+1)%7),from=Math.max(1,a),to=Math.min(30,a+6);",
  " const {byCat}=tsAgg(from,to);const entries=Object.entries(byCat).sort((x,y)=>y[1]-x[1]).slice(0,6);const total=entries.reduce((t,e)=>t+e[1],0);",
  " el.innerHTML=total?`<div class=\"flex items-center gap-4 mt-3\">`+tsDonutSvg(entries,total,96)+`<div class=\"text-xs space-y-1.5 flex-1\">`+entries.slice(0,4).map(([c,m])=>`<div class=\"flex justify-between\"><span><i class=\"dot\" style=\"background:${tsColor(c)}\"></i>${c}</span><b>${Math.round(m/total*100)}%</b></div>`).join('')+`</div></div><div class=\"mt-2 text-[10px] text-slate-400\">合计 ${tsHM(total)} · 点卡片看时间账本</div>`",
  "   :'<div class=\"mt-2 text-xs text-slate-400\">本周还没有记录 · 点卡片看时间账本</div>'}",
  '',
  '/* —— 分类管理（V1.19 · 两级树 · 长按拖拽换父组/排序 · 添加分类页） —— */',
]));

/* ③ 仪表盘分布卡改实算容器 + 点击进账本 */
rep('dash-card', L([
  '      <div class="card mt-4">',
  '        <div class="row-title">本周时间分布</div>',
  '        <div class="flex items-center gap-4 mt-3">',
  '          <svg viewBox="0 0 42 42" class="w-24 h-24 shrink-0 -rotate-90">',
  '            <circle cx="21" cy="21" r="15.9" fill="none" stroke="#e2e8f0" stroke-width="6" class="dark:opacity-10"/>',
  '            <circle cx="21" cy="21" r="15.9" fill="none" stroke="#6366f1" stroke-width="6" stroke-dasharray="38 100" stroke-dashoffset="0"/>',
  '            <circle cx="21" cy="21" r="15.9" fill="none" stroke="#2dd4bf" stroke-width="6" stroke-dashoffset="-38" stroke-dasharray="24 100"/>',
  '            <circle cx="21" cy="21" r="15.9" fill="none" stroke="#f59e0b" stroke-width="6" stroke-dashoffset="-62" stroke-dasharray="18 100"/>',
  '            <circle cx="21" cy="21" r="15.9" fill="none" stroke="#fb7185" stroke-width="6" stroke-dashoffset="-80" stroke-dasharray="20 100"/>',
  '          </svg>',
  '          <div class="text-xs space-y-1.5 flex-1">',
  '            <div class="flex justify-between"><span><i class="dot bg-brand-500"></i>工作学习</span><b>38%</b></div>',
  '            <div class="flex justify-between"><span><i class="dot bg-mint"></i>睡眠休息</span><b>24%</b></div>',
  '            <div class="flex justify-between"><span><i class="dot bg-sun"></i>运动健康</span><b>18%</b></div>',
  '            <div class="flex justify-between"><span><i class="dot bg-peach"></i>娱乐休闲</span><b>20%</b></div>',
  '          </div>',
  '        </div>',
  '      </div>',
]), L([
  '      <button onclick="navTo(\'p-timeStats\')" class="card mt-4 w-full text-left active:scale-[.99] transition">',
  '        <div class="row-title">本周时间分布</div>',
  '        <div id="dashTimeDist"></div>',
  '      </button>',
]));

/* ④ 时间页顶栏加入「账本」入口（线性柱状图标） */
rep('entry',
  '          <button id="btnToday" class="hidden w-9 h-9',
  L([
  '          <button onclick="navTo(\'p-timeStats\')" class="w-9 h-9 rounded-full flex items-center justify-center active:bg-slate-200 dark:active:bg-slate-800" title="时间账本"><svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="1.8" viewBox="0 0 24 24"><path stroke-linecap="round" d="M4 20V6M10 20v-7M16 20V9M22 20H2"/></svg></button>',
  '          <button id="btnToday" class="hidden w-9 h-9',
  ]));

/* ⑤ 页面钩子 + 标题 + 渲染联动 */
rep('hook', "  $$('.navtab').forEach(b=>b.classList.toggle('on', b.dataset.p===p));",
  "  if(p==='p-timeStats')renderTimeStats();\n  $$('.navtab').forEach(b=>b.classList.toggle('on', b.dataset.p===p));");
rep('cal-hook', "function renderCal(){renderHeadDate();", "function renderCal(){renderDashDist();renderHeadDate();");
rep('title', "'p-sub-cats':['分类管理','两级分类 · 全局同源引用']",
  "'p-sub-cats':['分类管理','两级分类 · 全局同源引用'],'p-timeStats':['时间账本','L4 · 分类时长统计 · 本周/本月']");

fs.writeFileSync(P, s);
console.log('OK ' + R.length + ': ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
