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
rep('heat', ` const book=hbScopeBook(),W=17,today=new Date(2026,8,19);
 const lead=(today.getDay()+6)%7,cells=W*7;
 const col=[];for(let c=0;c<cells+lead;c++){const back=c-(cells+lead-1);col.push(back)}
 let html='';
 for(let w=0;w<W;w++){html+='<div class="flex flex-col gap-[3px]">';
  for(let d=0;d<7;d++){const idx=w*7+d,back=idx-(cells+lead-1);
   if(back>6&&back<0||back<0){html+='<span class="w-[11px] h-[11px]"></span>';continue}
   if(back>140){html+='<span class="w-[11px] h-[11px]"></span>';continue}`,
 ` const book=hbScopeBook(),W=17,today=new Date(2026,8,19);
 const lead=(today.getDay()+6)%7;
 let html='';
 for(let w=0;w<W;w++){html+='<div class="flex flex-col gap-[3px]">';
  for(let d=0;d<7;d++){const back=lead-d+(W-1-w)*7;
   if(back<0||back>140){html+='<span class="w-[11px] h-[11px]"></span>';continue}`);
if (fails) { console.log('FAILS', fails); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK') } catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
