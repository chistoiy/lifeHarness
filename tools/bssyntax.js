const fs = require('fs');
const vm = require('vm');
const P = 'prototype/index-bookshelf.html';
const H = fs.readFileSync(P, 'utf8');
const m = [...H.matchAll(/<script>([\s\S]*?)<\/script>/g)];
const body = m[m.length - 1][1];
fs.writeFileSync('tmp_bs.js', body);
try { new vm.Script(body, { filename: 'inline.js' }); console.log('SYNTAX OK  scripts=' + m.length + ' js=' + body.length); }
catch (e) { console.log('SYNTAX FAIL ' + e.message); const l = /inline\.js:(\d+)/.exec(e.stack || ''); if (l) console.log(body.split('\n')[+l[1] - 1].slice(0, 300)); process.exit(1); }
