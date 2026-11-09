// fix_theme.js · 给专版残留的 themeDots 顶层语句补空守卫：node tmp/fix_theme.js <文件名>
const fs = require('fs');
const f = process.argv[2];
const F = 'prototype/' + f;
let h = fs.readFileSync(F, 'utf8');
const lines = h.split('\n');
let n = 0;
for (let i = 0; i < lines.length; i++) {
  const l = lines[i];
  if (l.trim().startsWith("$('#themeDots').innerHTML=")) {
    const rest = l.trim().slice("$('#themeDots').innerHTML=".length);
    lines[i] = '{const _td=$("#themeDots");if(_td){_td.innerHTML=' + rest.replace(/;\s*$/, '') + ';}}';
    n++;
  }
}
if (n !== 1) { console.error('themeDots 命中', n); process.exit(1); }
fs.writeFileSync(F, lines.join('\n'));
console.log('themeDots 守卫完成', f);
