// cut_file.js · 逐专版删越权副本（治理批 §4-5 通用管线第一步）
// 用法：node tmp/cut_file.js <文件名>            （删 reg.violations 中该文件全部未豁免 id）
//       node tmp/cut_file.js <文件名> --dry      （只报告）
// 护栏：先快照 tmp/snap-cut/<文件名>.before；每块命中断言（块内含 id）；体积校验（净减≈块和）；过渡态弹层最富副本先导出 tmp/merge_inbox/。
const fs = require('fs');
function extractBlock(html, openStart) {
  const m0 = html.slice(openStart, openStart + 60).match(/^<(section|div)\b/);
  if (!m0) return null;
  const tag = m0[1];
  const re = new RegExp('<' + tag + '\\b|</' + tag + '>', 'gi');
  re.lastIndex = openStart;
  let depth = 0, m, end = -1;
  while ((m = re.exec(html))) { depth += m[0][1] === '/' ? -1 : 1; if (depth === 0) { end = re.lastIndex; break; } }
  return end < 0 ? null : html.slice(openStart, end);
}
const f = process.argv[2];
const dry = process.argv.includes('--dry');
if (!f) { console.log('用法: node tmp/cut_file.js <文件名> [--dry]'); process.exit(2); }
const reg = JSON.parse(fs.readFileSync('prototype/_modules.json', 'utf8'));
const ids = reg.violations.filter(v => v.file === f && !v.exempt).map(v => v.id);
if (!ids.length) { console.log('无未豁免越权副本:', f); process.exit(0); }

// 过渡态弹层：导出各文件最富副本（跨现行文件比较，找最大）
fs.mkdirSync('tmp/merge_inbox', { recursive: true });
const TRANSIENT = ['sheetAddEvent', 'sheetEventDetail', 'sheetGridMark', 'sheetPlugin', 'sheetAddHabit'];
const ACTIVES = ['index-bookshelf.html', 'index-ledger.html', 'index_habitcheck.html', 'index-maternity_bady.html', 'index-day_aim__goods.html'];
for (const id of TRANSIENT) {
  let best = null, bestF = '';
  for (const af of ACTIVES) {
    const h = fs.readFileSync('prototype/' + af, 'utf8');
    const m = h.match(new RegExp('<div[^>]*\\bid="' + id + '"'));
    if (!m) continue;
    const b = extractBlock(h, m.index);
    if (b && (!best || b.length > best.length)) { best = b; bestF = af; }
  }
  if (best) {
    const outPath = 'tmp/merge_inbox/' + id + '.html';
    const cur = fs.existsSync(outPath) ? fs.statSync(outPath).size : 0;
    if (best.length > cur) { fs.writeFileSync(outPath, best); console.log('EXPORT', id, bestF, best.length); }
  }
}

let h = fs.readFileSync('prototype/' + f, 'utf8');
if (!dry) fs.writeFileSync('tmp/snap-cut/' + f + '.before', h);
const before = h.length;
let total = 0, done = [], miss = [];
// 长 id 先删防止嵌套误配？块提取按深度安全；顺序无所谓
for (const id of ids) {
  const m = h.match(new RegExp('<(?:section|div)[^>]*\\bid="' + id + '"'));
  if (!m) { miss.push(id); continue; }
  const b = extractBlock(h, m.index);
  if (!b || !b.includes('id="' + id + '"')) { console.error('BLOCK FAIL ' + id); process.exit(1); }
  h = h.slice(0, m.index) + h.slice(m.index + b.length);
  total += b.length;
  done.push(id + ':' + b.length);
}
const delta = before - h.length;
if (Math.abs(delta - total) > 600) { console.error('SIZE 异常', { delta, total }); process.exit(1); }
console.log(f, '删', done.length, '块 / 漏', miss.length, miss.join(','));
console.log(done.join(' '));
if (dry) { console.log('DRY 未写盘'); process.exit(0); }
fs.writeFileSync('prototype/' + f, h);
console.log('OK', before, '->', h.length);
