const fs = require('fs');
const vm = require('vm');
const P = 'prototype/index-bookshelf.html';
const H = fs.readFileSync(P, 'utf8');
const m = [...H.matchAll(/<script>([\s\S]*?)<\/script>/g)];
let fail = 0;
m.forEach((x, i) => {
  const body = x[1];
  try { new vm.Script(body, { filename: 'inline' + i + '.js' }); console.log('SYNTAX OK  block=' + i + ' js=' + body.length); }
  catch (e) { fail++; console.log('SYNTAX FAIL block=' + i + ' ' + e.message); const l = new RegExp('inline' + i + '\\.js:(\\d+)').exec(e.stack || ''); if (l) console.log(body.split('\n')[+l[1] - 1].slice(0, 300)); }
});
if (!m.length) { console.log('NO SCRIPT BLOCKS'); process.exit(1); }
process.exit(fail ? 1 : 0);
