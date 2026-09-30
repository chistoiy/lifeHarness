// 反馈轮5 原型改动：共享面 index.html
// ① p-profile 摘除「小工具合集」入口行 ② D.grid 摘除 日记/笔记 两枚
// ③ 阅读枚带第4位段名，点击先切 tab 再 switchRecord
const fs = require('fs');
const f = 'prototype/index.html';
let s = fs.readFileSync(f, 'utf8');
const before = s.length;
let hits = 0;
function sub(oldStr, newStr, tag) {
  const n = s.split(oldStr).length - 1;
  if (n !== 1) throw new Error('anchor ' + tag + ' hits=' + n + ' (expect 1)');
  s = s.replace(oldStr, newStr);
  hits++;
  console.log('ok ' + tag);
}

// ① 我的页入口行
const rowStart = `        <button onclick="navTo('p-tools')" class="w-full flex items-center gap-3 p-3.5 text-left border-t border-slate-100 dark:border-slate-800 active:bg-slate-50 dark:active:bg-slate-800/60">\n`;
const rowIc = s.slice(s.indexOf(rowStart) + rowStart.length);
const rowLine = rowIc.split('\n')[0] + '\n';
if (!rowLine.includes('小工具合集')) throw new Error('小工具合集 row not adjacent');
sub(rowStart + rowLine, '', 'profile-kits-row');

// ② 宫格摘除日记/笔记
sub(
  `grid:[['✅','待办','p-todo'],['⏱️','时间','p-calendar'],['📔','日记','p-records'],['📝','笔记','p-records'],['📚','阅读','p-records'],`,
  `grid:[['✅','待办','p-todo'],['⏱️','时间','p-calendar'],['📚','阅读','p-records','book'],`,
  'grid-drop-diary-note'
);

// ③ 点击处理支持第4位段名
sub(
  `    const act = activeTabs.includes(g[2]) ? \`navTab('\${g[2]}')\` : \`stack.length=0;setPage('\${g[2]}')\`;`,
  `    /* 反馈轮5：带第4位段名的宫格（如「阅读」）先落 tab 再切该段视图 */
    const act = g[3] ? \`navTab('\${g[2]}');switchRecord('\${g[3]}')\`
        : activeTabs.includes(g[2]) ? \`navTab('\${g[2]}')\` : \`stack.length=0;setPage('\${g[2]}')\`;`,
  'grid-click-segment'
);

fs.writeFileSync(f, s);
console.log('hits=' + hits + ' len ' + before + ' -> ' + s.length);
