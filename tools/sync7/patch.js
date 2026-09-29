/* 缺口盘点批 #7 · 同步严格校验用户编辑入口（prototype/index-sync.html 专版）
 * 命中断言式补丁；行尾自适应（本文件工作区为 CRLF）。
 * 用法：node tools/sync7/grab.js && node tools/sync7/patch.js
 */
const fs = require('fs');
const RD = (p) => fs.readFileSync(p, 'utf8');
const T = (n) => RD('tools/sync7/' + n);
const F = 'prototype/index-sync.html';
const jobs = [
  { from: T('row_from.txt'), to: T('row.txt'), tag: '服务配置·允许严格校验开关行' },
  { from: T('tier_from.txt'), to: T('tier_js.txt'), tag: '差异档受开关放行·新增 tglVerify' },
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
