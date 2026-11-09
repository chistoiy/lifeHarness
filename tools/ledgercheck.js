// tools/ledgercheck.js — index-ledger.html 记账专版区域三件套校验（emoji / 处理器 / id 接线）
const fs = require('fs');
const F = process.argv[2] || 'prototype/index-ledger.html';
const s = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');

// 1) emoji 扫描（只看记账专版区域；✓/✕ 为文字符号与全壳层约定同源，不计表情）
const EM = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{26FF}\u{27B0}-\u{27BF}\u{FE0F}]/gu;
const ranges = [
  ['pages', s.indexOf('<!-- ===== 记账全家桶'), s.indexOf('<!-- ===== P6b')],
  ['sheets', s.indexOf('<!-- ===== S2 日期滚轮'), s.indexOf('<!-- ===== 番茄全屏专注页')],
  ['js', s.indexOf('记账全家桶 · 引擎核心'), s.indexOf('//LEDGER_JS_END')]
];
let bad = 0;
for (const [n, a, b] of ranges) {
  if (a < 0 || b < a) { console.log(n, 'RANGE FAIL'); bad++; continue }
  const hits = [...new Set(s.slice(a, b).match(EM) || [])];
  console.log(n + ' emoji:', hits.join(' ') || 'NONE');
  if (hits.length) bad++;
}

// 2) onclick/oninput/onchange 处理器函数存在性
const decl = new Set();
for (const m of s.matchAll(/function\s+([A-Za-z_$][\w$]*)/g)) decl.add(m[1]);
for (const m of s.matchAll(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/g)) decl.add(m[1]);
const builtin = new Set(['if','for','while','switch','return','typeof','event','this','window','document','Math','Number','String','Array','Object','JSON','Date','setTimeout','clearTimeout','parseInt','parseFloat','isNaN','alert','confirm','localStorage','navigator','console','Boolean','Set','Map','Promise','scrollTo','getComputedStyle','requestAnimationFrame','focus','blur','Location','location','toggleHideAmounts']);
const called = new Map();
for (const m of s.matchAll(/\bon(?:click|input|change|submit|keydown)=\\?["'`]([^"'`]+)/g)) {
  for (const c of m[1].matchAll(/(^|[^.\w$])([A-Za-z_$][\w$]*)\s*\(/g)) {
    if (!builtin.has(c[2]) && !decl.has(c[2])) called.set(c[2], (called.get(c[2]) || 0) + 1);
  }
}
console.log('未定义处理器:', called.size ? [...called].map(x => x[0] + '(' + x[1] + ')').join(' ') : 'NONE');
if (called.size) bad++;

// 3) getElementById 字面量目标存在性（屏单一归属后：已迁出 id 按注册表 deleted 段豁免，兜底＝重定向）
let GONE = new Set();
try {
  const reg = JSON.parse(fs.readFileSync('prototype/_modules.json', 'utf8'));
  const base = require('path').basename(F);
  for (const rec of (reg.deleted || {})[base] || []) { GONE.add(rec.id); (rec.inner || []).forEach(x => GONE.add(x)); }
} catch (e) { }
const miss = new Set();
for (const m of s.matchAll(/getElementById\(['"]([\w-]+)['"]\)/g)) {
  if (!GONE.has(m[1]) && !new RegExp('id="' + m[1] + '"').test(s) && !decl.has(m[1])) miss.add(m[1]);
}
for (const m of s.matchAll(/\$\('#([\w-]+)'\)/g)) {
  if (!GONE.has(m[1]) && !new RegExp('id="' + m[1] + '"').test(s) && !decl.has(m[1])) miss.add(m[1]);
}
const SHELL_LEGACY=new Set(['dashTip']);for(const x of SHELL_LEGACY)miss.delete(x);// dashTip=壳层既有缺口 非记账引入
console.log('缺失 id 目标:', miss.size ? [...miss].join(' ') : 'NONE');
if (miss.size) bad++;

// 4) 记账屏/弹层清单
const pages = [...s.matchAll(/<section id="(p-finance|p-tx\w+|p-report|p-yearly|p-budget|p-asset\w*|p-cats|p-recur|p-wish|p-debt|p-txSearch|p-lset|p-export|p-billImport)"/g)].map(m => m[1]);
const sheets = [...s.matchAll(/<div id="(sheetLedger\w+)"/g)].map(m => m[1]);
console.log('pages(' + pages.length + '):', pages.join(' '));
console.log('sheets(' + sheets.length + '):', sheets.join(' '));
console.log(bad ? 'RESULT: ISSUES ' + bad : 'RESULT: PASS');
process.exit(bad ? 1 : 0);
