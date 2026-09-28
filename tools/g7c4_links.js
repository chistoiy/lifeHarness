// 治理G7c4 一次性脚本：reader_page.dart 链接/图片群外提为 extension part reader_links.dart
// 三条护栏：锚点唯一命中断言 + 体积校验 + 改前快照（.bak）。纯移动，零逻辑改动。
const fs = require('fs');
const path = require('path');

const DIR = 'lib/features/read/presentation/reader';
const SRC = path.join(DIR, 'reader_page.dart');
const OUT = path.join(DIR, 'reader_links.dart');
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

const start = findOne((l) => l.startsWith('  // ---------- 链接/图片'), 'links.section');
const nextIdx = findOne((l) => l.startsWith('  void _showFlash(String msg) {'), 'next.showFlash');
const block = lines.slice(start, nextIdx);
while (block.length && block[block.length - 1].trim() === '') block.pop();
if (!block[block.length - 1].trim().endsWith('}')) {
  console.error('END-FAIL', JSON.stringify(block[block.length - 1]));
  process.exit(1);
}

const members = [
  'void _onLink(EpubLink l) {',
  'Future<void> _onExtLink(String url) async {',
  'Future<void> _openUrl(String url) async {',
  'void _openImage(EpubPara para) {',
];
const partLines = [
  "part of 'reader_page.dart';",
  '',
  '// 治理G7c4：链接/图片群自 _ReaderPageState 移入同库扩展（行为零改动·直访私有字段）。',
  '// 内链跳章 / 外链三策略（含 UA·熔断后的回落通道）/ 图片放大与保存。',
  'extension _ReaderLinks on _ReaderPageState {',
  '',
  ...block,
  '}',
  '',
];

const keep = lines.slice();
for (let i = start + block.length - 1; i >= start; i--) keep.splice(i, 1);
while (keep[start] !== undefined && keep[start].trim() === '') keep.splice(start, 1);
keep.splice(start, 0, '');

const pa = keep.findIndex((l) => l === "part 'reader_stage.dart';");
if (pa < 0) {
  console.error('ANCHOR-FAIL part directive');
  process.exit(1);
}
keep.splice(pa + 1, 0, "part 'reader_links.dart';");
while (keep.length && keep[keep.length - 1].trim() === '') keep.pop();

const partText = partLines.join('\n');
const keptText = keep.join('\n');
const bad = [];
for (const m of members) {
  const inPart = partText.split('\n').filter((l) => l.trim() === m).length;
  const inKeep = keptText.split('\n').filter((l) => l.trim() === m).length;
  if (inPart !== 1 || inKeep !== 0) bad.push({ m, inPart, inKeep });
}
// 本群为纯 IO/跳转，断言不含 setState（否则需 G7c2 式定点 ignore）
const scc = partText.split('\n').filter((l) => l.includes('setState(')).length;
if (scc !== 0) bad.push({ m: 'setState 应为 0', got: scc });

const moved = block.length;
const before = lines.length;
const after = keep.length;
const volumeOk = before - after >= moved - 2 && before - after <= moved + 2 && after > 1000 && after < 1200;

console.log(JSON.stringify({ moved, partLines: partLines.length, readerPage: `${before} -> ${after}`, volumeOk, bad, DRY }, null, 2));
if (bad.length || !volumeOk) process.exit(1);
if (DRY) process.exit(0);

fs.copyFileSync(SRC, `${SRC}.bak`);
fs.writeFileSync(OUT, partText);
fs.writeFileSync(SRC, keptText + '\n');
console.log('WRITTEN', OUT, SRC);
