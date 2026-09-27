const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const a = s.indexOf("let tsMode='w'");
const b = s.indexOf('/* —— 分类管理', a);
if (a < 0 || b < 0) { console.log('bounds', a, b); process.exit(1); }
const seg = s.slice(a, b);
const n = seg.split('tsMode').length - 1;
if (n < 6) { console.log('unexpected count', n); process.exit(1); }
s = s.slice(0, a) + seg.split('tsMode').join('tsSpan') + s.slice(b);
fs.writeFileSync(P, s);
console.log('renamed tsMode->tsSpan x' + n + ' | ' + size0 + ' -> ' + s.length);
