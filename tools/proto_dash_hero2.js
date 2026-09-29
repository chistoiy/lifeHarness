/* R14-14 补丁②：「场安排」与今日安排列表同源 blocks（V1.52 起 D.events 已被 migrateEv152 清空，
   问候卡若读 D.events 会永远显示 0，而今日安排卡也是空的）。
   用法：node tools/proto_dash_hero2.js */
const fs = require('fs');
const F = 'prototype/index.html';
let s = fs.readFileSync(F, 'utf8');
const before = s.length;
let hits = 0;
function rep(old, neu, label) {
  const n = s.split(old).length - 1;
  if (n !== 1) { console.error('!! [' + label + '] 命中 ' + n + ' 次（要求 1 次）：' + old.slice(0, 70)); process.exit(1); }
  s = s.replace(old, neu); hits++;
}

/* ① 今日安排列表改由 blocks 渲染（原来映射 D.events，迁移后恒空） */
rep(
  `  $('#dashEvents').innerHTML = D.events.map(e=>\`<div class="flex items-center gap-3 rounded-2xl bg-slate-50 dark:bg-slate-800/60 p-3">
    <span class="w-1 self-stretch rounded-full \${e.c}"></span>
    <div class="flex-1 text-sm font-semibold">\${e.t}</div><div class="text-[11px] text-slate-400 font-mono">\${e.tm}-\${e.e}</div></div>\`).join('');`,
  `  /* R14-14：今日安排与问候卡「N 场安排」同源，统一由 blocks 渲染（见 renderHero） */`,
  'dashevents'
);

/* ② renderHero 内：场安排＝今日 blocks，并渲染安排列表 */
rep(
  "  set('#dashTodoN',tt.length); set('#dashPlanN',D.events.length);",
  `  const plans=blocks.filter(b=>(b.day||TODAY)===TODAY).slice().sort((a,b)=>a.s-b.s);
  const pe=$('#dashEvents');
  if(pe)pe.innerHTML=plans.map(b=>\`<div class="flex items-center gap-3 rounded-2xl bg-slate-50 dark:bg-slate-800/60 p-3">
    <span class="w-1 self-stretch rounded-full \${b.c||'bg-brand-500'}"></span>
    <div class="flex-1 text-sm font-semibold \${b.dn?'line-through opacity-60':''}">\${b.note||b.cat}</div><div class="text-[11px] text-slate-400 font-mono">\${b.tm?'计时中':fmt(b.s)+'-'+fmt(b.e)}</div></div>\`).join('');
  set('#dashTodoN',tt.length); set('#dashPlanN',plans.length);`,
  'hero-plans'
);

/* ③ 块任一变更（增删改/撤销/计时/拆分合并）即时回显 */
rep('function renderCal(){', 'function renderCal(){ renderHero();', 'hook-cal');

fs.writeFileSync(F, s);
console.log('命中 ' + hits + ' 处 · 体积 ' + before + ' → ' + s.length + '（' + (s.length - before) + '）');
