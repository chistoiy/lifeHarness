/* g5_schema_split2.js · 治理G5 B方案：域库外提 + DbSchema 别名 API
   移动：类成员常量/组常量 → lib/core/database/schema/<dom>.dart 顶层（原名，域内 $tX 零改动）；
         migrations 逐版本条目 → 所属域文件 final Map<int,List<String>> mig；
   保留：version/fileName/pluginPrefix/createStatements 字面量原样在类内。
   守护：成员全覆盖、迁移版本键互斥、跨域引用必须能解析为某域成员。三门禁后提交。 */
const fs = require('fs');
const path = require('path');
const SRC = 'lib/core/database/schema.dart';
const DIR = 'lib/core/database/schema';
const src = fs.readFileSync(SRC, 'utf8');
const fail = (m) => { console.error('GUARD-FAIL: ' + m); process.exit(1); };
const clsStart = src.indexOf('class DbSchema');
if (clsStart < 0) fail('无 class DbSchema');
const bodyStart = src.indexOf('{', clsStart) + 1;
const bodyOpen = bodyStart;
const clsEnd = src.lastIndexOf('\n}');
const bodyFull = src.slice(bodyOpen, clsEnd);
/* 类尾静态方法区（如 _ledgerSeeds）整体外提至 ledger 顶层 */
const mIdx = bodyFull.search(/\r?\n {2}static [\w<>, ]+\([\w ]*\)\s*\{/);
let methodZone = '', body = bodyFull;
if (mIdx >= 0) {
  methodZone = bodyFull.slice(mIdx).trimEnd();
  if (!/\}\s*$/.test(methodZone)) fail('方法区尾部异常');
  body = bodyFull.slice(0, mIdx);
}

/* ---- 1. 成员切分（状态机） ---- */
const members = [];
let i = 0, depth = 0, q = null, chunk = '';
while (i < body.length) {
  const c = body[i], three = body.slice(i, i + 3);
  if (!q) {
    if (c === '/' && body[i + 1] === '/') { const e = body.indexOf('\n', i); i = e < 0 ? body.length : e; continue; }
    if (three === "'''") { q = three; chunk += three; i += 3; continue; }
    if (c === "'" || c === '"') { q = c; chunk += c; i++; continue; }
    if ('([{'.includes(c)) depth++; else if (')]}'.includes(c)) depth--;
    if (c === ';' && depth === 0) { members.push(chunk + ';'); chunk = ''; i++; continue; }
    chunk += c; i++; continue;
  }
  if (c === '\\') { chunk += body.slice(i, i + 2); i += 2; continue; }
  if (q === "'''") { if (three === "'''") { chunk += three; q = null; i += 3; continue; } chunk += c; i++; continue; }
  if (c === q) { chunk += c; q = null; i++; continue; }
  chunk += c; i++;
}
if (chunk.trim() && !/^[\s]*$/.test(chunk)) fail('尾部残留: ' + JSON.stringify(chunk.slice(0, 50)));

/* ---- 2. 域规则 ---- */
const RULES = [
  ['read', /^(tBook|tDoubanMeta|catReadingId|book\w*SchemaStatements|doubanMetaSchemaStatements)/],
  ['habit', /^(tHabit|habit\w*SchemaStatements)/],
  ['ledger', /^(tLedger|tFinance|ledgerSchemaStatements|ledgerCatOther)/],
  ['care', /^(tCare|careTables|careSchemaStatements)/],
  ['days', /^(tDays|tDayPreps|tReminderItems|daysSchemaStatements)/],
  ['items', /^(tItems|tItem|itemSchemaStatements)/],
  ['goals', /^(tGoal|tKrUpdates|goalSchemaStatements)/],
  ['ai', /^(tAiCalls|aiCallSchemaStatements)/],
  ['core', /^(tTodos|tEvents|tJournal|tDiaryTemplates|tTemplateSections|tNotes|tNoteSnapshots|tNoteFolders|tInbox|tSettings|tHealth|tTimeBlocks|tCategories|tWeatherDaily|categorySeed)/],
];
const PREFIX = { core: 'c', read: 'r', habit: 'h', ledger: 'l', care: 'e', days: 'd', items: 'm', goals: 'g', ai: 'a' };
const KEEP = new Set(['version', 'fileName', 'pluginPrefix', 'createStatements', 'migrations']);
const declRe = /static\s+(const|final)\s+([\w<>,\s]+?)\s+(\w+)\s*=/;
const moved = new Map(); const keptDecls = [];
for (const raw of members) {
  if (/const\s+DbSchema\._\(\);/.test(raw)) continue; // 私有构造单独保留
  const m = raw.match(declRe);
  if (!m) { if (raw.trim()) fail('无法解析成员: ' + raw.trim().slice(0, 70)); continue; }
  const name = m[3], pre = raw.slice(0, m.index);
  if (KEEP.has(name)) { if (name !== 'migrations') keptDecls.push(raw); continue; }
  const dom = RULES.find(([, re]) => re.test(name));
  if (!dom) fail('未映射: ' + name);
  moved.set(name, { kind: m[1], type: m[2].trim(), dom: dom[0], pre, value: raw.slice(m.index + m[0].length, raw.length - 1) });
}
if (moved.size < 88) fail('moved=' + moved.size);
const domNames = {}; for (const [n, o] of moved) (domNames[o.dom] = domNames[o.dom] || new Set()).add(n);

/* ---- 3. 跨域引用重写（仅用于迁出文本） ---- */
function refsOf(text) {
  const s = new Set();
  for (const m of text.matchAll(/\$\{(\w+)\}|\$(\w+)\b|\.\.\.(\w+)\b/g)) { const n = m[1] || m[2] || m[3]; if (moved.has(n)) s.add(n); }
  return [...s];
}
function rewrite(text, selfDom) {
  return text.replace(/\$\{(\w+)\}|\$(\w+)\b|\.\.\.(\w+)\b/g, (all, a, b, c) => {
    const n = a || b || c;
    if (!moved.has(n) || moved.get(n).dom === selfDom) return all;
    const p = PREFIX[moved.get(n).dom];
    const out = '${' + p + '.' + n + '}';
    if (a) return out; if (b) return /\(/.test(all.slice(1 + b.length)) || true ? (all.includes('{') ? out : out) : out;
    return '...' + p + '.' + n;
  });
}
/* $name 后无特殊字符时简单替换为 ${p.name} 即可 */
function rewrite2(text, selfDom) {
  return text.replace(/\$\{(\w+)\}|\$(\w+)\b|\.\.\.(\w+)\b/g, (all, br, dol, spr) => {
    const n = br || dol || spr;
    if (!moved.has(n) || moved.get(n).dom === selfDom) return all;
    const p = PREFIX[moved.get(n).dom];
    return spr !== undefined ? '...' + p + '.' + n : '${' + p + '.' + n + '}';
  });
}

/* ---- 4. migrations 逐版本分域 ---- */
const mgRaw = members.find(t => /\bmigrations\s*=/.test(t));
const mgDecl = mgRaw.match(declRe);
const mgBody = mgRaw.slice(mgRaw.indexOf('{', mgRaw.indexOf('migrations')) + 1, mgRaw.lastIndexOf('}'));
function splitTop(text, open, close) {
  const parts = []; let depth = 0, q = null, cur = '', i = 0;
  while (i < text.length) {
    const c = text[i], three = text.slice(i, i + 3);
    if (!q) {
      if (three === "'''" ) { q = three; cur += three; i += 3; continue; }
      if (c === "'" || c === '"') { q = c; cur += c; i++; continue; }
      if ('([{'.includes(c)) depth++; else if (')]}'.includes(c)) depth--;
      if (c === ',' && depth === 0) { parts.push(cur); cur = ''; i++; continue; }
      cur += c; i++; continue;
    }
    if (c === '\\') { cur += text.slice(i, i + 2); i += 2; continue; }
    if (q === "'''") { if (three === "'''") { cur += three; q = null; i += 3; continue; } cur += c; i++; continue; }
    if (c === q) { cur += c; q = null; i++; continue; } cur += c; i++;
  }
  if (cur.trim()) parts.push(cur);
  return parts;
}
const migParts = {}; const seenKeys = new Set(); let migN = 0;
for (const e of splitTop(mgBody, '{', '}')) {
  const key = e.match(/^\s*(\d+)\s*:/);
  if (!key) { if (e.trim()) fail('迁移条目无法解析: ' + JSON.stringify(e.trim().slice(0, 60))); continue; }
  const k = +key[1];
  if (seenKeys.has(k)) fail('版本键重复: ' + k); seenKeys.add(k);
  const rs = refsOf(e);
  const doms = new Set(rs.map(n => moved.get(n).dom));
  const own = [...doms].filter(d => d); const dom = own.length ? (doms.has('core') && [...rs].some(n => moved.get(n).dom === 'core') ? primaryOf(rs, doms) : [...doms][0]) : 'core';
  (migParts[dom] = migParts[dom] || []).push(rewrite2(e, dom)); migN++;
}
function primaryOf(rs, doms) { const cnt = {}; for (const n of rs) cnt[moved.get(n).dom] = (cnt[moved.get(n).dom] || 0) + 1; return Object.entries(cnt).sort((a, b) => b[1] - a[1])[0][0]; }
if (migN < 25) fail('迁移条目 ' + migN);

/* ---- 5. 输出 ---- */
fs.mkdirSync(DIR, { recursive: true });
const usedCross = {}; // dom -> set of referenced other-dom names
for (const dom of Object.keys(migParts)) for (const t of migParts[dom]) for (const m of t.matchAll(/\$\{(\w)\.(\w+)\}/g)) (usedCross[m[1]] = usedCross[m[1]] || new Set()).add(m[2]);
for (const [n, o] of moved) for (const m of rewrite2(o.value, o.dom).matchAll(/\$\{(\w)\.(\w+)\}/g)) { }
const bodies = {};
for (const [n, o] of moved) {
  const txt = '\n' + (o.pre.trimEnd().replace(/\n(?![\s\/])/g, '\n') || '') + '\nconst'.length ? '' : '';
  let chunk = o.pre.replace(/^\n+/, '') + o.kind + ' ' + o.type + ' ' + n + ' = ' + rewrite2(o.value, o.dom) + ';';
  (bodies[o.dom] = bodies[o.dom] || []).push(chunk);
}
for (const [dom, es] of Object.entries(migParts)) (bodies[dom] = bodies[dom] || []).push('/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）\nfinal Map<int, List<String>> mig = {' + es.join(',') + '\n};');
if (methodZone) (bodies['ledger'] = bodies['ledger'] || []).push('/// 治理G5：自 DbSchema 整体外提（仅引用本域表名常量·零重写）\n' + methodZone.replace(/^\s*static\s+/, ''));
const DOMS = Object.keys(bodies).sort();
for (const dom of DOMS) {
  const imports = Object.entries(PREFIX).filter(([d]) => d !== dom).map(([d, p]) => {
    const names = [...(usedCross[p] || [])].filter(n => moved.get(n) && moved.get(n).dom === d);
    return names.length ? null : null;
  });
  let head = "part of 'unused.dart';\n"; // placeholder removed below
  const cross = {};
  for (const t of bodies[dom]) for (const m of t.matchAll(/\$\{(\w)\.(\w+)\}|\.\.\.(\w)\.(\w+)\b/g)) { const p = m[1] || m[3]; const dom2 = Object.keys(PREFIX).find(d => PREFIX[d] === p); if (dom2) (cross[dom2] = cross[dom2] || new Set()).add(m[2] || m[4]); }
  let txt = '// 治理G5 域库：' + dom + ' · 由 schema.dart 外提（原名零改写）·跨域引用带前缀\n';
  for (const [d2, p] of Object.entries(PREFIX)) if (d2 !== dom && cross[d2]) txt += "import '" + d2 + ".dart' as " + p + ';\n';
  txt += '\n' + bodies[dom].join('\n\n') + '\n';
  fs.writeFileSync(path.join(DIR, dom + '.dart'), txt);
  console.log(dom + '.dart lines=' + txt.split('\n').length);
}
let agg = src.slice(0, clsStart);
agg += 'library;\n';
agg += DOMS.map(d => "import 'schema/" + d + ".dart' as " + PREFIX[d] + ';').join('\n') + '\n';
agg += src.slice(clsStart, bodyOpen) + '\n  const DbSchema._();\n';
for (const raw of keptDecls) agg += raw + '\n';
for (const [n, o] of moved) agg += '  static ' + o.kind + ' ' + o.type + ' ' + n + ' = ' + PREFIX[o.dom] + '.' + n + ';  // G5: ' + o.dom + '.dart\n';
agg += '  static final Map<int, List<String>> migrations = {\n';
for (const dom of DOMS) agg += '    ...' + PREFIX[dom] + '.mig,\n';
agg += '  };\n}\n';
fs.writeFileSync(SRC, agg);
console.log('schema.dart lines=' + agg.split('\n').length + ' moved=' + moved.size + ' domFiles=' + DOMS.join(','));
