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

/* tpNowBase：打开弹层时记录当前档，避免跨档导致 isNow 失效 */
rep('nowbase-decl', "let tpEdit=null,tpTiming=false;", "let tpEdit=null,tpTiming=false,tpNowBase=-1;");
rep('nowbase-open',
  "function openTimePick(d,h,m,editBlk){const isNow=h===undefined&&m===undefined;\n  tpEdit=editBlk||null;tpTiming=false;",
  "function openTimePick(d,h,m,editBlk){const isNow=h===undefined&&m===undefined;\n  tpEdit=editBlk||null;tpTiming=false;tpNowBase=isNow?now5():-1;");
rep('nowbase-add',
  " let s=tpMin('tpSh')*60+tpMin('tpSm');let e=tpEd();const isNow=sd===TODAY&&s===now5();",
  " let s=tpMin('tpSh')*60+tpMin('tpSm');let e=tpEd();const isNow=sd===TODAY&&s===tpNowBase;");

fs.writeFileSync(P, s);
console.log('OK ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
