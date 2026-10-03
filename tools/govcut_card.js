// gen_card.js · 重建 prototype/screens/<file>.index.json（屏单一归属索引卡，动刀后必重跑）
// 用法：node tmp/gen_card.js <文件名.html>
const fs = require('fs'), crypto = require('crypto');
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
const reg = JSON.parse(fs.readFileSync('prototype/_modules.json', 'utf8'));
const byid = Object.fromEntries(reg.screens.map(s => [s.id, s]));
const viol = new Set(reg.violations.filter(v => v.file === f && !v.exempt).map(v => v.id));
const html = fs.readFileSync('prototype/' + f, 'utf8');
const screens = [];
for (const m of html.matchAll(/<(?:section|div)[^>]*\bid="([^"]+)"/g)) {
  const id = m[1];
  const tag = m[0].startsWith('<section') ? 'section' : 'div';
  if (tag === 'div' && !/^sheet|^drawer/.test(id)) continue;
  const b = extractBlock(html, m.index);
  if (!b) continue;
  const s = byid[id];
  const kind = tag === 'section' ? 'screen' : 'sheet';
  let role = 'home';
  if (s) role = (s.home === f) ? 'home' : ((s.reps || []).includes(f) ? 'rep' : (s.status === 'collision' && s.homes && s.homes[f] ? 'home' : s.status === 'dropped' ? 'ghost' : 'cut'));
  else role = 'unreg';
  if (viol.has(id)) role = 'cut';
  screens.push({ id, kind, title: (s && s.title) || '', role, size: b.length, hash: crypto.createHash('md5').update(b).digest('hex').slice(0, 8) });
}
const cut = screens.filter(s => s.role === 'cut' || s.role === 'ghost').length;
const card = { file: f, total: html.length, cut, screens };
fs.writeFileSync('prototype/screens/' + f.replace('.html', '') + '.index.json', JSON.stringify(card, null, 1));
console.log(f, '屏数', screens.length, '待删', cut, '未登记', screens.filter(s => s.role === 'unreg').map(s => s.id).join(',') || '无');
