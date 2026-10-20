const fs = require('fs');
const f = 'lib/features/read/presentation/reader_page.dart';
const src = fs.readFileSync(f, 'utf8');
const lines = src.split('\n');

function findStart(snip) {
  const i = lines.findIndex((l) => l.includes(snip));
  if (i < 0) throw new Error('未找到起点: ' + snip);
  return i;
}
const a = findStart('  Widget _pnlProg(BookPagination pag) {');
const b = findStart('  Widget _flashBar((String, Color, Color) th) {');
if (b <= a) throw new Error('区间反向');
const dropped = lines.slice(a, b);
const joined = dropped.join('\n');
for (const must of ['_pnlBright', '_pnlFont', '_pnlBtn', '_stepBtn', '_stepNudge', '_sideLabel', "ValueKey('brProg')", "ValueKey('brLum')"]) {
  if (!joined.includes(must)) throw new Error('待删区间缺少锚点：' + must);
}
if (joined.length > 12000) throw new Error('待删区间异常巨大：' + joined.length);
const before = lines.length;
lines.splice(a, b - a);
fs.writeFileSync(f, lines.join('\n'), 'utf8');
console.log('删除 ' + (before - lines.length) + ' 行 · 区间 ' + (a + 1) + '~' + b);
