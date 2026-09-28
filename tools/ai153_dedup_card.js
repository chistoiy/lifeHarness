// 去重：_AiUsageEntryCard 被两次插入，删掉前一份（保留后一份·内容与页内引用一致）。
const fs = require('fs');
const p = 'lib/features/settings/presentation/ai_page.dart';
const lines = fs.readFileSync(p, 'utf8').split('\n');
const starts = lines.reduce((acc, l, i) => {
  if (l.startsWith('class _AiUsageEntryCard extends')) acc.push(i);
  return acc;
}, []);
if (starts.length !== 2) throw new Error('期望 2 处定义，实得 ' + starts.length);
// 第一份结束于第二份的文档注释行之前
let end = starts[1] - 1;
while (end > starts[0] && !lines[end].startsWith('/// AI 使用记录入口卡')) end--;
if (end <= starts[0]) throw new Error('找不到第一份的结束边界');
const removed = end - starts[0];
if (removed < 60 || removed > 130) throw new Error('删除行数异常: ' + removed);
lines.splice(starts[0], removed);
fs.writeFileSync(p, lines.join('\n'), 'utf8');
const now = fs.readFileSync(p, 'utf8');
const left = now.split('\n').filter((l) => l.startsWith('class _AiUsageEntryCard extends')).length;
if (left !== 1) throw new Error('去重后仍有 ' + left + ' 份');
console.log('OK 删除', removed, '行，剩 1 份定义');
