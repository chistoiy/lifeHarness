// 修复 UI组件规范：上一次编辑把 LH-K30 行首吃掉、并把 LH-S30 行插进了 K 段。
// 现把 S30 迁回 S 段（LH-S29 之后），并还原 K30 的行首。
const fs = require('fs');
const p = 'docs/UI组件规范.md';
let lines = fs.readFileSync(p, 'utf8').split('\n');

const i30 = lines.findIndex((l) => l.startsWith('| LH-S30 '));
if (i30 < 0) throw new Error('找不到 LH-S30 行');
const s30 = lines[i30];

// ① K 段里 S30 那行 → 还原成 K30 行（行首要补回来，尾部与下一行是同一条被拆开的两半）
const frag = lines[i30 + 1];
if (!frag.startsWith(' `#apKey`/') && !frag.startsWith(" `#apKey`/")) {
  throw new Error('K30 残片不在预期位置：' + JSON.stringify(frag.slice(0, 30)));
}
lines[i30] = '| LH-K30 | **掩码密钥输入 + 眼睛切换**（V1.53.1） |' + frag;
lines.splice(i30 + 1, 1);

// ② 把 S30 插到 LH-S29 之后（S 段）
const iS29 = lines.findIndex((l) => l.startsWith('| LH-S29 '));
if (iS29 < 0) throw new Error('找不到 LH-S29 行');
lines.splice(iS29 + 1, 0, s30);

const out = lines.join('\n');
// 断言：三段各就各位、没有以空格开头的残行
for (const need of ['| LH-S29 ', '| LH-S30 ', '| LH-K29 ', '| LH-K30 ', '| LH-K31 ']) {
  if (!lines.some((l) => l.startsWith(need))) throw new Error('缺行 ' + need);
}
const orphans = lines.filter((l) => l.startsWith(' `') || l.startsWith(' | `'));
if (orphans.length) throw new Error('仍有残行 ' + orphans.length);
fs.writeFileSync(p, out, 'utf8');
console.log('OK：S30 归 S 段，K30 行首已还原');
