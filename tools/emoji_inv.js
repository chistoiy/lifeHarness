/* emoji 全仓清单工装（T13 分拣第一步）：按文件枚数＋去重字形列出；标注行是否注释级。
 * 用法：node tools/emoji_inv.js [dir]   （默认 lib；prototype 也可扫）
 * 口径：注释级命中不构成违令（守护上闸前先剔）；「原型同款」内容级 emoji 是否清扫归产品裁定——本脚本只出事实不动代码。 */
const fs = require('fs'), path = require('path');
const root = process.argv[2] || 'lib';
const ext = root === 'prototype' ? /\.(html|js)$/ : /\.dart$/;
function walk(d, out) {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    const st = fs.statSync(p);
    if (st.isDirectory()) { if (f !== 'build' && f !== '.dart_tool' && f !== 'archive') walk(p, out); }
    else if (ext.test(f)) out.push(p);
  }
  return out;
}
const EM = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]/gu;
let files = 0, hits = 0, cmt = 0;
for (const f of walk(root, [])) {
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  let fh = 0; const set = new Set(); const marks = [];
  lines.forEach((l, i) => {
    const m = l.match(EM); if (!m) return;
    fh += m.length; m.forEach(x => set.add(x));
    const isCmt = /^\s*(\/\/|\*|\/\*|<!--)/.test(l) || /"""|'''/.test(l);
    marks.push((isCmt ? '# ' : '') + (i + 1) + ':' + m.join(''));
    if (isCmt) cmt++;
  });
  if (fh) { files++; hits += fh; console.log(f.replace(/\\/g, '/') + '  ×' + fh + '  [' + [...set].join('') + ']  ' + marks.slice(0, 8).join(' ')); }
}
console.log('TOTAL files=' + files + ' hits=' + hits + ' comment-lines=' + cmt);
