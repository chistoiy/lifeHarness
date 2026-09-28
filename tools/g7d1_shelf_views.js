// 治理G7d1c/1d 一次性脚本：shelf_page.dart 五视图群/书脊时间线群/批量群 外提为 extension part
// 用法：node tools/g7d1_shelf_views.js --groups views          （G7d1c）
//       node tools/g7d1_shelf_views.js --groups spine,batch    （G7d1d）
//       加 --dry 只看统计。三条护栏：锚点唯一命中断言 + 体积校验 + 改前快照（.bak）。
const fs = require('fs');
const path = require('path');

const DIR = 'lib/features/read/presentation/shelf';
const SRC = path.join(DIR, 'shelf_page.dart');
const DRY = process.argv.includes('--dry');
const gIdx = process.argv.indexOf('--groups');
const wanted = (gIdx >= 0 ? process.argv[gIdx + 1] : '').split(',').filter(Boolean);
if (!wanted.length) {
  console.error('USAGE: --groups views[,spine][,batch]');
  process.exit(1);
}

const lines = fs.readFileSync(SRC, 'utf8').split('\n');
const origLen = lines.length;

function findOnce(src, pred, label) {
  const hits = [];
  for (let i = 0; i < src.length; i++) if (pred(src[i], i)) hits.push(i);
  if (hits.length !== 1) {
    console.error(`ANCHOR-FAIL [${label}] hits=${hits.length} -> ${hits.join(',')}`);
    process.exit(1);
  }
  return hits[0];
}

const byTrim = (t) => (l) => l.trim() === t;
const lastBrace = (() => {
  for (let i = lines.length - 1; i >= 0; i--)
    if (lines[i].trim() !== '') return i;
  return -1;
})();

// 每个群：start 锚点 + end 锚点（'EOF'＝类收尾花括号前一行）
const ALL = {
  views: {
    out: 'shelf_views.dart',
    ext: '_ShelfViews',
    start: byTrim('// ---------------- 主体五视图 ----------------'),
    endLabel: '_spineView',
    end: byTrim('Widget _spineView(List<Book> list, String pfx) {'),
    header: [
      "part of 'shelf_page.dart';",
      '',
      '// 治理G7d1c：主体五视图群自 _ShelfPageState 移入同库扩展（行为零改动·直访私有字段）。',
      '// 圆钮/维度分组 / 视图派发（_body 五态）/ 点按包装与单选切换 / 封面墙卡片 / 列表行。',
    ],
    members: [
      'Widget _roundBtn(String key, IconData ic, String tip, VoidCallback onTap) {',
      'List<Widget> _dimGroups(',
      'Widget _body(',
      'Widget _tapWrap(',
      'void _selTap(ShelfUI ui, Book b) {',
      'Widget _wallCard(',
      'String _md(int? ms) {',
      'Widget _rowItem(',
    ],
  },
  spine: {
    out: 'shelf_spine_time.dart',
    ext: '_ShelfSpineTime',
    start: byTrim('Widget _spineView(List<Book> list, String pfx) {'),
    endLabel: 'batch.section',
    end: byTrim(
      '// ---------------- 批量管理浮动条（原型 849-855 / 4619-4628） ----------------',
    ),
    header: [
      "part of 'shelf_page.dart';",
      '',
      '// 治理G7d1d：书脊视图与时间线视图自 _ShelfPageState 移入同库扩展（行为零改动）。',
      '// 书脊列（含封面可用性判定 _hasCover）/ 按月分组的阅读时间线。',
    ],
    members: [
      'Widget _spineView(List<Book> list, String pfx) {',
      'Widget _timelineView(List<Book> list, ColorScheme cs) {',
    ],
  },
  batch: {
    out: 'shelf_batch_ops.dart',
    ext: '_ShelfBatchOps',
    start: byTrim(
      '// ---------------- 批量管理浮动条（原型 849-855 / 4619-4628） ----------------',
    ),
    endLabel: 'EOF',
    end: null,
    header: [
      "part of 'shelf_page.dart';",
      '',
      '// 治理G7d1d：批量管理群自 _ShelfPageState 移入同库扩展（行为零改动）。',
      '// 浮动选择条与批量钮 / 退出多选 / 批量移书单·删除·加标签（走 shelfUiProvider + readTick）。',
    ],
    members: [
      'Widget _batchBar(ShelfUI ui, ColorScheme cs, dynamic tokens) {',
      'Widget _batBtn(',
      'Future<void> _batMove(List<String> ids) async {',
      'Future<void> _batDel(List<String> ids) async {',
      'Future<void> _batTag(List<String> ids) async {',
    ],
  },
};

const groups = wanted.map((k) => ALL[k]);
for (const g of groups) {
  g.s = findOnce(lines, g.start, `${g.out}.start`);
  g.e = g.end === null ? lastBrace : findOnce(lines, g.end, `${g.out}.end`);
}
const sorted = groups.slice().sort((a, b) => a.s - b.s);
for (let i = 0; i < sorted.length; i++) {
  const g = sorted[i];
  if (!(g.s < g.e)) {
    console.error('ORDER-FAIL', g.out, g.s, g.e);
    process.exit(1);
  }
  if (i + 1 < sorted.length && !(g.e <= sorted[i + 1].s)) {
    console.error('OVERLAP-FAIL', g.out, sorted[i + 1].out);
    process.exit(1);
  }
}

function block(src, start, endExclusive) {
  const b = src.slice(start, endExclusive);
  while (b.length && b[b.length - 1].trim() === '') b.pop();
  if (!b.length || !/[};]$/.test(b[b.length - 1].trim())) {
    console.error('END-FAIL', JSON.stringify(b[b.length - 1]));
    process.exit(1);
  }
  return b;
}

const keep = lines.slice();
for (const g of sorted.slice().reverse()) {
  const eEx = g.end === null ? g.e : g.e; // batch：g.e＝类收尾花括号行（不含）
  const blk = block(keep, g.s, eEx);
  g.body = blk;
  for (let i = g.s + blk.length - 1; i >= g.s; i--) keep.splice(i, 1);
  while (keep[g.s] !== undefined && keep[g.s].trim() === '') keep.splice(g.s, 1);
  keep.splice(g.s, 0, '');
}

const lastPart = findOnce(keep, (l) => l.startsWith("part 'shelf_panel.dart';"), 'last.part');
keep.splice(lastPart + 1, 0, ...groups.map((g) => `part '${g.out}';`));
while (keep.length && keep[keep.length - 1].trim() === '') keep.pop();
keep.push('');

const keptText = keep.join('\n');
const bad = [];
const partTexts = {};
for (const g of groups) {
  const t = [...g.header, `extension ${g.ext} on _ShelfPageState {`, ...g.body, '}', ''].join('\n');
  partTexts[g.out] = t;
  for (const m of g.members) {
    const inPart = t.split('\n').filter((l) => l.trim() === m).length;
    const inKeep = keptText.split('\n').filter((l) => l.trim() === m).length;
    if (inPart !== 1 || inKeep !== 0) bad.push({ out: g.out, m, inPart, inKeep });
  }
  const scc = t.split('\n').filter((l) => l.includes('setState(')).length;
  if (scc !== 0) bad.push({ out: g.out, m: 'setState 应为 0', got: scc });
  const fld = t.split('\n').filter((l) => /^  (final |late )/.test(l));
  if (fld.length) bad.push({ out: g.out, m: '疑似字段', got: fld });
}
// 主文件必须仍是完整库：类收尾花括号存在、build 未被动
for (const m of ['Widget build(BuildContext context) {', '}']) {
  const n = keptText.split('\n').filter((l) => l.trim() === m).length;
  if (m === '}' ? n < 1 : n !== 1) bad.push({ m: 'keep 侧异常 ' + m, got: n });
}

const moved = groups.reduce((s, g) => s + g.body.length, 0);
const after = keep.length;
const volumeOk =
  origLen - after >= moved - 3 * groups.length - 2 &&
  origLen - after <= moved + 4 &&
  after > 700;

console.log(
  JSON.stringify(
    {
      groups: wanted,
      moved,
      parts: groups.map((g) => `${g.out}:${g.body.length}`),
      shelfPage: `${origLen} -> ${after}`,
      volumeOk,
      bad,
      DRY,
    },
    null,
    2,
  ),
);
if (bad.length || !volumeOk) process.exit(1);
if (DRY) process.exit(0);

fs.writeFileSync(SRC + '.bak', lines.join('\n'));
for (const g of groups) fs.writeFileSync(path.join(DIR, g.out), partTexts[g.out]);
fs.writeFileSync(SRC, keptText);
console.log('WRITTEN');
