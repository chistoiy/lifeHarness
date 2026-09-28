// 治理G7d1b 一次性脚本：shelf_page.dart 目标卡群 + 筛选面板群 外提为 extension part
// （_cardDeco.._openYearList → _ShelfGoal；// 排序与筛选面板 .. _panelChip → _ShelfPanel）
// 三条护栏：锚点唯一命中断言 + 体积校验 + 改前快照（.bak）。纯移动，零逻辑改动。
const fs = require('fs');
const path = require('path');

const DIR = 'lib/features/read/presentation/shelf';
const SRC = path.join(DIR, 'shelf_page.dart');
const DRY = process.argv.includes('--dry');

const lines = fs.readFileSync(SRC, 'utf8').split('\n');
const origLen = lines.length;

// 在「State 类体内」按锚点前缀找唯一命中（返回 0-based 行号）
function findOnce(src, pred, label) {
  const hits = [];
  for (let i = 0; i < src.length; i++) if (pred(src[i], i)) hits.push(i);
  if (hits.length !== 1) {
    console.error(`ANCHOR-FAIL [${label}] hits=${hits.length} -> ${hits.join(',')}`);
    process.exit(1);
  }
  return hits[0];
}

const aState = findOnce(lines, (l) => l.startsWith('class _ShelfPageState'), 'state.class');
const aBuild = findOnce(lines, (l) => l.trim() === 'Widget build(BuildContext context) {', 'build');
const aCard = findOnce(
  lines,
  (l) => l.startsWith('  BoxDecoration _cardDeco(BuildContext context) {'),
  'goal.cardDeco',
);
const aPanel = findOnce(lines, (l) => l.includes('排序与筛选面板'), 'panel.section');
const aViews = findOnce(lines, (l) => l.includes('主体五视图'), 'views.section');
const aBatch = findOnce(
  lines,
  (l) => l.trim().startsWith('//') && l.includes('批量管理浮动条（原型 849-855 /'),
  'batch.section',
);
if (!(aState < aBuild && aBuild < aCard && aCard < aPanel && aPanel < aViews && aViews < aBatch)) {
  console.error('ORDER-FAIL', { aState, aBuild, aCard, aPanel, aViews, aBatch });
  process.exit(1);
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

const groups = [
  {
    out: 'shelf_goal.dart',
    ext: '_ShelfGoal',
    start: aCard,
    end: aPanel,
    header: [
      "part of 'shelf_page.dart';",
      '',
      '// 治理G7d1b：目标卡群自 _ShelfPageState 移入同库扩展（行为零改动·直访私有字段）。',
      '// 卡片装饰 / 年度完成与 ETA 计算 / 目标卡与年度迷你视图 / 年度清单弹层。',
    ],
    members: [
      'BoxDecoration _cardDeco(BuildContext context) {',
      'List<Book> _yearDone(List<Book> all) {',
      'String _yearEta(WorkbenchData? w, int done, int goal) {',
      'Widget _goalCard(WorkbenchData? w, dynamic tokens, List<Book> all) {',
      'Widget _yearMini(ShelfUI ui, int done, int goal, int need) {',
      'Future<void> _openYearList() async {',
      'Widget _pillBtn(String key, String label, VoidCallback onTap) =>',
    ],
  },
  {
    out: 'shelf_panel.dart',
    ext: '_ShelfPanel',
    start: aPanel,
    end: aViews,
    header: [
      "part of 'shelf_page.dart';",
      '',
      '// 治理G7d1b：排序与筛选面板群自 _ShelfPageState 移入同库扩展（行为零改动）。',
      '// 半屏面板（_openPanel）+ 面板胶囊（_panelChip）；读写走 shelfUiProvider。',
    ],
    members: [
      'void _openPanel(BuildContext context, ShelfUI ui) {',
      'Widget _panelChip(',
    ],
  },
];

// 自底向上删除，避免索引漂移
const keep = lines.slice();
for (const g of groups.slice().reverse()) {
  const blk = block(keep, g.start, g.end);
  g.body = blk;
  for (let i = g.start + blk.length - 1; i >= g.start; i--) keep.splice(i, 1);
  while (keep[g.start] !== undefined && keep[g.start].trim() === '') keep.splice(g.start, 1);
  keep.splice(g.start, 0, '');
}

const lastPart = findOnce(
  keep,
  (l) => l.startsWith("part 'shelf_goal_ring.dart';"),
  'last.part',
);
keep.splice(lastPart + 1, 0, ...groups.map((g) => `part '${g.out}';`));
while (keep.length && keep[keep.length - 1].trim() === '') keep.pop();
keep.push('');

const keptText = keep.join('\n');
const bad = [];
const partTexts = {};
for (const g of groups) {
  const t = [...g.header, `extension ${g.ext} on _ShelfPageState {`, ...g.body, '}', ''].join(
    '\n'
  );
  partTexts[g.out] = t;
  for (const m of g.members) {
    const inPart = t.split('\n').filter((l) => l.trim() === m).length;
    const inKeep = keptText.split('\n').filter((l) => l.trim() === m).length;
    if (inPart !== 1 || inKeep !== 0) bad.push({ out: g.out, m, inPart, inKeep });
  }
  const scc = t.split('\n').filter((l) => l.includes('setState(')).length;
  if (scc !== 0) bad.push({ out: g.out, m: 'setState 应为 0', got: scc });
  // 扩展体内不得含实例字段（extension 不支持字段）
  const fld = t.split('\n').filter((l) => /^  (final |late )/.test(l));
  if (fld.length) bad.push({ out: g.out, m: '疑似字段', got: fld });
}
for (const m of ['Widget build(BuildContext context) {', 'void initState() {']) {
  if (keptText.split('\n').filter((l) => l.trim() === m).length !== 1)
    bad.push({ m: 'keep 侧缺失 ' + m });
}

const moved = groups.reduce((s, g) => s + g.body.length, 0);
const after = keep.length;
const volumeOk = origLen - after >= moved - 4 && origLen - after <= moved + 6 && after > 1200;

console.log(
  JSON.stringify(
    {
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
