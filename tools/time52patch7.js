const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const R = [];
function rep(name, a, b, cnt) {
  const n = s.split(a).length - 1;
  if (n !== (cnt || 1)) { console.error(name + ' count=' + n); process.exit(1); }
  s = s.split(a).join(b);
  R.push(name + (cnt && cnt > 1 ? 'x' + cnt : ''));
}

/* TP_DAYS 扩为 9 月全月 30 天 */
rep('tpdays',
  "const TP_DAYS=['09/13','09/14','09/15','09/16','09/17','09/18','09/19','09/20'];",
  "const TP_DAYS=Array.from({length:30},(_,i)=>'09/'+String(i+1).padStart(2,'0'));");
/* 索引换算 sd-13 → sd-1（openTimePick 内两处） */
rep('di', "const di=Math.max(0,Math.min(7,sd-13));", "const di=Math.max(0,Math.min(29,sd-1));");
rep('ed', "wReg('tpEd',TP_DAYS,di,tpUpd);", "wReg('tpEd',TP_DAYS,di,tpUpd);");
/* tpNow/tpAdd 等取日：slice(3) 对 '09/28' 仍成立；tpNowBase 档位索引 19-13 → 18 */
rep('nowbase', "tpSetWheel('tpSd',TODAY-13);", "tpSetWheel('tpSd',TODAY-1);");
/* 块视图选区「弹层精细」入口按当前日 */
rep('fine', "openTimePick(19,${Math.floor(cellMin(a)/60)},${cellMin(a)%60})", "openTimePick(${calDay},${Math.floor(cellMin(a)/60)},${cellMin(a)%60})");

fs.writeFileSync(P, s);
console.log('OK ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
