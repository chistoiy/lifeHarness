// 修复交接文档：V1.53 行插入时把上一行（V1.53.1 落地记录）的行首吞掉了，补回来。
const fs = require('fs');
const p = 'docs/交接文档.md';
const lines = fs.readFileSync(p, 'utf8').split('\n');
const i = lines.findIndex((l) => l.startsWith(' ① **Flutter 侧**：`ai_config.dart`'));
if (i < 0) throw new Error('找不到待续行');
if (lines[i - 1].includes('V1.53.1 · AI 服务商可增删改落地')) throw new Error('疑似已修过，勿重跑');
lines[i] =
  '| 2026-09-28 | **V1.53.1 · AI 服务商可增删改落地 + AI 规范固化（R8）**（提交 `aa6342a` + `d4c6ba2`） |' +
  lines[i];
fs.writeFileSync(p, lines.join('\n'), 'utf8');
const check = fs.readFileSync(p, 'utf8').split('\n');
const bad = check.filter((l) => l.startsWith(' |') || l.startsWith(' ① '));
if (bad.length) throw new Error('仍有残行: ' + bad.length);
console.log('OK 行首已还原');
