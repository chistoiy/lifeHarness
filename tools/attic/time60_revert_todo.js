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
// 待办时间滚轮回退 5 分档（Flutter 侧 lib/core/widgets/wheel_time.dart 仍为 5 分档，
// 时间模块事件弹层保持 1 分档；避免原型与实现两源不一致，待办统一另立批次）。
rep('twmins',
  "const TW_MINS=Array.from({length:60},(_,i)=>String(i).padStart(2,'0'));",
  "const TW_MINS=Array.from({length:12},(_,i)=>String(i*5).padStart(2,'0'));");
rep('curhm',
  "function curHM(){const n=new Date();return {h:n.getHours(),m:n.getMinutes()}}",
  "function curHM(){const n=new Date();return {h:n.getHours(),m:Math.floor(n.getMinutes()/5)*5}}");
rep('tkpoint', "if(m==='point'){wReg('tkPh',TW_HRS,t.h);wReg('tkPm',TW_MINS,t.m)}",
  "if(m==='point'){wReg('tkPh',TW_HRS,t.h);wReg('tkPm',TW_MINS,Math.floor(t.m/5))}");
rep('tkrange',
  "if(m==='range'){wReg('tkSh',TW_HRS,t.h);wReg('tkSm',TW_MINS,t.m);wReg('tkEh',TW_HRS,t.h);wReg('tkEm',TW_MINS,t.m)}}",
  "if(m==='range'){wReg('tkSh',TW_HRS,t.h);wReg('tkSm',TW_MINS,Math.floor(t.m/5));wReg('tkEh',TW_HRS,t.h);wReg('tkEm',TW_MINS,Math.floor(t.m/5))}}");
fs.writeFileSync(P, s);
console.log('OK ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
