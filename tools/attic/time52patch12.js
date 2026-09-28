const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const a = '  .tp-subgrid{background:rgb(241 245 249 / .8);border-radius:12px;padding:6px}';
const b = '  .tp-subgrid{display:flex;flex-wrap:wrap;gap:4px;background:rgb(241 245 249 / .8);border-radius:12px;padding:6px;max-height:82px;overflow-y:auto}';
if (s.split(a).length - 1 !== 1) { console.log('anchor issue'); process.exit(1); }
s = s.replace(a, b);
s = s.replace('  .tp-catgrid .tag-chip{padding:5px 2px;font-size:10px;justify-content:center;gap:3px;min-width:0}',
  '  .tp-catgrid .tag-chip{padding:5px 2px;font-size:10px;justify-content:center;gap:3px;min-width:0}\n  .tp-subgrid .tag-chip{padding:5px 7px;font-size:10px;gap:3px;flex:none}');
fs.writeFileSync(P, s);
console.log('subgrid tuned');
