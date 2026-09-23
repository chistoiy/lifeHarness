const fs = require('fs'), vm = require('vm');
const F = process.argv[2] || 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
const m = ms[ms.length - 1];
const js = m[1];
const pre = S.slice(0, m.index).split('\n').length - 1;
const L = js.split('\n');
for (let n = 1; n <= L.length; n++) {
  try { new vm.Script(L.slice(0, n).join('\n')) }
  catch (e) {
    if (/Unexpected end|missing \}/.test(e.message)) continue;
    console.log('FILE LINE', n + pre, '|', e.message.slice(0, 70));
    for (let k = Math.max(0, n - 3); k < Math.min(L.length, n + 1); k++) console.log(k + 1 + pre, L[k].slice(0, 220));
    process.exit(1);
  }
}
console.log('SYNTAX OK js=' + js.length);
