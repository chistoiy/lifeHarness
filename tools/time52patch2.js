const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const R = [];
function rep(name, a, b) {
  const i = s.indexOf(a);
  if (i < 0) { console.error('MISS ' + name); process.exit(1); }
  if (s.indexOf(a, i + 1) >= 0) { console.error('DUP ' + name); process.exit(1); }
  s = s.slice(0, i) + b + s.slice(i + a.length);
  R.push(name);
}

/* 1) closeSheet 空守卫（sheetEventDetail HTML 已删除） */
rep('closeSheet-guard',
  "function closeSheet(id){ const s=$('#'+id); s.classList.remove('sheet-open'); s.classList.add('hidden'); }",
  "function closeSheet(id){ const s=$('#'+id); if(!s)return; s.classList.remove('sheet-open'); s.classList.add('hidden'); }");

/* 2) renderGrid 格子色/提示改新字段 */
rep('grid-cls',
  "    const cls=b?(b.done!==undefined?'bg-emerald-400':b.ev!==undefined?'bg-brand-500/80':(b.live?'animate-pulse ':'')+CATS[b.cat]):'bg-slate-100 dark:bg-slate-800';",
  "    const cls=b?(b.dn?'bg-emerald-400':(b.tm?'animate-pulse bg-rose-500 ':'')+(b.tm?'':CATS[b.cat])):'bg-slate-100 dark:bg-slate-800';");
rep('grid-tip',
  "    const tip=b?(b.ev!==undefined?'⚡事件 · ':b.done!==undefined?'✓完成 · ':(b.live?'●进行中 · ':''))+b.cat+' '+fmt(b.s)+'-'+fmt(b.e)+(b.note?' · '+b.note:''):'空格 '+fmt(m);",
  "    const tip=b?(b.tm?'●计时中 · ':(b.dn?'✓完成 · ':''))+(b.note||b.cat)+' '+fmt(b.s)+'-'+fmt(b.e)+(b.note&&b.cat!==b.note?' · '+b.cat:''):'空格 '+fmt(m);");

/* 3) 旧详情函数文案去掉已退役弹层引用 */
rep('detail-toast',
  "   <div class=\"mt-2 text-[10px] text-slate-400 text-center\">已完成事件同样可查看 / 编辑 / 删除 · 轴/块/日/日程/周五视图同步</div>`;",
  "   <div class=\"mt-2 text-[10px] text-slate-400 text-center\">已完成事件同样可查看 / 编辑 / 删除 · 轴/块/日/周五视图同步</div>`;");

/* 4) tpSave：起始被改则不再是计时中 */
rep('save-tm',
  " if(b.tm&&e!==nowMin())b.tm=0;",
  " if(b.tm&&(e!==nowMin()||s!==b.s))b.tm=0;");

fs.writeFileSync(P, s);
console.log('OK ' + R.length + ': ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
