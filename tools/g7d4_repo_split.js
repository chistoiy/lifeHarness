// 治理G7d④ 一次性脚本：read_repository.dart 按域外提 extension part（成员粒度切块·枢纽留类内）
// 用法：node tools/g7d4_repo_split.js --parts book,session   （加 --dry 只看统计）
//
// 与 note_edit 刀的差量：仓储无 State/setState → 免定点 ignore；改为「花括号深度切块 +
// 全局引用闭合断言」——extension 成员静态派发，跨扩展裸调用不解析，故任一被引用者
// 必须留类内（core）或与调用者同群。PLAN 即按此闭合条件定稿。
const fs = require('fs');
const path = require('path');

const DIR = 'lib/features/read/data';
const MAIN = 'read_repository.dart';
const SRC = path.join(DIR, MAIN);
const DRY = process.argv.includes('--dry');
const gIdx = process.argv.indexOf('--parts');
const wanted = (gIdx >= 0 ? process.argv[gIdx + 1] : '').split(',').filter(Boolean);
if (!wanted.length) {
  console.error('USAGE: --parts book,session,quote,toc,dict,list,stat,imp,expo');
  process.exit(1);
}

const norm = (s) => s.replace(/\r\n/g, '\n');
const lines = norm(fs.readFileSync(SRC, 'utf8')).split('\n');
const origLen = lines.length;

function code(s) {
  let out = '';
  let q = null;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q) {
      if (c === '\\') { i++; continue; }
      if (c === q) q = null;
      continue;
    }
    if (c === "'" || c === '"') { q = c; continue; }
    if (c === '/' && s[i + 1] === '/') break;
    out += c;
  }
  return out;
}
const delta = (s) => {
  let d = 0;
  for (const ch of code(s))
    if (ch === '{' || ch === '(' || ch === '[') d++;
    else if (ch === '}' || ch === ')' || ch === ']') d--;
  return d;
};

// ---- 切块（锚定「下一成员声明行」，不用花括号深度）----
// 坑（G7d④ 4c 首跑炸 397 个 error 后改刀法）：本文件有跨行相邻字符串拼接成员，如
//   String _quoteText(BookQuote q, Book b) =>
//       '《${b.title}》${q.chapter == null ? '' : ' · ${q.chapter}'}'
//       '${q.page == null ? '' : ' · ${q.page} 页'}\n${q.body}' …;
// 插值里嵌套引号，任何「先剥字符串再数括号/判句末」的词法都会在此错位而提前收块，
// 把函数体留在主文件里 → 语法炸。本文件房规够用：成员声明行必在缩进 2、非注释、
// 非收尾符开头，故「块尾＝下一声明行（含其上方注释）之前」，并对句末做断言兜底。
const classStart = lines.findIndex((l) => l.startsWith('abstract class _ReadRepoBase {'));
if (classStart < 0) { console.error('NO-BASE-CLASS'); process.exit(1); }
let classEnd = -1;
for (let i = classStart + 1; i < lines.length; i++)
  if (lines[i] === '}') { classEnd = i; break; }
if (classEnd < 0) { console.error('NO-BASE-END'); process.exit(1); }
const isDeclLine = (i) =>
  i > classStart &&
  i < classEnd &&
  /^  \S/.test(lines[i]) &&
  !/^  [});\]]/.test(lines[i]) &&
  !lines[i].trim().startsWith('//');
const decls = [];
for (let i = classStart + 1; i < classEnd; i++) if (isDeclLine(i)) decls.push(i);
const blocks = [];
// 上方注释随块走：先接紧邻注释/注解串；若再往上是一空行且空行之上仍是注释串，
// 一并接住（区头 // ---- X ---- 与其后的多行说明常与上一成员隔一空行）。
const absorbUp = (from) => {
  let k = from;
  while (k > 0 && lines[k - 1].trim() !== '' && /^\s*(@\w+|\/\/|\/\*)/.test(lines[k - 1])) k--;
  return k;
};
for (const d of decls) {
  let s = absorbUp(d);
  if (s - 1 > classStart && lines[s - 1].trim() === '') {
    const k2 = absorbUp(s - 1);
    if (k2 < s - 1) s = k2;
  }
  blocks.push({ decl: d, start: s, sig: lines[d].trim() });
}
// 块尾＝下一块 start 之前（注释/区头已划归下一块），再退掉尾部空行
for (let j = 0; j < blocks.length; j++) {
  let e = j + 1 < blocks.length ? blocks[j + 1].start - 1 : classEnd - 1;
  while (e >= blocks[j].start && lines[e].trim() === '') e--;
  blocks[j].end = e;
}
if (!blocks.length) { console.error('NO-MEMBER'); process.exit(1); }
const nameOf = (sig) => {
  const g = sig.match(/\bget (_?\w+)/) || sig.match(/\b(_?\w+)\s*[(=]/);
  return g ? g[1] : null;
};
for (const b of blocks) {
  b.name = nameOf(b.sig);
  const last = lines[b.end].trim();
  if (!/[;}]$/.test(last)) {
    console.error('END-FAIL', b.name, 'L' + (b.end + 1), JSON.stringify(last.slice(0, 60)));
    process.exit(1);
  }
}
const named = blocks.filter((b) => b.name);
const block = (n) => named.find((b) => b.name === n);

// ---- 刀路 PLAN：part → 成员（core＝留类内）----
const PLAN = {
  book: {
    out: 'read_repo_book.dart',
    ext: '_RepoBooks',
    doc: [
      '// 治理G7d④：书籍状态群与购书费用流水群自 _ReadRepoBase 移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。',
      '// 新增/更新/分区流转（单本与批量同语义）·批量加标签·软删；',
      '// 「购书费用 → L4/记账流水」整段随本群外提（唯一调用者 addBook/updateBook 在同群）。',
      '// 群内自用 static _stateValues 随迁；枢纽 allBooks/bookById/touchLastRead/_registerDictFor 留类内。',
    ],
    members: ['addBook', 'updateBook', '_stateValues', 'setBookState', 'bulkSetState', 'bulkAddTags', 'softDeleteBooks', '_syncFeeTxn'],
  },
  session: {
    out: 'read_repo_session.dart',
    ext: '_RepoSessions',
    doc: [
      '// 治理G7d④：计时会话群自 _ReadRepoBase 移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。',
      '// 单活会话开始/结束/就地补位·关闭与门槛·明细增删改与 L4 流水回写·聚合重算·',
      '// 今日/本周分钟与自然日列表。allSessions（被统计群跨群调用）与 dayStartMs（公开静态 API）留类内。',
    ],
    members: ['runningSession', 'startSession', 'endSession', 'stampSessionStart', '_close', 'sessionsOf', 'addManualSession', 'editSession', 'deleteSession', '_syncTxn', 'syncBookAgg', 'minutesOnDay', 'minutesThisWeek', 'readingDays'],
  },
  quote: {
    out: 'read_repo_quote.dart',
    ext: '_RepoQuotes',
    doc: [
      '// 治理G7d④：摘录群（查重入账/标签字典/复习档位/L5 跨模块分流）移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。',
      '// 群内自用 static reviewGapsMs 随迁（全仓无 ReadRepository.reviewGapsMs 外部调用，已核实）；',
      '// quotesOf/allQuotes 被导出群与统计群跨群调用，留类内。',
    ],
    members: ['reviewGapsMs', 'addQuote', 'updateQuote', 'quoteById', 'setQuoteStarred', 'softDeleteQuote', 'restoreQuote', 'quoteCount', 'quoteCountSince', 'recentQuotes', 'quoteBookIdsMatching', 'quoteTags', 'reviewOf', 'reviewMap', 'dueReviewCount', 'dueReviews', 'bumpReview', 'resetReview', 'holdReview', '_quoteText', 'quoteToDiary', 'quoteToTodo', 'quoteToNote', 'bookToNote'],
  },
  toc: {
    out: 'read_repo_toc.dart',
    ext: '_RepoToc',
    doc: [
      '// 治理G7d④：目录（两级·手动微调与粘贴导入）与记进度群移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。',
    ],
    members: ['tocOf', 'replaceToc', 'renameToc', 'moveToc', 'deleteToc', 'addTocPart', 'addTocSection', 'tocPrune', 'saveProgress'],
  },
  dict: {
    out: 'read_repo_dict.dart',
    ext: '_RepoDict',
    doc: [
      '// 治理G7d④：书架资料字典的引用计数与改名联动群移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。',
      '// dictOf/dictAdd 被摘录群跨群调用，留类内。',
    ],
    members: ['dictRefCount', 'dictRefCounts', 'dictRename', 'dictDelete'],
  },
  list: {
    out: 'read_repo_list.dart',
    ext: '_RepoLists',
    doc: [
      '// 治理G7d④：书单群（手动 items / 年度 auto_year 动态成员）移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。',
      '// allLists 被导出群跨群调用，留类内。',
    ],
    members: ['findAutoYear', 'addList', 'listById', 'updateList', 'setListBooks', 'addBookToList', 'removeBookFromList', 'softDeleteList', 'listMembers'],
  },
  stat: {
    out: 'read_repo_stat.dart',
    ext: '_RepoStats',
    doc: [
      '// 治理G7d④：统计聚合群（p-readstat 数据源）移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。',
      '// 逐日分钟/逐日摘录/时段直方/费用/字数/本月摘录/本年读完；跨群只调类内枢纽。',
    ],
    members: ['dayLogYear', 'dayQuotesYear', 'hourHistogram', 'feeTotals', 'doneWords', 'quotesThisMonth', 'doneThisYear'],
  },
  imp: {
    out: 'read_repo_import.dart',
    ext: '_RepoImport',
    doc: [
      '// 治理G7d④：导入群（三级去重·整批事务·撤销本批·书单导入）移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。',
    ],
    members: ['findBookFor', 'previewImport', 'commitImport', 'undoImportBatch', 'importBookList'],
  },
  expo: {
    out: 'read_repo_export.dart',
    ext: '_RepoExport',
    ext2: '_RepoDouban',
    doc: [
      '// 治理G7d④：导出群（MD 按书分组 / JSON 书架备份）与豆瓣元数据缓存群移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。',
    ],
    members: ['buildQuotesMd', 'buildBookQuotesMd', 'buildBackupJson', 'doubanCacheRow', 'doubanCachePut', 'doubanCacheCount', 'doubanCacheClear'],
  },
};
const partOfMember = new Map();
for (const [k, p] of Object.entries(PLAN)) for (const m of p.members) partOfMember.set(m, k);
const part = (name) => partOfMember.get(name) ?? 'core';

// 1) 计划成员必须逐一存在且唯一
const byName = new Map();
for (const b of blocks) {
  if (!b.name) continue;
  if (byName.has(b.name)) { console.error('DUP-MEMBER', b.name); process.exit(1); }
  byName.set(b.name, b);
}
const bad = [];
const sigSeen = new Map();
for (const b of blocks) if (b.name) sigSeen.set(b.sig, (sigSeen.get(b.sig) ?? 0) + 1);
for (const [s, n] of sigSeen) if (n > 1) bad.push(`DUP-SIG x${n} ${s.slice(0, 50)}`);
// 计划成员只在本批必须存在（前几批已外提的成员自然不在基类里了）
for (const k of wanted) {
  if (!PLAN[k]) bad.push(`UNKNOWN-GROUP ${k}`);
  else for (const m of PLAN[k].members) if (!byName.has(m)) bad.push(`PLAN-MISS ${k}/${m}`);
}

// 2) 全局引用闭合：任一被引用者若与他群不同群且不在 core → 编译期裸调用不可达
const refSites = new Map(); // target -> Set<`${from}>line`>
let edgeTotal = 0;
for (const b of blocks) {
  for (let i = b.start; i <= b.end; i++) {
    if (i === b.decl) continue;
    const c = code(lines[i]);
    const names = new Set();
    for (const m of c.matchAll(/([A-Za-z_]\w*)\s*\(/g)) names.add(m[1]);
    for (const m of c.matchAll(/\b(reviewGapsMs|_stateValues|_dayMs|dayStartMs|_rng|db)\b/g)) names.add(m[1]);
    for (const n of names) {
      // 目标可能是本批/他批计划成员（前批已外提者不在 byName 里，但计划归属仍有效）
      if (n === b.name || (!byName.has(n) && !partOfMember.has(n))) continue;
      edgeTotal++;
      if (part(n) !== part(b.name) && part(n) !== 'core') {
        const key = `${b.name}[${part(b.name)}] → ${n}[${part(n)}]`;
        if (!refSites.has(key)) refSites.set(key, new Set());
        refSites.get(key).add(`L${i + 1}`);
      }
    }
  }
}
for (const [k, v] of refSites) bad.push(`CROSS-EXT ${k} @ ${[...v].join(',')}`);

// 3) 本批块内禁：实例字段（extension 不允许）· @override · super.
const groups = wanted.map((k) => ({ key: k, ...PLAN[k] }));
const bodies = new Map();
for (const g of groups) {
  const bs = g.members.map((m) => byName.get(m)).sort((a, b) => a.start - b.start);
  for (const b of bs) {
    for (let i = b.start; i <= b.end; i++) {
      const t = lines[i];
      if (/^  (final |late )/.test(t)) bad.push(`FIELD-IN-EXT ${g.key} L${i + 1} ${t.trim().slice(0, 40)}`);
      if (t.trim() === '@override') bad.push(`OVERRIDE-IN-EXT ${g.key} L${i + 1}`);
      if (/(^|[^.\w])super\./.test(t)) bad.push(`SUPER-IN-EXT ${g.key} L${i + 1}`);
    }
    bodies.set(b.name, lines.slice(b.start, b.end + 1));
  }
  g.sorted = bs;
  g.rawLen = bs.reduce((s, b) => s + (b.end - b.start + 1), 0);
}

// ---- 主文件：摘除本批成员，空行折叠 ----
const drop = new Set();
for (const g of groups) for (const b of g.sorted) for (let i = b.start; i <= b.end; i++) drop.add(i);
let kept = lines.filter((_, i) => !drop.has(i));
kept = kept
  .join('\n')
  .replace(/\n{3,}/g, '\n\n')
  .split('\n');
while (kept.length && kept[kept.length - 1].trim() === '') kept.pop();
kept.push('');
// 类收尾前不留空行
for (let i = kept.length - 2; i > 0; i--) {
  if (kept[i].trim() === '' && /^\S/.test(kept[i + 1])) { kept.splice(i, 1); break; }
}

// ---- part 指令：追加到已有 part 块末尾（无则末条 import 之后）----
let insAt = -1;
let hadParts = false;
for (let i = 0; i < kept.length; i++)
  if (kept[i].startsWith("part '")) { insAt = i; hadParts = true; }
if (!hadParts) {
  insAt = kept.reduce((acc, l, i) => (l.startsWith('import ') ? i : acc), -1);
  if (insAt < 0) { console.error('NO-IMPORT-ANCHOR'); process.exit(1); }
  kept.splice(insAt + 1, 0, '');
  insAt += 1;
}
kept.splice(insAt + 1, 0, ...groups.map((g) => `part '${g.out}';`));

// ---- with 子句：本批 mixin 追加进 ReadRepository 的 with 列表（顺序＝part 顺序）----
const newMixins = groups.flatMap((g) => [g.ext, ...(g.ext2 ? [g.ext2] : [])]);
const clsRe = /class ReadRepository extends _ReadRepoBase(\s+with\s+[_\w\s,]+?)?\s*\{/;
const cm = kept.join('\n').match(clsRe);
if (!cm) { console.error('NO-READREPO-CLASS'); process.exit(1); }
const existing = (cm[1] || '')
  .replace(/^\s*with/, '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
const allMixins = [...new Set([...existing, ...newMixins])];
for (const x of existing) if (!/^_Repo[A-Za-z]+$/.test(x)) bad.push(`WITH-SUSPECT ${x}`);
const clause = allMixins.length
  ? 'class ReadRepository extends _ReadRepoBase\n    with\n        ' +
    allMixins.join(',\n        ') +
    ' {'
  : 'class ReadRepository extends _ReadRepoBase {';
kept = kept.join('\n').replace(clsRe, () => clause).split('\n');
for (const x of allMixins) {
  const n = kept.filter((l) => l.trim() === `${x},` || l.trim() === `${x} {`).length;
  if (n !== 1) bad.push(`WITH-ONCE ${x} hits=${n}`);
}

// ---- part 文件正文 ----
const keptText = kept.join('\n');
const partTexts = {};
for (const g of groups) {
  const out = [
    `part of '${MAIN}';`,
    '',
    ...g.doc,
    `mixin ${g.ext} on _ReadRepoBase {`,
  ];
  g.sorted.forEach((b, idx) => {
    if (idx > 0) out.push('');
    if (g.ext2 && b.name === 'doubanCacheRow') out.push('}', '', `mixin ${g.ext2} on _ReadRepoBase {`);
    out.push(...bodies.get(b.name));
  });
  out.push('}', '');
  partTexts[g.out] = out.join('\n');
}

// ---- 成员「恰好出现一次」双向断言 ----
for (const g of groups) {
  const pl = partTexts[g.out].split('\n');
  for (const m of g.members) {
    const sig = byName.get(m).sig;
    const inPart = pl.filter((l) => l.trim() === sig).length;
    const inKeep = keptText.split('\n').filter((l) => l.trim() === sig).length;
    if (inPart !== 1 || inKeep !== 0) bad.push(`ONCE ${g.key}/${m} part=${inPart} keep=${inKeep} sig=${sig.slice(0, 40)}`);
  }
  if (pl[0] !== `part of '${MAIN}';`) bad.push(`PART-OF ${g.out}`);
}

const moved = groups.reduce((s, g) => s + g.rawLen, 0);
const after = kept.length;
const nBlocks = groups.reduce((s, g) => s + g.members.length, 0);
// 体积护栏：净减 ∈ [moved, moved + 每块空行折叠 1 行 + part 指令行]，防误删
const volumeOk =
  origLen - after >= moved - 2 * groups.length &&
  origLen - after <= moved + nBlocks + 2 * groups.length + 4;

console.log(
  JSON.stringify(
    {
      batches: wanted,
      parts: groups.map((g) => `${g.out}:${g.rawLen}`),
      moved,
      main: `${origLen} -> ${after}`,
      volumeOk,
      edgeTotal,
      crossExtRefs: [...refSites.keys()],
      bad,
      DRY,
    },
    null,
    2
  )
);
if (bad.length || !volumeOk) process.exit(1);
if (process.argv.includes('--dump'))
  console.log(
    blocks.map((b) => `${b.name ?? '(anon)'}\tL${b.start + 1}..L${b.end + 1}\t${part(b.name)}\t${lines[b.end].trim().slice(0, 40)}`).join('\n')
  );
if (DRY) process.exit(0);

fs.writeFileSync(SRC + '.bak', lines.join('\n'));
for (const g of groups) fs.writeFileSync(path.join(DIR, g.out), partTexts[g.out]);
fs.writeFileSync(SRC, keptText);
console.log('WRITTEN');
