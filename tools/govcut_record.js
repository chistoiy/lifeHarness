// record_deleted.js · 把已删越权副本的内部 id 登记进注册表 deleted 段（检查脚本白名单数据源）
// 依据：tmp/snap-cut/<file>.before（删前快照）× reg.violations[file]。幂等：重跑覆盖同键。
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
const reg = JSON.parse(fs.readFileSync('prototype/_modules.json', 'utf8'));
reg.deleted = reg.deleted || {};
const targets = process.argv.slice(2).length?process.argv.slice(2):['index.html','index-bookshelf.html','index-ledger.html','index_habitcheck.html','index-maternity_bady.html','index-day_aim__goods.html'];
for (const f of targets) {
  const snap = f === 'index.html' ? 'tmp/snap-cut/index.before-cut.html' : 'tmp/snap-cut/' + f + '.before';
  if (!fs.existsSync(snap)) { console.log('跳（无快照）', f); continue; }
  const old = fs.readFileSync(snap, 'utf8');
  const cur = fs.readFileSync('prototype/' + f, 'utf8');
  const ids = [...new Set((reg.violations || []).filter(v => v.file === f && !v.exempt).map(v => v.id))];
  const rec = [];
  for (const id of ids) {
    const m = old.match(new RegExp('<(?:section|div)[^>]*\\bid="' + id + '"'));
    if (!m) continue;
    const b = extractBlock(old, m.index);
    if (!b) continue;
    if (new RegExp('id="' + id + '"').test(cur)) continue; // 仍在本版（rep 保留），不登记
    const inner = [...new Set([...b.matchAll(/id="([^"]+)"/g)].map(x => x[1]).filter(x => x !== id && !new RegExp('id="' + x + '"').test(cur)))];
    rec.push({ id, inner });
  }
  reg.deleted[f] = rec;
  console.log('登记', f, rec.length, '块');
}
fs.writeFileSync('prototype/_modules.json', JSON.stringify(reg, null, 2));
