// 影音游专版语法检查 · 与 bssyntax.js 同套流程但目标文件参数化
// 用法：node tools/mediasyntax.js [path]   默认 prototype/index-media.html
const fs = require('fs');
const vm = require('vm');
const P = process.argv[2] || 'prototype/index-media.html';
const H = fs.readFileSync(P, 'utf8');
const m = [...H.matchAll(/<script>([\s\S]*?)<\/script>/g)];
const body = m[m.length - 1][1];
fs.writeFileSync('tmp_md.js', body);
try { new vm.Script(body, { filename: 'inline.js' }); console.log('SYNTAX OK  ' + P + '  scripts=' + m.length + '  js=' + body.length); }
catch (e) { console.log('SYNTAX FAIL ' + e.message); const l = /inline\.js:(\d+)/.exec(e.stack || ''); if (l) console.log(body.split('\n')[+l[1] - 1].slice(0, 300)); process.exit(1); }
