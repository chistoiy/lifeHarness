// 治理G7c2 一次性脚本：reader_page.dart 选区/划线逻辑群外提为 extension part reader_sel_ops.dart
// 三条护栏：锚点唯一命中断言 + 体积校验 + 改前快照（.bak）。纯移动，零逻辑改动。
const fs = require('fs');
const path = require('path');

const DIR = 'lib/features/read/presentation/reader';
const SRC = path.join(DIR, 'reader_page.dart');
const OUT = path.join(DIR, 'reader_sel_ops.dart');
const LAYER = path.join(DIR, 'reader_sel_layer.dart');
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

// ── 区块起点：群注释/文档注释；区块终点：下一个保留成员的首行
const aStart = findOne((l) => l.startsWith('  // ---------- 批3 划词/划线'), 'A.start');
const aEnd = findOne((l) => l.startsWith('  // ---------- 外观（批4'), 'A.next') - 1;
const bStart = findOne((l) => l.startsWith('  /// 选区端点 → 舞台 Stack'), 'B.start');
const bEnd = findOne((l) => l.startsWith('  Widget _para((String, Color, Color) th'), 'B.next') - 1;
const cStart = findOne((l) => l.startsWith('/// AI 解读结果弹层'), 'C.start');
const orphan = findOne((l) => l.startsWith('/// 选区工具条下沿指向小三角'), 'C.orphan');
const tail = lines.length - 1; // 区块 C 到文件末尾

// 起点/终点内容复核（防止锚点漂到别的成员）
const expectFirst = [
  [aStart, '  // ---------- 批3'],
  [aStart + 3, '  String get _selTxt {'],
  [bStart, '  /// 选区端点'],
  [bStart + 1, '  Offset? _selAnchor(bool end) {'],
  [cStart, '/// AI 解读结果弹层'],
];
for (const [i, head] of expectFirst) {
  if (!lines[i].startsWith(head)) {
    console.error(`SHAPE-FAIL line ${i + 1}: want ${head} got ${JSON.stringify(lines[i])}`);
    process.exit(1);
  }
}
for (const [i, label] of [[aEnd, 'A.end'], [bEnd, 'B.end'], [tail, 'C.end']]) {
  const t = lines[i].trim();
  if (t !== '}' && t !== '});' && t !== '') {
    console.error(`SHAPE-FAIL ${label} line ${i + 1}: ${JSON.stringify(lines[i])}`);
    process.exit(1);
  }
}
// 移出的每一段必须以「}」收尾（去掉尾部空行后）
function trimTail(block) {
  const b = block.slice();
  while (b.length && b[b.length - 1].trim() === '') b.pop();
  return b;
}
const blockA = trimTail(lines.slice(aStart, aEnd + 1));
const blockB = trimTail(lines.slice(bStart, bEnd + 1));
const blockC = trimTail(lines.slice(cStart, tail + 1));
for (const [name, b] of [['A', blockA], ['B', blockB], ['C', blockC]]) {
  if (!b[b.length - 1].trim().endsWith('}')) {
    console.error(`END-FAIL block ${name}: ${JSON.stringify(b[b.length - 1])}`);
    process.exit(1);
  }
}

// 成员清单断言：移动前后各恰好出现一次
const members = [
  'String get _selTxt',
  'int? _charPosInPara(int ci, int pi, Offset global)',
  'void _selectPara(int ci, int pi, {Offset? at})',
  'void _clearSel() => setState',
  '({String tg, Color c, bool hasThought})? _hlAt(int ci, int pi)',
  'Future<void> _reloadHls() async',
  'Future<void> _addHl(String tg) async',
  'Future<void> _delHl() async',
  'void _actCopy()',
  'void _actShare()',
  'void _actQuote(bool thought)',
  'void _actDict()',
  'Future<void> _actAi() async',
  'Offset? _selAnchor(bool end)',
  'RenderParagraph? _paraRender(int ci, int pi)',
  'void _dragSel({required bool end, required Offset global})',
  '({int pi, int off})? _paraHitAt(int ci, Offset g)',
  'class _BrAiSheet extends StatelessWidget',
];

// setState 在扩展内属「受保护成员直访」误报，按 G7c1 口径定点 ignore
function addIgnores(block) {
  const out = [];
  for (const l of block) {
    if (l.includes('setState(')) {
      const prev = out.length ? out[out.length - 1] : '';
      if (!prev.includes('invalid_use_of_protected_member')) {
        out.push(`${l.match(/^\s*/)[0]}// ignore: invalid_use_of_protected_member`);
      }
    }
    out.push(l);
  }
  return out;
}

const header = [
  "part of 'reader_page.dart';",
  '',
  '// 治理G7c2：选区/划线逻辑群自 _ReaderPageState 移入同库扩展（行为零改动·直访私有字段）。',
  '// 群内成员＝选区文本/句粒度命中/划线增删/工具条动作（复制·分享·书摘·词典·AI），',
  '// 以及手柄定位（_selAnchor/_paraRender/_dragSel/_paraHitAt）与 AI 解读弹层 _BrAiSheet。',
  'extension _ReaderSelOps on _ReaderPageState {',
  '',
];
const partLines = [
  ...header,
  ...addIgnores(blockA),
  '',
  ...addIgnores(blockB),
  '}',
  '',
  ...blockC,
  '',
];

// ── 新 reader_page：删 C（含孤立注释行）→ 删 B → 删 A → 补 part 指令
const keep = lines.slice();
const cut = (from, to) => {
  for (let i = to; i >= from; i--) keep.splice(i, 1);
};
cut(cStart, tail);
// C 之前的孤立注释（BrTriPainter 文档注释错位留在此处）与其后空行一并清
cut(orphan, cStart - 1 > orphan ? cStart - 1 : orphan);
cut(bStart, bEnd);
cut(aStart, aEnd);

const partAnchor = keep.findIndex((l) => l === "part 'reader_chrome.dart';");
if (partAnchor < 0) {
  console.error('ANCHOR-FAIL part directive');
  process.exit(1);
}
keep.splice(partAnchor + 1, 0, "part 'reader_sel_ops.dart';");

// 只在拼接点收敛：文件尾多余空行剥掉（不做全文件空行重排，避免无关键噪音）
while (keep.length && keep[keep.length - 1].trim() === '') keep.pop();
const collapsed = keep;

// BrTriPainter 补回文档注释（纯注释搬运）
const layerSrc = fs.readFileSync(LAYER, 'utf8');
const painterAnchor = 'class BrTriPainter extends CustomPainter {';
if (!layerSrc.includes(painterAnchor)) {
  console.error('ANCHOR-FAIL BrTriPainter');
  process.exit(1);
}
const painterDoc = '/// 选区工具条下沿指向小三角（参考图4 气泡尖）。\n';
const newLayer = layerSrc.includes(painterDoc)
  ? layerSrc
  : layerSrc.replace(painterAnchor, painterDoc + painterAnchor);

const movedCount = blockA.length + blockB.length + blockC.length;
const ignoreCount = partLines.filter((l) => l.includes('invalid_use_of_protected_member')).length;
const before = lines.length;
const after = collapsed.length;
const volumeOk = before - after > 400 && before - after < movedCount + 40 && after > 1400 && after < 1700;

console.log(
  JSON.stringify(
    {
      blockA: blockA.length,
      blockB: blockB.length,
      blockC: blockC.length,
      moved: movedCount,
      partLines: partLines.length,
      readerPage: `${before} -> ${after}`,
      setStateIgnores: ignoreCount,
      volumeOk,
      dry: DRY,
    },
    null,
    2,
  )
);

// 双向成员断言
const partText = partLines.join('\n');
const keptText = collapsed.join('\n');
const bad = [];
for (const m of members) {
  const inPart = partText.split('\n').filter((l) => l.trim().startsWith(m)).length;
  const inKeep = keptText.split('\n').filter((l) => l.trim().startsWith(m)).length;
  if (inPart !== 1 || inKeep !== 0) bad.push({ m, inPart, inKeep });
}
if (bad.length) {
  console.error('MEMBER-ASSERT-FAIL', JSON.stringify(bad, null, 2));
  process.exit(1);
}
if (!volumeOk) {
  console.error('VOLUME-FAIL');
  process.exit(1);
}
// 大文件写入护栏：新 reader_page 体积必须 < 旧且 > 1400
if (DRY) process.exit(0);

fs.copyFileSync(SRC, `${SRC}.bak`);
fs.writeFileSync(OUT, partText + '\n');
fs.writeFileSync(SRC, keptText + '\n');
fs.writeFileSync(LAYER, newLayer);
console.log('WRITTEN', OUT, SRC, LAYER);
