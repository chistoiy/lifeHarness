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

/* 1) 弹层加计时/编辑提示行 #tpHintEl */
rep('hint-el',
  '      <div class="mt-2 flex items-center gap-1.5 text-[10px] font-bold flex-wrap">时长',
  '      <div id="tpHintEl" class="mt-1.5 text-[10px] font-bold text-brand-500"></div>\n      <div class="mt-2 flex items-center gap-1.5 text-[10px] font-bold flex-wrap">时长');

/* 2) 迁移幂等守卫 */
rep('mig-guard',
  "function migrateEv152(){D.events.forEach",
  "function migrateEv152(){if(window._mig152)return;window._mig152=1;D.events.forEach");

fs.writeFileSync(P, s);
console.log('OK ' + R.join(', ') + ' | ' + size0 + ' -> ' + s.length);
