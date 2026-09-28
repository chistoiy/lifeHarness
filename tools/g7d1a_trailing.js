// 治理G7d1a 一次性脚本：shelf_page.dart 尾随四块整块外提为 part 文件
// （_BatchTagSheet+State / GradShelfFab / kLp*+showLongPressSheet / _GoalRingPainter）
// 三条护栏：锚点唯一命中断言 + 体积校验 + 改前快照（.bak）。纯移动，零逻辑改动。
const fs = require('fs');
const path = require('path');

const DIR = 'lib/features/read/presentation/shelf';
const SRC = path.join(DIR, 'shelf_page.dart');
const DRY = process.argv.includes('--dry');

const lines = fs.readFileSync(SRC, 'utf8').split('\n');
const origLen = lines.length;

function findOne(pred, label) {
  const hits = [];
  for (let i = 0; i < lines.length; i++) if (pred(lines[i], i)) hits.push(i);
  if (hits.length !== 1) {
    console.error(`ANCHOR-FAIL [${label}] hits=${hits.length} -> ${hits.join(',')}`);
    process.exit(1);
  }
  return hits[0];
}

// ---- 锚点（0-based）----
const aTag = findOne((l) => l.startsWith('/// 批量加标签弹层'), 'tag.doc');
const aFab = findOne((l) => l.startsWith('/// 书架 FAB'), 'fab.doc');
const aLp = findOne(
  (l) => l.startsWith('/// 长按书籍菜单：项与顺序来自设置'),
  'longpress.doc',
);
const aRing = findOne(
  (l) => l.startsWith('class _GoalRingPainter extends CustomPainter {'),
  'ring.class',
);
const aState = findOne(
  (l) => l.startsWith('class _ShelfPageState extends ConsumerState<ShelfPage> {'),
  'state.class',
);
const aLastImport = findOne(
  (l) => l.startsWith("import '../widgets/bs_cover.dart';"),
  'last.import',
);
if (!(aState < aTag && aTag < aFab && aFab < aLp && aLp < aRing)) {
  console.error('ORDER-FAIL', { aState, aTag, aFab, aLp, aRing });
  process.exit(1);
}

function sliceBlock(start, endExclusive) {
  const b = lines.slice(start, endExclusive);
  while (b.length && b[b.length - 1].trim() === '') b.pop();
  if (!b.length || !b[b.length - 1].trim().endsWith('}')) {
    console.error('END-FAIL', JSON.stringify(b[b.length - 1]));
    process.exit(1);
  }
  return b;
}

const blocks = [
  {
    out: 'shelf_batch_tag.dart',
    header: [
      "part of 'shelf_page.dart';",
      '',
      '// 治理G7d1a：批量加标签弹层自 shelf_page 尾随块整块外提（行为零改动）。',
      '// 自持 controller，避免 pop 动画期间用到已 dispose 的控制器。',
    ],
    body: sliceBlock(aTag, aFab),
    members: [
      'class _BatchTagSheet extends StatefulWidget {',
      'State<_BatchTagSheet> createState() => _BatchTagSheetState();',
      'class _BatchTagSheetState extends State<_BatchTagSheet> {',
      'void _pick(String t) => Navigator.of(context).pop(t);',
    ],
  },
  {
    out: 'shelf_fab.dart',
    header: [
      "part of 'shelf_page.dart';",
      '',
      '// 治理G7d1a：书架 FAB（＋ 新书）自 shelf_page 尾随块整块外提（行为零改动）。',
    ],
    body: sliceBlock(aFab, aLp),
    members: [
      'class GradShelfFab extends StatelessWidget {',
      'const GradShelfFab({super.key, required this.onTap});',
    ],
  },
  {
    out: 'shelf_long_press.dart',
    header: [
      "part of 'shelf_page.dart';",
      '',
      '// 治理G7d1a：长按菜单（kLpAll / kLpDefault / showLongPressSheet）自 shelf_page',
      '// 顶层整块外提（同库 part·外部 import shelf_page.dart 的 show 名单不受影响）。',
      '// 项与顺序来自设置（read.longPress · §6 · 弹层自带「调整长按菜单」入口）。',
    ],
    body: sliceBlock(aLp, aRing),
    members: [
      "const kLpAll = ['计时', '记摘录', '改分区', '移书单', '标记读完', '多选', '删除'];",
      "const kLpDefault = '计时,记摘录,改分区,移书单,删除';",
      'Future<void> showLongPressSheet(BuildContext context, WidgetRef ref, Book b) {',
    ],
  },
  {
    out: 'shelf_goal_ring.dart',
    header: [
      "part of 'shelf_page.dart';",
      '',
      '// 治理G7d1a：年度目标环 CustomPainter 自 shelf_page 尾随块整块外提（行为零改动）。',
    ],
    body: sliceBlock(aRing, lines.length),
    members: [
      'class _GoalRingPainter extends CustomPainter {',
      'bool shouldRepaint(_GoalRingPainter old) => old.frac != frac;',
    ],
  },
];

// ---- 主文件：删除 [aTag, EOF) 整段，插入 part 指令 ----
const keep = lines.slice(0, aTag);
while (keep.length && keep[keep.length - 1].trim() === '') keep.pop();
keep.push('');
keep.splice(aLastImport + 1, 0, '', ...blocks.map((b) => `part '${b.out}';`));
while (keep.length && keep[keep.length - 1].trim() === '') keep.pop();
keep.push('');

const keptText = keep.join('\n');
const bad = [];
const partTexts = {};
for (const b of blocks) {
  const t = [...b.header, ...b.body, ''].join('\n');
  partTexts[b.out] = t;
  for (const m of b.members) {
    const inPart = t.split('\n').filter((l) => l.trim() === m).length;
    const inKeep = keptText.split('\n').filter((l) => l.trim() === m).length;
    if (inPart !== 1 || inKeep !== 0) bad.push({ out: b.out, m, inPart, inKeep });
  }
  // 纯移动块：不应新增 setState（本文件实测全局 0 处）
  const scc = t.split('\n').filter((l) => l.includes('setState(')).length;
  if (scc !== 0) bad.push({ out: b.out, m: 'setState 应为 0', got: scc });
  // 块首行必须是 part of（房规）
  if (t.split('\n')[0] !== "part of 'shelf_page.dart';")
    bad.push({ out: b.out, m: '首行 part of' });
}
// 主文件保留成员仍在（未被误删）
for (const m of [
  'class ShelfPage extends ConsumerStatefulWidget {',
  'class _ShelfPageState extends ConsumerState<ShelfPage> {',
  'Widget build(BuildContext context) {',
]) {
  if (keptText.split('\n').filter((l) => l.trim() === m).length !== 1)
    bad.push({ m: 'keep 侧缺失 ' + m });
}

const moved = blocks.reduce((s, b) => s + b.body.length, 0);
const before = origLen;
const after = keep.length;
const volumeOk = before - after >= moved - 4 && before - after <= moved + 8;

console.log(
  JSON.stringify(
    {
      moved,
      parts: blocks.map((b) => `${b.out}:${b.body.length}`),
      shelfPage: `${before} -> ${after}`,
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
for (const b of blocks) fs.writeFileSync(path.join(DIR, b.out), partTexts[b.out]);
fs.writeFileSync(SRC, keptText);
console.log('WRITTEN');
