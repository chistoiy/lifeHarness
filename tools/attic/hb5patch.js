const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
let fails = 0;
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length);
}
rep('hsrec', " book.forEach(h=>{const t=hbTot(h,dim);cnt+=t.cnt;val+=t.val;recN+=hbRecN(h,dim)});",
 " book.forEach(h=>{const t=hbTot(h,dim);cnt+=t.cnt;val+=t.val;if(hbHasVal(h)&&hbRecN(h,dim))recN++});");
rep('hscards', "['数值记录',recN,'条']", "['在记数值',recN,'个']");
rep('hssub', "' 个跟踪中习惯 · 打卡 '+cnt+' 次 · 数值记录 '+recN+' 条 · 负向触发 '",
 "' 个跟踪中习惯 · 打卡 '+cnt+' 次 · 在记数值 '+recN+' 个 · 负向触发 '");
rep('fab', "'p-habitDetail':{ico:'＋',act:()=>heOpen(hbCur)}", "'p-habitDetail':{ico:'✎',act:()=>heOpen(hbCur)}");
rep('sub', "'p-habits':['习惯','今日打卡 · 正负向双模式']", "'p-habits':['习惯','今日打卡 · 数值记录 · 组打卡']");
if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK') } catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
