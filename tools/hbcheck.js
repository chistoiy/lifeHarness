const fs = require('fs');
const F = process.argv[2] || 'prototype/index_habitcheck.html';
const s = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');

// 1) emoji 扫描（只看习惯专版区域）
const EM = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]/gu;
const ranges = [
  ['pages', s.indexOf('<!-- ===== P12 习惯打卡'), s.indexOf('    <!-- ===== P12a 二级：数据与同步')],
  ['sheets', s.indexOf('<!-- ===== 习惯专版 · 新建'), s.indexOf('  <!-- ===== 主题市场 -->')],
  ['js', s.indexOf('/* ================= 习惯打卡'), s.indexOf('/* ================= 插件中心')]
];
for (const [n, a, b] of ranges) {
  if (a < 0 || b < a) { console.log(n, 'RANGE FAIL'); continue }
  const hits = [...new Set(s.slice(a, b).match(EM) || [])];
  console.log(n + ' emoji:', hits.join(' ') || 'NONE');
}

// 2) 处理器函数存在性
const decl = new Set();
for (const m of s.matchAll(/function\s+([A-Za-z_$][\w$]*)/g)) decl.add(m[1]);
for (const m of s.matchAll(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/g)) decl.add(m[1]);
const builtin = new Set(['if', 'for', 'while', 'switch', 'return', 'typeof', 'event', 'this', 'window', 'document', 'Math', 'Number', 'String', 'Array', 'Object', 'JSON', 'Date', 'setTimeout', 'clearTimeout', 'parseInt', 'parseFloat', 'isNaN', 'alert', 'confirm', 'localStorage', 'navigator', 'console', 'Boolean', 'Set', 'Map', 'Promise', 'encodeURIComponent', 'decodeURIComponent', 'scrollTo', 'getComputedStyle', 'requestAnimationFrame', 'focus', 'blur']);
const called = new Map();
for (const m of s.matchAll(/\bon(?:click|input|change|submit|keydown)=\\?["'`]([^"'`]+)/g)) {
  for (const c of m[1].matchAll(/([A-Za-z_$][\w$]*)\s*\(/g)) {
    if (!builtin.has(c[1]) && !decl.has(c[1])) called.set(c[1], (called.get(c[1]) || 0) + 1);
  }
}
console.log('未定义处理器:', called.size ? [...called].map(x => x[0] + '(' + x[1] + ')').join(' ') : 'NONE');

// 3) getElementById 目标是否存在（字面量）
const miss = new Set();
for (const m of s.matchAll(/getElementById\(['"]([\w-]+)['"]\)/g)) {
  if (!new RegExp('id="' + m[1] + '"').test(s) && !decl.has(m[1])) miss.add(m[1]);
}
console.log('缺失 id 目标:', miss.size ? [...miss].join(' ') : 'NONE');

// 4) 动态 id 前缀（sheet/page）接线
const ids = [...s.matchAll(/id="(sheetHabit[\w]*|p-habit[\w]*)"/g)].map(m => m[1]);
console.log('习惯弹层/页面:', ids.join(' '));
for (const fn of ['renderHabits', 'renderHabitDetail', 'renderHabitStat', 'heOpen', 'heSave', 'hbLogOpen', 'hbLogSave', 'hbTap', 'hdPick', 'hsPick', 'hbLogClear', 'hbLogUndo', 'heSubAdd', 'heValPick', 'heTodoChg', 'renderHdrActs']) {
  if (!decl.has(fn)) console.log('MISSING fn', fn);
}
