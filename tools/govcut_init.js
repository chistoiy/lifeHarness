// govcut_init.js · 从专版 init 调用链摘除指定死调用：node tools/govcut_init.js <文件名> <调用1,调用2,...>
// 护栏：每调用在 init 行命中恰 1 次；init 行=含 `);`≥10 的最长行；摘除后行数报告。
const fs = require('fs');
const [f, list] = process.argv.slice(2);
if (!f || !list) { console.log('用法: node tools/govcut_init.js <文件> <a(),b()()>'); process.exit(2); }
const F = 'prototype/' + f;
const lines = fs.readFileSync(F, 'utf8').split('\n');
let li = -1, maxc = 0;
lines.forEach((l, i) => { const c = (l.match(/\)\;/g) || []).length; if (c > maxc) { maxc = c; li = i; } });
if (maxc < 10) { console.error('INIT 行未找到'); process.exit(1); }
let init = lines[li];
const dropped = [];
for (const raw of list.split(',')) {
  const d = raw.trim();
  const call = d.endsWith(')') ? d + ';' : d.endsWith(');') ? d : d;
  const n = init.split(call).length - 1;
  if (n !== 1) { console.error('命中 ' + n + ' 次: ' + call); process.exit(1); }
  init = init.split(call + ' ').join('').split(call).join('');
  dropped.push(call);
}
lines[li] = init;
if (/\bnull\b/.test(init)) { }
fs.writeFileSync(F, lines.join('\n'));
console.log('摘除', dropped.length, '项，init 剩余调用', (init.match(/\)\;/g) || []).length);
