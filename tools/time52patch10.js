/* V1.52 第三轮：时间滚轮改 1 分钟粒度（事件弹层 + 待办时间三态）· 循环滚动口径确认 */
const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const R = [];
function rep(name, a, b, cnt) {
  const n = s.split(a).length - 1;
  if (n !== (cnt || 1)) { console.error('MISS/DUP ' + name + ' count=' + n); process.exit(1); }
  s = s.split(a).join(b);
  R.push(name);
}

/* 1) 分钟档 5→1 分 */
rep('tpmins',
  "const TP_MINS=Array.from({length:12},(_,i)=>String(i*5).padStart(2,'0'));",
  "const TP_MINS=Array.from({length:60},(_,i)=>String(i).padStart(2,'0'));");
rep('twmins',
  "const TW_MINS=Array.from({length:12},(_,i)=>String(i*5).padStart(2,'0'));",
  "const TW_MINS=Array.from({length:60},(_,i)=>String(i).padStart(2,'0'));");

/* 2) 去掉 5 分档取整函数，改用真实分钟 */
rep('now5-del',
  "const nowMin=()=>{const d=new Date();return d.getHours()*60+d.getMinutes()};\nconst now5=()=>Math.floor(nowMin()/5)*5;",
  "const nowMin=()=>{const d=new Date();return d.getHours()*60+d.getMinutes()};");
rep('nowbase', "tpNowBase=isNow?now5():-1;", "tpNowBase=isNow?nowMin():-1;");
rep('s0', "let s0=bl?bl.s:(sd===TODAY&&isNow?now5():((h||0)*60));", "let s0=bl?bl.s:(sd===TODAY&&isNow?nowMin():((h||0)*60));");
rep('save-tm', " if(b.tm&&s===b.s&&e===Math.floor(nowMin()/5)*5){e=nowMin()}", " if(b.tm&&s===b.s&&e===nowMin()){e=nowMin()}");

/* 3) 滚轮索引换算改 1 分制 */
rep('idx',
  "wReg('tpSd',TP_DAYS,di,tpUpd);wReg('tpSh',TP_HRS,Math.floor(s0/60),tpUpd);wReg('tpSm',TP_MINS,Math.floor(s0%60/5),tpUpd);\n  wReg('tpEd',TP_DAYS,di,tpUpd);wReg('tpEh',TP_HRS,Math.floor(e0/60),tpUpd);wReg('tpEm',TP_MINS,Math.floor(e0%60/5),tpUpd);",
  "wReg('tpSd',TP_DAYS,di,tpUpd);wReg('tpSh',TP_HRS,Math.floor(s0/60),tpUpd);wReg('tpSm',TP_MINS,s0%60,tpUpd);\n  wReg('tpEd',TP_DAYS,di,tpUpd);wReg('tpEh',TP_HRS,Math.floor(e0/60),tpUpd);wReg('tpEm',TP_MINS,e0%60,tpUpd);");
rep('tpnow',
  "function tpNow(){const n=nowMin();tpSetWheel('tpSd',TODAY-1);tpSetWheel('tpSh',Math.floor(n/60));tpSetWheel('tpSm',Math.floor(n%60/5));\n  tpSetWheel('tpEd',TODAY-13);tpSetWheel('tpEh',Math.floor(n/60));tpSetWheel('tpEm',Math.floor(n%60/5));tpUpd()}",
  "function tpNow(){const n=nowMin();tpSetWheel('tpSd',TODAY-1);tpSetWheel('tpSh',Math.floor(n/60));tpSetWheel('tpSm',n%60);\n  tpSetWheel('tpEd',TODAY-1);tpSetWheel('tpEh',Math.floor(n/60));tpSetWheel('tpEm',n%60);tpUpd()}");
rep('tpdur',
  "WHEELS.tpEh.i=Math.floor(e/60)%24;WHEELS.tpEm.i=Math.min(11,Math.floor((e%60)/5));renderW('tpEh');renderW('tpEm');tpUpd()}",
  "WHEELS.tpEh.i=Math.floor(e/60)%24;WHEELS.tpEm.i=e%60;renderW('tpEh');renderW('tpEm');tpUpd()}");

/* 4) 待办时间三态同步 1 分制 */
rep('curhm',
  "function curHM(){const n=new Date();return {h:n.getHours(),m:Math.floor(n.getMinutes()/5)*5}}",
  "function curHM(){const n=new Date();return {h:n.getHours(),m:n.getMinutes()}}");
rep('tkpoint', "if(m==='point'){wReg('tkPh',TW_HRS,t.h);wReg('tkPm',TW_MINS,Math.floor(t.m/5))}",
  "if(m==='point'){wReg('tkPh',TW_HRS,t.h);wReg('tkPm',TW_MINS,t.m)}");
rep('tkrange',
  "if(m==='range'){wReg('tkSh',TW_HRS,t.h);wReg('tkSm',TW_MINS,Math.floor(t.m/5));wReg('tkEh',TW_HRS,t.h);wReg('tkEm',TW_MINS,Math.floor(t.m/5))}}",
  "if(m==='range'){wReg('tkSh',TW_HRS,t.h);wReg('tkSm',TW_MINS,t.m);wReg('tkEh',TW_HRS,t.h);wReg('tkEm',TW_MINS,t.m)}}");

/* 5) 文案：5 分一档 → 1 分一档 · 循环 */
rep('cap', '      <div class="mt-1 text-[10px] text-slate-400 text-center">5 分一档</div>',
  '      <div class="mt-1 text-[10px] text-slate-400 text-center">1 分一档 · 滚轮循环</div>');

/* 6) 循环缓冲：分钟 60 项时保证上下各可滑 3 圈 */
rep('rep',
  "if(!w._bx||!w._bx.isConnected){const rep=Math.max(6,Math.ceil(120/n));let h='<div style=\"height:32px\"></div>';",
  "if(!w._bx||!w._bx.isConnected){const rep=Math.max(4,Math.ceil(180/n));let h='<div style=\"height:32px\"></div>';");

fs.writeFileSync(P, s);
console.log('OK ' + R.length + ': ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
