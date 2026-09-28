// 治理G7c3 一次性脚本：reader_page.dart 舞台渲染群（_stage/_para）外提为 extension part reader_stage.dart
// 三条护栏：锚点唯一命中断言 + 体积校验 + 改前快照（.bak）。纯移动，零逻辑改动。
const fs = require('fs');
const path = require('path');

const DIR = 'lib/features/read/presentation/reader';
const SRC = path.join(DIR, 'reader_page.dart');
const OUT = path.join(DIR, 'reader_stage.dart');
const DRY = process.argv.includes('--dry');

const lines = fs.readFileSync(SRC, 'utf8').split('\n');

function findOne(pred, label) {
  const hits = [];
  for (let i = 0; i < lines.length; i++) if (pred(lines[i], i)) hits.push(i);
  if (hits.length !== 1) {
    console.error(`ANCHOR-FAIL [${label}] hits=${hits.length} -> ${hits.join(',')}`);
    process.exit(1);
  }
  return hits[0];
}

const start = findOne((l) => l.startsWith('  // ---------- 舞台（翻页/滚动）'), 'stage.section');
// 文件里裸 '}' 有两处：ReaderPage 组件类收尾 + _ReaderPageState 收尾。取最后一处＝State 类收尾。
const bareBraces = [];
for (let i = 0; i < lines.length; i++) if (lines[i] === '}') bareBraces.push(i);
if (bareBraces.length !== 2) {
  console.error(`ANCHOR-FAIL [bare braces] expect 2 got ${bareBraces.length} -> ${bareBraces.join(',')}`);
  process.exit(1);
}
const classEnd = bareBraces[1];
if (classEnd !== lines.length - 2 && lines[classEnd + 1].trim() !== '') {
  console.error('SHAPE-FAIL class.close 后应为文件尾');
  process.exit(1);
}

const block = lines.slice(start, classEnd);
while (block.length && block[block.length - 1].trim() === '') block.pop();
if (!block.length || !block[block.length - 1].trim().endsWith('}')) {
  console.error('END-FAIL', JSON.stringify(block[block.length - 1]));
  process.exit(1);
}
if (!lines[start + 2].startsWith('  Widget _stage((String, Color, Color) th) {')) {
  console.error('SHAPE-FAIL _stage decl');
  process.exit(1);
}

const members = [
  'Widget _stage((String, Color, Color) th) {',
  'Widget _para((String, Color, Color) th, EpubDoc doc, int ci, EpubPara p, int pi) {',
];
const partLines = [
  "part of 'reader_page.dart';",
  '',
  '// 治理G7c3：舞台渲染群自 _ReaderPageState 移入同库扩展（行为零改动·直访私有字段）。',
  '// _stage＝错误态/加载态/滚动窗口/翻页 AnimatedSwitcher 四态；_para＝段型分派＋划线底色＋选区子串高亮。',
  'extension _ReaderStage on _ReaderPageState {',
  '',
  ...block,
  '}',
  '',
];

const keep = lines.slice();
for (let i = start + block.length - 1; i >= start; i--) keep.splice(i, 1);
// 拼接点空行收敛为恰好一行（只动删除点两侧，不做全文件空行重排）
while (keep[start] !== undefined && keep[start].trim() === '') keep.splice(start, 1);
keep.splice(start, 0, '');
const pa = keep.findIndex((l) => l === "part 'reader_sel_ops.dart';");
if (pa < 0) {
  console.error('ANCHOR-FAIL part directive');
  process.exit(1);
}
keep.splice(pa + 1, 0, "part 'reader_stage.dart';");
while (keep.length && keep[keep.length - 1].trim() === '') keep.pop();

const partText = partLines.join('\n');
const keptText = keep.join('\n');
const bad = [];
for (const m of members) {
  const inPart = partText.split('\n').filter((l) => l.trim() === m.trim()).length;
  const inKeep = keptText.split('\n').filter((l) => l.trim() === m.trim()).length;
  if (inPart !== 1 || inKeep !== 0) bad.push({ m, inPart, inKeep });
}
// setState 若出现在本群需要定点 ignore；本批断言为零（纯渲染）
const scc = partText.split('\n').filter((l) => l.includes('setState(')).length;
if (scc !== 0) bad.push({ m: 'setState 数量应为 0', got: scc });

const moved = block.length;
const before = lines.length;
const after = keep.length;
const volumeOk = before - after >= moved - 2 && before - after <= moved + 2 && after > 1150 && after < 1350;

console.log(JSON.stringify({ moved, partLines: partLines.length, readerPage: `${before} -> ${after}`, volumeOk, bad, DRY }, null, 2));
if (bad.length || !volumeOk) process.exit(1);
if (DRY) process.exit(0);

fs.copyFileSync(SRC, `${SRC}.bak`);
fs.writeFileSync(OUT, partText);
fs.writeFileSync(SRC, keptText + '\n');
console.log('WRITTEN', OUT, SRC);
