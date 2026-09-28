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
function repOnce(name, a, b) {
  const n = s.split(a).length - 1;
  if (n !== 1) { console.error(name + ' count=' + n); process.exit(1); }
  rep(name, a, b);
}

/* 滚轮 5 分一档 · 当前时刻按档取整，保证 isNow 判定可命中 */
repOnce('now5-def',
  "const nowMin=()=>{const d=new Date();return d.getHours()*60+d.getMinutes()};",
  "const nowMin=()=>{const d=new Date();return d.getHours()*60+d.getMinutes()};\nconst now5=()=>Math.floor(nowMin()/5)*5;");
repOnce('now5-open',
  "  let s0=bl?bl.s:(sd===TODAY&&isNow?nowMin():((h||0)*60));",
  "  let s0=bl?bl.s:(sd===TODAY&&isNow?now5():((h||0)*60));");
repOnce('now5-add',
  " let s=tpMin('tpSh')*60+tpMin('tpSm');let e=tpEd();const isNow=sd===TODAY&&s===nowMin();",
  " let s=tpMin('tpSh')*60+tpMin('tpSm');let e=tpEd();const isNow=sd===TODAY&&s===now5();");
/* 编辑保存：仅改分类/备注时保持计时；结束时间取真实当前分钟 */
repOnce('save-tm2',
 " if(e<=s)e=s+5;\n if(b.tm&&(e!==nowMin()||s!==b.s))b.tm=0;",
 " if(b.tm&&s===b.s&&e===Math.floor(nowMin()/5)*5){e=nowMin()}\n if(e<=s)e=b.tm?Math.max(s,nowMin()):s+5;\n if(b.tm&&(e!==nowMin()||s!==b.s))b.tm=0;");

fs.writeFileSync(P, s);
console.log('OK ' + R.length + ': ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
