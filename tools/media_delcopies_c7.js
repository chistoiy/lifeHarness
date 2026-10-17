/* media_delcopies_c7.js · 影音游批2 第一刀 C 段：删 index-media.html 的 58 枚越权副本＋2 枚已下架小工具屏
 * 用法：node tools/media_delcopies_c7.js [--dry]
 * 护栏：写前快照 tmp/；每 id 恰 1 命中否则中止；体积校验（新体积＝旧体积−块合计±换行余量）；
 *      #recMedia 工作台整段先抽出留 tmp/ 作共享面回灌原料（S-01）。
 */
const fs = require('fs');
const dry = process.argv.includes('--dry');
const FILE = 'index-media.html', P = 'prototype/' + FILE;
const reg = JSON.parse(fs.readFileSync('prototype/_modules.json', 'utf8'));
let html = fs.readFileSync(P, 'utf8');
const before = html.length;

const ids = reg.violations.filter(v => v.file === FILE).map(v => v.id);
const extra = ['p-tools', 'p-toolDetail']; // 闸3 勿复活件一并摘净
const targets = [...new Set(ids.concat(extra))];
if (targets.length < 55) { console.error('FAIL 目标 ' + targets.length + ' 枚（预期 ≥55）'); process.exit(1); }

function blockOf(id) {
  const tag = id.startsWith('sheet') || id.startsWith('drawer') ? 'div' : 'section';
  const re = new RegExp('<' + tag + '\\b[^>]*\\bid="' + id + '"', 'g');
  const hits = [...html.matchAll(re)];
  if (hits.length !== 1) { console.error('FAIL id=' + id + ' 命中 ' + hits.length + ' 次（须恰 1）'); process.exit(1); }
  const openStart = hits[0].index;
  const inner = new RegExp('<' + tag + '\\b|</' + tag + '>', 'gi');
  inner.lastIndex = openStart;
  let depth = 0, m, end = -1;
  while ((m = inner.exec(html))) {
    depth += m[0][1] === '/' ? -1 : 1;
    if (depth === 0) { end = inner.lastIndex; break; }
  }
  if (end < 0) { console.error('FAIL id=' + id + ' 标签不配平'); process.exit(1); }
  return [openStart, end];
}

/* 先把 #recMedia 工作台段抽出留档（它在 p-records 内，删父块前抢救） */
{
  const re = /<div\b[^>]*\bid="recMedia"/g;
  const h = [...html.matchAll(re)];
  if (h.length !== 1) { console.error('FAIL recMedia 命中 ' + h.length); process.exit(1); }
  const st = h[0].index;
  const inner = /<div\b|<\/div>/gi; inner.lastIndex = st;
  let d = 0, m, en = -1;
  while ((m = inner.exec(html))) { d += m[0][1] === '/' ? -1 : 1; if (d === 0) { en = inner.lastIndex; break; } }
  fs.writeFileSync('tmp/recmedia_workbench_for_backport_c7.html', html.slice(st, en), 'utf8');
  console.log('recMedia saved:', en - st, 'chars');
}

/* 逆序删除（前面的块先删会移动后面的偏移） */
const spans = targets.map(id => [id, ...blockOf(id)]).sort((a, b) => b[1] - a[1]);
let removed = 0;
for (const [id, st, en] of spans) {
  // 连带吃掉块所在整行（含前导空白与行尾换行）
  let s2 = st; while (s2 > 0 && (html[s2 - 1] === ' ' || html[s2 - 1] === '\t')) s2--;
  let e2 = en; if (html[e2] === '\n') e2++;
  while (s2 > 0 && html[s2 - 1] === '\n') { // 若整行只有空白，也吃掉行首换行
    const ls = html.lastIndexOf('\n', s2 - 2);
    if (html.slice(ls + 1, s2).trim() === '') { s2 = ls + 1; } else break;
  }
  removed += (e2 - s2);
  html = html.slice(0, s2) + html.slice(e2);
}
const delta = before - html.length;
if (Math.abs(delta - removed) > targets.length * 2 + 8) { console.error('FAIL 体积差 ' + delta + ' ≠ 块合计 ' + removed); process.exit(1); }
console.log(JSON.stringify({ targets: targets.length, removedChars: delta, size: before + '→' + html.length }));
if (dry) { console.log('DRY 未写盘'); process.exit(0); }
fs.writeFileSync('tmp/index-media_before_delcopies_c7.html', fs.readFileSync(P, 'utf8'), 'utf8');
fs.writeFileSync(P, html, 'utf8');
console.log('WROTE ' + P);
