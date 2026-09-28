const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const R = [];
function rep(name, a, b, cnt) {
  const n = s.split(a).length - 1;
  if (n !== (cnt || 1)) { console.error(name + ' count=' + n + ' found'); process.exit(1); }
  s = s.split(a).join(b);
  R.push(name);
}
/* 计时块显示结束=当前时刻（原对象只读投影） */
rep('bend',
  "function normB(b){if(b.tm&&b.day===TODAY)b.e=Math.max(b.s,nowMin());return b}",
  "function bend(b){return b.tm&&b.day===TODAY?Math.max(b.s,nowMin()):b.e}\nfunction normB(b){return b}");
rep('blockAt',
  "function blockAt(m){return dayBlocks(calDay).find(b=>m>=b.s&&m<b.e)}",
  "function blockAt(m){return dayBlocks(calDay).find(b=>m>=b.s&&m<bend(b))}");
rep('blocksAt',
  "function blocksAt(m,d){return dayBlocks(d===undefined?TODAY:d).filter(b=>m>=b.s&&m<b.e);}",
  "function blocksAt(m,d){return dayBlocks(d===undefined?TODAY:d).filter(b=>m>=b.s&&m<bend(b));}");
/* 轴视图普通/完成卡与提示 */
rep('axis-sub',
  "const sub=b.dn?`✓ 已完成 · ${fmt(b.s)} – ${fmt(b.e)} · 实际 ${b.e-b.s} 分钟 · 已回填 L1 · 入时间账本 L4 · 点卡片仍可修改/删除`:`${b.cat} · ${fmt(b.s)} – ${fmt(b.e)} · ${b.e-b.s} 分钟 · 点卡片修改起止/类型`;",
  "const sub=b.dn?`✓ 已完成 · ${fmt(b.s)} – ${fmt(bend(b))} · 实际 ${bend(b)-b.s} 分钟 · 已回填 L1 · 入时间账本 L4 · 点卡片仍可修改/删除`:`${b.cat} · ${fmt(b.s)} – ${fmt(bend(b))} · ${bend(b)-b.s} 分钟 · 点卡片修改起止/类型`;");
/* 块视图格子提示 */
rep('grid-tip',
  "    const tip=b?(b.tm?'●计时中 · ':(b.dn?'✓完成 · ':''))+(b.note||b.cat)+' '+fmt(b.s)+'-'+fmt(b.e)+(b.note&&b.cat!==b.note?' · '+b.cat:''):'空格 '+fmt(m);",
  "    const tip=b?(b.tm?'●计时中 · ':(b.dn?'✓完成 · ':''))+(b.note||b.cat)+' '+fmt(b.s)+'-'+fmt(bend(b))+(b.note&&b.cat!==b.note?' · '+b.cat:''):'空格 '+fmt(m);");
/* 日视图/周视图不再依赖 b.e 的计时推进：周视图格子按 bend 覆盖（blocksAt 已修） */
fs.writeFileSync(P, s);
console.log('OK ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
