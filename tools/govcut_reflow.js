// govcut_reflow.js · 从删前快照回灌函数簇（弹层/屏的 onclick 依赖递归闭包）
// 用法：node tools/govcut_reflow.js <目标文件.html> <种子函数,逗号分隔> [快照路径=默认 tmp/snap-cut/<目标>.before]
const fs = require('fs');
function extractFn(text, name) {
  const m = new RegExp('function\\s+' + name + '\\s*\\(').exec(text);
  if (!m) return null;
  const start = text.indexOf('function', m.index);
  let p = text.indexOf('(', start + 9), dp = 0, k = p;
  for (; k < text.length; k++) { const c = text[k]; if (c === '(') dp++; else if (c === ')') { dp--; if (!dp) break; } }
  const s = text.indexOf('{', k);
  if (s < 0 || s - k > 30) return null;
  let depth = 0, j = s;
  for (; j < text.length; j++) { const c = text[j]; if (c === '{') depth++; else if (c === '}') { depth--; if (!depth) break; } }
  let e = j + 1;
  if (text[e] === ';') e++;
  return text.slice(start, e);
}
const [f, seeds, snapArg] = process.argv.slice(2);
if (!f || !seeds) { console.log('用法: node tools/govcut_reflow.js <文件.html> <fn1,fn2> [快照]'); process.exit(2); }
const F = 'prototype/' + f;
const snap = snapArg || ('tmp/snap-cut/' + f + '.before');
const src = fs.readFileSync(snap, 'utf8');
let h = fs.readFileSync(F, 'utf8');
const has = (t, n) => new RegExp('function\\s+' + n + '\\s*\\(').test(t);
const BUILTIN = /^(toast|closeSheet|openSheet|navTo|tgl|if|for|while|return|typeof|new|function|Number|Math|Date|JSON|String|Array|Object|parseInt|parseFloat|isNaN|setTimeout|clearTimeout|setInterval|clearInterval|console|window|document|location|localStorage|confirm|alert|event|this)$/;
const add = [];
const q = seeds.split(',').map(s => s.trim());
const seen = new Set();
while (q.length) {
  const n = q.shift();
  if (seen.has(n)) continue;
  seen.add(n);
  if (has(h, n) || add.some(a => a.n === n)) continue;
  const b = extractFn(src, n);
  if (!b) { console.log('· 快照无此函数:', n); continue; }
  add.push({ n, b });
  for (const m of b.matchAll(/(?<![.\w$])([A-Za-z_$][\w$]*)\s*\(/g)) {
    const c = m[1];
    if (BUILTIN.test(c) || seen.has(c)) continue;
    if (has(src, c) && !has(h, c)) q.push(c);
  }
}
if (!add.length) { console.log('无需回灌'); process.exit(0); }
const block = '\n/* ==== 治理批 govcut_reflow：函数簇回灌（源＝' + snap.replace(/.*\//, '') + '） ==== */\n' + add.map(a => a.b).join('\n') + '\n';
const anchor = h.lastIndexOf('</script>');
if (anchor < 0) { console.error('无 </script> 锚'); process.exit(1); }
h = h.slice(0, anchor) + block + h.slice(anchor);
fs.writeFileSync(F, h);
console.log('回灌', add.length, '个：', add.map(a => a.n).join(','));
