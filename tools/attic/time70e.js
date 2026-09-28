const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const bad = 'return `<div class="flex-1 flex flex-col justify-end items-center gap-0.5" title="9月${d}日';
const good = 'return `<div class="flex-1 h-full flex flex-col justify-end items-center gap-0.5" title="9月${d}日';
const n = s.split(bad).length - 1;
if (n !== 1) { console.log('anchor count', n); process.exit(1); }
fs.writeFileSync(P, s.split(bad).join(good));
console.log('stack bar height fixed');
