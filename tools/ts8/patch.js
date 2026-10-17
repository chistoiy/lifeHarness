/* 缺口盘点批 #8 · 时间账本分类明细下钻（prototype/index.html 共享面）
 * 命中断言式补丁；行尾自适应。用法：node tools/ts8/grab.js && node tools/ts8/patch.js
 */
const fs = require('fs');
const RD = (p) => fs.readFileSync(p, 'utf8');
const T = (n) => RD('tools/ts8/' + n);
const F = 'prototype/index.html';
const jobs = [
  { from: T('rank_from.txt'), to: "onclick=\"tsOpenCat('${c}')\"", tag: '分类行改真下钻' },
  { from: T('anchor_from.txt'), to: T('js.txt'), tag: '下钻模块 JS' },
  { from: '  <!-- ===== INS 全屏查看 ===== -->\n', to: T('sheet.html'), tag: '分类明细半屏' },
];
let src = RD(F);
const eol = (src.match(/\r\n/g) || []).length >= (src.match(/(^|[^\r])\n/g) || []).length ? '\r\n' : '\n';
const fit = (t) => eol === '\r\n' ? t.replace(/\r?\n/g, '\r\n') : t;
let bad = 0;
for (const j of jobs) {
  j.from = fit(j.from); j.to = fit(j.to);
  const n = src.split(j.from).length - 1;
  if (n !== 1) { console.log('FAIL ' + j.tag + ' 命中 ' + n + ' 次（需恰好 1）'); bad++; }
}
if (bad) { console.log('== ' + bad + ' 处未命中，整批不落盘 =='); process.exit(1); }
const size0 = src.length;
for (const j of jobs) src = src.replace(j.from, j.to);
fs.writeFileSync(F, src);
console.log('OK  ' + F + ' ' + size0 + ' → ' + src.length + ' 字节（+' + (src.length - size0) + '）· ' + jobs.length + ' 处补丁落盘（行尾 ' + (eol === '\r\n' ? 'CRLF' : 'LF') + '）');
