const fs = require('fs'), vm = require('vm');
const F = process.argv[2] || 'prototype/index_habitcheck.html';
const S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
const js = ms[ms.length - 1][1];
const pre = S.slice(0, ms[ms.length - 1].index).split('\n').length - 1;
try { new vm.Script(js); console.log('FULL PARSE OK js=' + js.length) }
catch (e) {
  console.log('FULL PARSE FAIL:', e.message);
  const m = /:(\d+)\n([\s\S]*?)\n\s*\^/.exec(e.stack || '');
  if (m) {
    const ln = +m[1], L2 = js.split('\n');
    for (let k = Math.max(0, ln - 4); k < Math.min(L2.length, ln + 2); k++)
      console.log((k + 1 + pre) + (k + 1 === ln ? ' >> ' : '    ') + L2[k].slice(0, 200));
  } else console.log((e.stack || '').split('\n').slice(0, 6).join('\n'));
}
