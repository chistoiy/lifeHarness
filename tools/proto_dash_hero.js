/* R14-14 补丁：今日问候卡 + 物品总览去写死、全实算（原型先行·零行为改动以外只动展示口径）
   用法：node tools/proto_dash_hero.js
   护栏：每处替换断言命中 1 次；改完校验体积与结构。 */
const fs = require('fs');
const F = 'prototype/index.html';
let s = fs.readFileSync(F, 'utf8');
const before = s.length;
let hits = 0;
function rep(old, neu, label) {
  const n = s.split(old).length - 1;
  if (n !== 1) {
    console.error('!! [' + label + '] 命中 ' + n + ' 次（要求 1 次）：' + old.slice(0, 70));
    process.exit(1);
  }
  s = s.replace(old, neu);
  hits++;
}
function repRe(re, neu, label) {
  const m = s.match(re);
  if (!m || m.length !== 1) {
    console.error('!! [' + label + '] 正则命中 ' + (m ? m.length : 0) + ' 次（要求 1 次）');
    process.exit(1);
  }
  s = s.replace(re, neu);
  hits++;
}

/* ① 问候语去 emoji（UI 禁 emoji 口径） */
rep('早上好，CHIST ☀️</div>', '早上好，CHIST</div>', 'greet-static');
rep("g.textContent=g.dataset.hi+p.name+' ☀️';", 'g.textContent=g.dataset.hi+p.name;', 'greet-js');

/* ② 标题行「N 个待办 · M 场安排」挂 id */
rep(
  '今天有 <span class="text-3xl">4</span> 个待办 · <span class="text-3xl">2</span> 场安排',
  '今天有 <span id="dashTodoN" class="text-3xl">4</span> 个待办 · <span id="dashPlanN" class="text-3xl">2</span> 场安排',
  'hero-title'
);

/* ③ 象限洞察行挂 id */
rep(
  '</span> 本周 62% 精力在「重要」象限，状态不错',
  '</span> <span id="dashInsight">本周 62% 精力在「重要」象限，状态不错</span>',
  'hero-insight'
);

/* ④ 完成环三件套挂 id */
rep(
  '<circle cx="18" cy="18" r="15" fill="none" stroke="#fff" stroke-width="5" stroke-dasharray="60 100" stroke-linecap="round"/>',
  '<circle id="dashRing" cx="18" cy="18" r="15" fill="none" stroke="#fff" stroke-width="5" stroke-dasharray="60 100" stroke-linecap="round"/>',
  'hero-ring'
);
rep(
  '<span class="absolute inset-0 flex items-center justify-center text-[10px] font-bold">60%</span>',
  '<span id="dashRingPct" class="absolute inset-0 flex items-center justify-center text-[10px] font-bold">60%</span>',
  'hero-ring-pct'
);
rep(
  '<div class="text-xs leading-4">3/5<br>已完成</div>',
  '<div id="dashRingLine" class="text-xs leading-4">3/5<br>已完成</div>',
  'hero-ring-line'
);

/* ⑤ 持有成本两行挂 id */
rep(
  '<div class="text-xl font-extrabold mt-1">¥ 47.2<span class="text-xs font-medium opacity-80">/天</span></div>',
  '<div class="text-xl font-extrabold mt-1">¥ <span id="dashCost">47.20</span><span class="text-xs font-medium opacity-80">/天</span></div>',
  'hero-cost'
);
rep(
  '<div class="text-[10px] opacity-70">12 件物品计费中</div>',
  '<div class="text-[10px] opacity-70"><span id="dashCostN">12</span> 件物品计费中</div>',
  'hero-cost-n'
);

/* ⑥ 教学性说明文案删除（R14-8 口径：只留功能标签与状态提示） */
repRe(
  /\n\s*<div class="mt-3 flex items-center justify-between text-\[10px\] text-white\/75">\s*<span>长按任意卡片可编排顺序<\/span>\s*<\/div>/,
  '',
  'hero-teaching-line'
);

/* ⑦ 物品页总览与问候卡同源（否则两页数字互相打脸） */
rep(
  '<div class="text-3xl font-extrabold mt-1 text-mint">¥ 47.<span class="text-xl">20</span><span class="text-sm font-bold text-slate-400">/天</span></div>',
  '<div class="text-3xl font-extrabold mt-1 text-mint">¥ <span id="itCost">47.20</span><span class="text-sm font-bold text-slate-400">/天</span></div>',
  'items-cost'
);
rep(
  '<div class="mt-2 flex gap-4 text-[11px] text-slate-400"><span>使用中 <b class="text-white">12</b></span><span>闲置 <b class="text-white">2</b></span><span>已回收 <b class="text-white">3</b></span><span>已报废 <b class="text-white">1</b></span></div>',
  '<div class="mt-2 flex gap-4 text-[11px] text-slate-400"><span>使用中 <b id="itUse" class="text-white">12</b></span><span>闲置 <b id="itIdle" class="text-white">2</b></span><span>已回收 <b id="itRec" class="text-white">3</b></span><span>已报废 <b id="itScrap" class="text-white">1</b></span></div>',
  'items-counts'
);

/* ⑧ renderHero：单一实算出口（今日待办 / 场安排 / 象限精力 / 完成环 / 持有成本） */
rep(
  'function openProfileEdit(){',
  `/* R14-14：问候卡与物品总览同源实算——待办/日程/物品三处数据一变即回显，无写死数字。
   口径：今日待办=due 以「今天」开头；场安排=当日 events 条数；精力占比=未完成待办落在
   重要两象限（q0 重要且紧急 / q1 重要不紧急）的比例；持有成本=计费中物品的直线法日均合计。 */
const dashToday=()=>D.todos.filter(t=>/^今天/.test(t.due));
function renderHero(){
  const pc=(a,b)=>b?Math.round(a/b*100):0;
  const set=(id,v,html)=>{const e=$(id); if(e){ html?(e.innerHTML=v):(e.textContent=v); }};
  const tt=dashToday(), dn=tt.filter(t=>t.done).length;
  set('#dashTodoN',tt.length); set('#dashPlanN',D.events.length);
  const und=D.todos.filter(t=>!t.done), ip=pc(und.filter(t=>t.q===0||t.q===1).length,und.length);
  set('#dashInsight','本周 '+ip+'% 精力在「重要」象限，'+(ip>=60?'状态不错':ip>=40?'还能更聚焦':'紧急事偏多'));
  const p=pc(dn,tt.length);
  const ring=$('#dashRing'); if(ring)ring.setAttribute('stroke-dasharray',p+' 100');
  set('#dashRingPct',p+'%'); set('#dashRingLine',dn+'/'+tt.length+'<br>已完成',true);
  const live=D.items.filter(it=>it.calc), cost=live.reduce((a,it)=>a+costOf(it),0);
  set('#dashCost',cost.toFixed(2)); set('#dashCostN',live.length);
  set('#itCost',cost.toFixed(2));
  set('#itUse',D.items.filter(it=>it.st==='使用中').length);
  set('#itIdle',D.items.filter(it=>it.st==='闲置').length);
  set('#itRec',D.items.filter(it=>/^已回收/.test(it.st)).length);
  set('#itScrap',D.items.filter(it=>it.st==='已报废').length);
}
function openProfileEdit(){`,
  'renderHero'
);

/* ⑨ 挂钩：待办/物品任一渲染即回显（renderTodos 覆盖增删改勾拖拽，renderItems 覆盖物品侧） */
rep('function renderTodos(){', 'function renderTodos(){ renderHero();', 'hook-todos');
rep('function renderItems(){', 'function renderItems(){ renderHero();', 'hook-items');

/* ⑩ 待办筛选 chip「今天 N」与问候卡同一谓词 */
rep(
  "D.todoChips=D.todoChips.map(c=>c.replace(/已完成 \\d+/,'已完成 '+statDone()));",
  "D.todoChips=D.todoChips.map(c=>c.replace(/已完成 \\d+/,'已完成 '+statDone()).replace(/今天 \\d+/,'今天 '+dashToday().length));",
  'chip-today'
);

fs.writeFileSync(F, s);
const after = s.length;
console.log(
  '命中 ' + hits + ' 处 · 体积 ' + before + ' → ' + after + '（' + (after - before >= 0 ? '+' : '') + (after - before) + '）'
);
