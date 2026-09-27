const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const a = '<span class="flex-1 min-w-0 truncate">${fmt(b.s)} ${b.note||b.cat} ${lbl}</span>';
const b = '<span class="flex-1 min-w-0 truncate">${fmt(b.s)} ${b.tailOf?\'↩ \':\'\'}${b.note||b.cat} ${lbl}</span>';
if (s.split(a).length - 1 !== 1) { console.log('anchor count', s.split(a).length - 1); process.exit(1); }
fs.writeFileSync(P, s.split(a).join(b));
console.log('day tail marker added');

let t = fs.readFileSync('tools/time52check.js', 'utf8');
const oa = "const dayTxt=$('#calDayHourView').textContent;";
const ob = "const dayTxt=$('#calDayHourView').textContent;switchCalView('axis');const axTxt=$('#timeAxis').textContent;switchCalView('day');";
if (t.split(oa).length - 1 !== 1) { console.log('test anchor', t.split(oa).length - 1); process.exit(1); }
t = t.split(oa).join(ob);
t = t.split("tailLabel:/续昨日/.test(dayTxt)").join("tailLabel:/↩/.test(dayTxt)&&/续昨日/.test(axTxt)");
fs.writeFileSync('tools/time52check.js', t);
console.log('t26 updated');
