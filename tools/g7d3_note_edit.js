// 治理G7d③ 一次性脚本：note_edit_page.dart 六个区头段外提为 extension part
// 用法：node tools/g7d3_note_edit.js --groups focus,rich   （加 --dry 只看统计）
// 与 shelf 刀的差量：本文件有 23 处 setState → 在搬运算块内每个 setState 行上方按同缩进
// 插一条 `// ignore: invalid_use_of_protected_member`，并断言 ignore 数＝setState 数。
// 护栏：锚点唯一命中 / 块内禁 @override·super. / 成员「恰好出现一次」双向断言 / 体积校验 / .bak 快照。
const fs = require('fs');
const path = require('path');

const DIR = 'lib/features/journal/presentation';
const SRC = path.join(DIR, 'note_edit_page.dart');
const MAIN = 'note_edit_page.dart';
const DRY = process.argv.includes('--dry');
const gIdx = process.argv.indexOf('--groups');
const wanted = (gIdx >= 0 ? process.argv[gIdx + 1] : '').split(',').filter(Boolean);
if (!wanted.length) {
  console.error('USAGE: --groups focus,rich,mode,save,swipe,layout');
  process.exit(1);
}

const norm = (s) => s.replace(/\r\n/g, '\n');
const lines = norm(fs.readFileSync(SRC, 'utf8')).split('\n');
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
const sec = (frag) => (l) => l.trim().startsWith('// ----------') && l.includes(frag);

// layout 段的结束＝build 之前的 @override 行（@override 必须留在类内）
const buildIdx = findOnce(lines, (l) => l.trim() === 'Widget build(BuildContext context) {', 'build');
let overrideIdx = buildIdx;
while (overrideIdx > 0 && lines[overrideIdx].trim() !== '@override') overrideIdx--;
if (lines[overrideIdx].trim() !== '@override') {
  console.error('NO-OVERRIDE-BEFORE-BUILD');
  process.exit(1);
}

const ALL = {
  focus: {
    out: 'note_edit_focus.dart',
    ext: '_NoteFocusMode',
    start: sec('专注模式'),
    end: sec('富文本'),
    header: [
      "part of 'note_edit_page.dart';",
      '',
      '// 治理G7d③：专注模式段落群自 _NoteEditPageState 移入同库扩展（行为零改动·直访私有字段）。',
      '// 段落即编辑（段击聚焦·淡出）/ 全局退格拦截并入上段 / 段落↔_bodyCtl 单一真源同步 /',
      '// MD 图片独占段的缩略卡呈现与删除。群内含 static _splitParas 与 static _imgPara（互引不出群）。',
    ],
    members: [
      'void _disposeLater(List<Object> disposable) {',
      'FocusNode _newParaNode() {',
      'bool _onGlobalKey(KeyEvent event) {',
      'void _resetParas(String text) {',
      'static List<String> _splitParas(String text) {',
      'String _joinedParas() {',
      'void _syncBodyAfterReset() {',
      'void _flushParas() {',
      'void _paraChanged(int i, String v) {',
      'static final _imgPara = RegExp(',
      'Widget _paraField(int i, {bool lineNum = false}) {',
      'Widget _paraInput(int i, {required bool dimmed, required bool highlight}) {',
      'Widget _paraImage(int i, String path) {',
      'void _showImageFull(String path) => showImageLightbox(context, path);',
      'void _removePara(int i) {',
    ],
  },
  rich: {
    out: 'note_edit_rich.dart',
    ext: '_NoteRich',
    start: sec('富文本'),
    end: sec('模式 / 快捷栏'),
    header: [
      "part of 'note_edit_page.dart';",
      '',
      '// 治理G7d③：V1.29批B 富文本群自 _NoteEditPageState 移入同库扩展（行为零改动）。',
      '// Quill 文档↔Delta JSON / 属性开关（标题·列表·居中·链接·待办·插图·字号弹层）/',
      '// 标题字段·富文本编辑器·底栏图标钮与二级行。',
    ],
    members: [
      'Document _richDocFromContent(String content) {',
      'QuillController _newRich(String content) => QuillController(',
      'void _rebuildRich(String content) {',
      'void _onRichChanged() {',
      'void _richToggle(Attribute<dynamic> attr) {',
      'void _richSetHeader(int level) {',
      'void _richListAs(Attribute target) {',
      'void _richCenter() {',
      'Future<void> _richLink() async {',
      'Future<void> _openFontSheet() async {',
      'void _richTask() {',
      'Future<void> _richImage() async {',
      'Future<void> _plainAttach() async {',
      'DefaultStyles _richStyles() {',
      'Widget _titleField() {',
      'Widget _richEditor() {',
      'Widget _pwIconBtn(String key, IconData icon, VoidCallback onTap, String tip) {',
      'Widget _pwSep() => Container(',
      'Widget _toolBarArea() {',
      'Widget _pwSubRow(bool rich) {',
    ],
  },
  mode: {
    out: 'note_edit_mode.dart',
    ext: '_NoteModeKit',
    start: sec('模式 / 快捷栏'),
    end: sec('保存'),
    header: [
      "part of 'note_edit_page.dart';",
      '',
      '// 治理G7d③：模式/快捷栏/纸感群自 _NoteEditPageState 移入同库扩展（行为零改动）。',
      '// 三态切换 / MD 工具条与撤销重做栈 / 标题级与列表级快捷 / 聚焦开关 / 类型切换 / 小工具抽屉。',
    ],
    members: [
      'void _setMode(NoteEditMode m) {',
      'void _tool(String k) {',
      'void _mdBarTap(String k) {',
      'void _mdPushUndo() {',
      'void _mdUndoStep() {',
      'void _mdRedoStep() {',
      'void _mdSetHeading(int lv) {',
      'void _toggleFocus() {',
      'void _setKind(String next) {',
      'void _openKit() {',
    ],
  },
  save: {
    out: 'note_edit_save.dart',
    ext: '_NoteSave',
    start: sec('保存'),
    end: sec('左右滑动'),
    header: [
      "part of 'note_edit_page.dart';",
      '',
      '// 治理G7d③：保存群自 _NoteEditPageState 移入同库扩展（行为零改动）。',
      '// 变更标脏 / 版本快照（停输 30s·每 +500 字）/ 落库 / 防抖自动保存 / 保存并退出。',
    ],
    members: [
      'void _onChanged(String _) {',
      'Future<void> _maybeSnap({required bool idle}) async {',
      'Future<Note> _persist() async {',
      'Future<void> _autoSave() async {',
      'Future<void> _saveAndExit() async {',
    ],
  },
  swipe: {
    out: 'note_edit_swipe.dart',
    ext: '_NoteSwipe',
    start: sec('左右滑动'),
    end: sec('布局'),
    header: [
      "part of 'note_edit_page.dart';",
      '',
      '// 治理G7d③：轮8③ 左右滑动/←→ 切笔记群自 _NoteEditPageState 移入同库扩展（行为零改动）。',
      '// Listener 旁路追踪 + 按当前排序/筛选取上下一篇 + 换笔记载入；字数与统计文案 getter 同群。',
    ],
    members: [
      'void _onSwipeDown(PointerDownEvent e) {',
      'void _onSwipeMove(PointerMoveEvent e) {',
      'Future<void> _switchNote(int dir) async {',
      'Future<void> _loadNote(Note n) async {',
      'int get _words {',
      'String get _countText {',
    ],
  },
  layout: {
    out: 'note_edit_layout.dart',
    ext: '_NoteLayout',
    byIndex: true,
    start: sec('布局'),
    end: () => overrideIdx,
    header: [
      "part of 'note_edit_page.dart';",
      '',
      '// 治理G7d③：布局群自 _NoteEditPageState 移入同库扩展（行为零改动）。',
      '// MD 工具钮 / 源码编辑器 / 预览 / 待办勾选与联动 / 三态主体区。build() 仍留类内。',
    ],
    members: [
      'Widget _mdToolBtn(String k, String glyph, String tip) {',
      'Widget _srcEditor() {',
      'Widget _preview({double fontSize = 14}) {',
      'void _toggleTask(int idx, bool check) {',
      'Future<void> _completeTodo(String? title) async {',
      'Future<int> _syncTodoLines() async {',
      'Widget _bodyArea() {',
    ],
  },
};

const groups = wanted.map((k) => ({ key: k, ...ALL[k] }));
for (const g of groups) {
  if (!g.out) {
    console.error('UNKNOWN-GROUP ' + g.key);
    process.exit(1);
  }
  g.s = findOnce(lines, g.start, `${g.key}.start`);
  g.e = g.byIndex ? g.end() : findOnce(lines, g.end, `${g.key}.end`);
}
const sorted = groups.slice().sort((a, b) => a.s - b.s);
for (let i = 0; i < sorted.length; i++) {
  if (!(sorted[i].s < sorted[i].e)) {
    console.error('ORDER-FAIL', sorted[i].key);
    process.exit(1);
  }
  if (i + 1 < sorted.length && !(sorted[i].e <= sorted[i + 1].s)) {
    console.error('OVERLAP-FAIL', sorted[i].key, sorted[i + 1].key);
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

// 块内每个 setState 行上方同缩进插 ignore（自底向上，行号不漂）
function addIgnores(blk) {
  const out = blk.slice();
  let n = 0;
  for (let i = out.length - 1; i >= 0; i--) {
    const l = out[i];
    if (l.includes('setState(') && !l.trim().startsWith('//')) {
      const ind = l.match(/^ */)[0];
      out.splice(i, 0, `${ind}// ignore: invalid_use_of_protected_member`);
      n++;
    }
  }
  return { blk: out, ignores: n };
}

const keep = lines.slice();
for (const g of sorted.slice().reverse()) {
  const raw = block(keep, g.s, g.e);
  g.rawLen = raw.length;
  const { blk, ignores } = addIgnores(raw);
  g.body = blk;
  g.ignores = ignores;
  for (let i = g.s + raw.length - 1; i >= g.s; i--) keep.splice(i, 1);
  while (keep[g.s] !== undefined && keep[g.s].trim() === '') keep.splice(g.s, 1);
  keep.splice(g.s, 0, '');
}

// part 指令：追加到已有 part 块末尾（无则插到末条 import 之后并补空行）
let insAt = -1;
let hadParts = false;
for (let i = 0; i < keep.length; i++)
  if (keep[i].startsWith("part '")) {
    insAt = i;
    hadParts = true;
  }
if (!hadParts) {
  insAt = findOnce(keep, (l) => l.startsWith("import 'widgets/note_sheets.dart';"), 'last.import');
  keep.splice(insAt + 1, 0, '');
  insAt += 1;
}
keep.splice(insAt + 1, 0, ...groups.map((g) => `part '${g.out}';`));
while (keep.length && keep[keep.length - 1].trim() === '') keep.pop();
keep.push('');

const keptText = keep.join('\n');
const bad = [];
const partTexts = {};
for (const g of groups) {
  const t = [
    ...g.header,
    `extension ${g.ext} on _NoteEditPageState {`,
    ...g.body,
    '}',
    '',
  ].join('\n');
  partTexts[g.out] = t;
  const pl = t.split('\n');
  for (const m of g.members) {
    const inPart = pl.filter((l) => l.trim().startsWith(m)).length;
    const inKeep = keptText.split('\n').filter((l) => l.trim().startsWith(m)).length;
    if (inPart !== 1 || inKeep !== 0) bad.push({ out: g.out, m, inPart, inKeep });
  }
  const scc = pl.filter((l) => l.includes('setState(')).length;
  const igc = pl.filter((l) => l.trim() === '// ignore: invalid_use_of_protected_member').length;
  if (scc !== igc) bad.push({ out: g.out, m: 'ignore 数≠setState 数', got: `${igc}/${scc}` });
  if (pl.filter((l) => l.trim() === '@override').length)
    bad.push({ out: g.out, m: '块内不应有 @override' });
  if (pl.filter((l) => /(^|[^.\w])super\./.test(l)).length)
    bad.push({ out: g.out, m: '块内不应有 super.' });
  if (pl.filter((l) => /^  (final |late )/.test(l)).length)
    bad.push({ out: g.out, m: '扩展体疑似实例字段' });
  if (pl[0] !== `part of '${MAIN}';`) bad.push({ out: g.out, m: '首行 part of' });
  g.stCount = scc;
}
for (const m of ['Widget build(BuildContext context) {', '@override']) {
  const n = keptText.split('\n').filter((l) => l.trim() === m).length;
  if (n < 1) bad.push({ m: 'keep 侧缺失 ' + m });
}

const moved = groups.reduce((s, g) => s + g.rawLen, 0);
const after = keep.length;
const volumeOk =
  origLen - after >= moved - 2 * groups.length - 2 &&
  origLen - after <= moved + 4 * groups.length + 4 &&
  after > 250;

console.log(
  JSON.stringify(
    {
      groups: wanted,
      moved,
      parts: groups.map((g) => `${g.out}:${g.rawLen}(setState ${g.stCount}/ignore ${g.ignores})`),
      noteEdit: `${origLen} -> ${after}`,
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
