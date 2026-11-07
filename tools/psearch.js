/* psearch.js · 原型全文检索（§4-6 读侧工具）：文案/关键词 → 文件＋所属屏/弹层＋行号。
 * 用法：node tools/psearch.js <正则或关键词> [--file 限定] [--max 每条上限=8]
 * 示例：node tools/psearch.js 生成决算 --max 3
 */
const fs = require('fs');
const path = require('path');
const args = process.argv.slice(2);
if (!args.length) { console.log('用法见文件头注释'); process.exit(2); }
const q = args[0].toLowerCase();
const fileOnly = (() => { const i = args.indexOf('--file'); return i >= 0 ? args[i + 1] : null; })();
const maxPer = Number((() => { const i = args.indexOf('--max'); return i >= 0 ? args[i + 1] : 8; })());

const DIR = 'prototype';
let files = fileOnly ? [fileOnly] : fs.readdirSync(DIR).filter(f => f.endsWith('.html') && !['v2.html', 'index-v2.html'].includes(f));
const FROZEN = ['index-media.html', 'index-sync.html'];
let rx; try { rx = new RegExp(q, 'i'); } catch (e) { rx = null; }
let total = 0;
for (const f of files) {
  const p = path.join(DIR, f);
  if (!fs.existsSync(p)) { console.log('跳过（文件不存在）: ' + f); continue; }
  const html = fs.readFileSync(p, 'utf8');
  // id 锚点表（用于归属判定）
  const anchors = [];
  const re = /<(section|div)\b[^>]*\bid="([^"]+)"/gi; let m;
  while ((m = re.exec(html))) {
    if (m[1] === 'div' && !(m[2].startsWith('sheet') || m[2].startsWith('drawer'))) continue;
    anchors.push([m.index, m[2]]);
  }
  const lines = html.split('\n');
  let linePos = [], acc = 0;
  for (const l of lines) { linePos.push(acc); acc += l.length + 1; }
  const owner = idx => { let best = null; for (const [pos, id] of anchors) { if (pos <= idx) best = id; else break; } return best || '(壳层/JS)'; };
  const hits = [];
  for (let i = 0; i < lines.length; i++) {
    const ok = rx ? rx.test(lines[i]) : lines[i].toLowerCase().includes(q);
    if (ok) hits.push({ n: i + 1, in: owner(linePos[i]), t: lines[i].trim().slice(0, 110) });
  }
  if (!hits.length) continue;
  total += Math.min(hits.length, maxPer);
  console.log(`\n== ${f}${FROZEN.includes(f) ? ' [冻结]' : ''} 命中 ${hits.length} 行（示 ${Math.min(hits.length, maxPer)}）`);
  for (const h of hits.slice(0, maxPer)) console.log(`  ${String(h.n).padStart(6)} 行  <${h.in}>  ${h.t}`);
}
console.log('\n合计示出 ' + total + ' 条。屏归属以 prototype/_modules.json 为准；读单屏用 tools/pslice.js。');
