const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const key = 'const TS_HEX=';
const i1 = s.indexOf(key);
const i2 = s.indexOf(key, i1 + 1);
if (i1 < 0 || i2 < 0) { console.log('occurrences', i1, i2); process.exit(1); }
const endMark = 'function renderDashDist()';
const j = s.indexOf(endMark, i2);
if (j < 0) { console.log('no end mark'); process.exit(1); }
const removed = s.slice(i2, j);
if (!removed.includes('function tsRange') || !removed.includes('function renderTimeStats')) {
  console.log('unexpected old block content', removed.length); process.exit(1);
}
if (removed.includes('function renderDashDist')) { console.log('would delete live fn'); process.exit(1); }
s = s.slice(0, i2) + s.slice(j);
fs.writeFileSync(P, s);
console.log('removed stale block chars:', removed.length, '| size', size0, '->', s.length);
