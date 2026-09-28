// 治理G7d④ 只读调研 v2：花括号深度切块 + 群间调用边
// 用法：node tools/g7d4_survey.js
const fs = require('fs');
const norm = (s) => s.replace(/\r\n/g, '\n');
const SRC = 'lib/features/read/data/read_repository.dart';
const lines = norm(fs.readFileSync(SRC, 'utf8')).split('\n');

// 去掉字符串与 // 注释后计深度（本文件无三引号字符串，已核实）
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
  const c = code(s);
  let d = 0;
  for (const ch of c)
    if (ch === '{' || ch === '(' || ch === '[') d++;
    else if (ch === '}' || ch === ')' || ch === ']') d--;
  return d;
};

const classStart = lines.findIndex((l) => l.startsWith('class ReadRepository {'));
let depth = 0;
let cur = null;
const blocks = [];
for (let i = classStart; i < lines.length; i++) {
  const d0 = depth;
  depth += delta(lines[i]);
  if (i === classStart) continue;
  const isDecl =
    d0 === 1 &&
    /^  \S/.test(lines[i]) &&
    !/^  [});\]]/.test(lines[i]) &&
    !lines[i].trim().startsWith('//');
  if (isDecl) {
    let s = i;
    while (s > 0 && /^\s*(@\w+|\/\/|\/\*)/.test(lines[s - 1]) && lines[s - 1].trim() !== '') s--;
    cur = { decl: i, start: s, end: i, sig: lines[i].trim() };
    blocks.push(cur);
  } else if (cur) {
    cur.end = i;
  }
  if (cur && depth === 1) cur = null;
  if (depth === 0) break; // 类收尾
}
let unbal = 0;
for (const b of blocks) {
  let d = 0;
  for (let i = b.start; i <= b.end; i++) d += delta(lines[i]);
  if (d !== 0) { unbal++; console.log('UNBALANCED L' + (b.start + 1) + '..L' + (b.end + 1) + ' ' + b.sig.slice(0, 70)); }
}
console.log('成员块数', blocks.length, '未配平', unbal);

const nameOf = (sig) => {
  const g = sig.match(/\bget (_?\w+)/) || sig.match(/\b(_?\w+)\s*[(=]/);
  return g ? g[1] : null;
};
blocks.forEach((b) => (b.name = nameOf(b.sig)));
const noName = blocks.filter((b) => !b.name);
if (noName.length) console.log('无名成员', noName.map((b) => b.sig));

const SECS = [[34, 'book'], [220, 'session'], [597, 'quote'], [770, 'quote'], [866, 'quote'],
  [932, 'toc'], [1117, 'toc'], [1153, 'dict'], [1316, 'list'], [1474, 'stat'], [1572, 'fee'],
  [1620, 'imp'], [1813, 'expo'], [1887, 'kv'], [1912, 'douban']];
const groupOf = (ln0) => {
  let g = 'core';
  for (const [n, k] of SECS) if (ln0 + 1 >= n) g = k;
  return g;
};
blocks.forEach((b) => (b.group = groupOf(b.decl)));

const owner = new Map();
for (const b of blocks) if (!owner.has(b.name)) owner.set(b.name, b);

const edges = [];
for (const b of blocks) {
  const body = lines.slice(b.start, b.end + 1).join('\n');
  const calls = new Set();
  for (const c of body.matchAll(/([A-Za-z_]\w*)\s*\(/g))
    if (owner.has(c[1]) && c[1] !== b.name) calls.add(c[1]);
  for (const n of calls) {
    const t = owner.get(n);
    if (t.group !== b.group) edges.push({ from: b, to: t });
  }
}
const agg = {};
for (const e of edges) {
  const k = `${e.to.group}/${e.to.name}`;
  agg[k] = agg[k] || new Set();
  agg[k].add(`${e.from.group}/${e.from.name}`);
}
console.log('\n--- 跨群被调用者（须留类内，或与全部调用者同群）---');
for (const [k, v] of Object.entries(agg).sort()) console.log(`${k.padEnd(24)} ← ${[...v].join(', ')}`);

console.log('\n--- 群规模 ---');
const g = {};
for (const b of blocks) {
  g[b.group] = g[b.group] || { n: 0, ln: 0 };
  g[b.group].n++;
  g[b.group].ln += b.end - b.start + 1;
}
for (const [k, v] of Object.entries(g)) console.log(`${k.padEnd(8)} 成员${String(v.n).padStart(3)} 行${String(v.ln).padStart(5)}`);

console.log('\n--- static / 字段成员 ---');
for (const b of blocks)
  if (/^\s*(static|final|late)\b/.test(lines[b.decl])) console.log(`${b.group}/${b.name} L${b.decl + 1}: ${b.sig.slice(0, 72)}`);

if (process.argv.includes('--dump'))
  console.log('\n--- 全部块 ---\n' + blocks.map((b) => `${b.group}/${b.name} L${b.start + 1}..L${b.end + 1}`).join('\n'));
