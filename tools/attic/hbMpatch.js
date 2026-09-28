const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
let fails = 0;
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length);
}
rep('pend', " const ar=document.getElementById('hbAutoRow');if(ar)ar.innerHTML=auto.length?",
 " const pendN=book.reduce((a,h)=>a+(h.pend||[]).length,0);\n const ar=document.getElementById('hbAutoRow');if(ar)ar.innerHTML=(auto.length||pendN)?");
rep('pend2', "(auto.reduce((a,h)=>a+(h.pend||[]).length,0))", "(pendN)");
if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK') } catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED M');
