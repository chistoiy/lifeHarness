/* proto_cards_check.js · 读侧索引卡一致性闸（治理 §4-6「doclint 校索引与 HTML 一致」2026-10-16 补做）
 *
 * 为什么要这枚工具：`prototype/screens/<file>.index.json` 自 2026-10-03 治理批建起就是
 * `tools/pslice.js --list` 的**唯一读数来源**（有卡读卡、无卡现扫），但从来没有任何闸校验过它——
 * 2026-10-16 盘点实测：15 份专版只有 8 份有卡，且已有卡普遍过期（bookshelf 卡记 766,859、
 * 盘上实测 706,661，差 6 万字符），即读侧工具一直在给错读数而无人知情。本件把「卡」变成活闸。
 *
 * 口径（与 tools/govcut_card.js **逐字一致**，勿改其一——改一处必两处同改，否则存量卡集体作废）：
 *   卡＝{file, total: 文件字符数, cut: role∈{cut,ghost} 的条数, screens:[{id,kind,title,role,size,hash}]}
 *   块＝`<(section|div)[^>]* id="X">` 起按同名标签配平到闭合止（**不跳嵌套**，页内弹层各自成条）；
 *   div 仅当 id 以 sheet/drawer 开头才算屏级；size＝块字符数（JS str.length）；hash＝块文本 md5 前 8 位（utf8）。
 *   落盘＝JSON.stringify(card, null, 1)，**无尾换行**。
 *
 * 用法：node tools/proto_cards_check.js            # 体检报告（不改文件）
 *       node tools/proto_cards_check.js --write    # 按实测重生成全部在册专版的卡
 *       node tools/proto_cards_check.js --check    # 有漂移即 exit 1（接进 doclint 当收口闸）
 */
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const DIR = 'prototype', CARD_DIR = path.join(DIR, 'screens'), REG = path.join(DIR, '_modules.json');
const argv = process.argv.slice(2);
const WRITE = argv.includes('--write'), CHECK = argv.includes('--check');

const reg = JSON.parse(fs.readFileSync(REG, 'utf8'));
const byid = Object.fromEntries(reg.screens.map(s => [s.id, s]));
const frozen = new Set(reg.frozen || []);
/* 在册专版＝注册表 screens[].files 里出现过的文件（frozen 豁免：v2.html / index-v2.html
   两份非本系列旧原型已于 2026-10-16 由产品手动删除并提交，条目留在 frozen 里作历史台账；
   三个闸都按「名单内即豁免」处理，故这些条目无害——frozen 是豁免名单而非在册名单）*/
const onfile = new Set();
for (const s of reg.screens) for (const f of Object.keys(s.files || {})) if (!frozen.has(f)) onfile.add(f);

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
function build(f) {                      /* —— 与 govcut_card.js 同款：角色判定依赖 _modules.json —— */
  const viol = new Set(reg.violations.filter(v => v.file === f && !v.exempt).map(v => v.id));
  const html = fs.readFileSync(path.join(DIR, f), 'utf8');
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
    if (viol.has(id) && s && s.home !== f) role = 'cut'; else if (s && s.home === f) role = 'home';
    screens.push({ id, kind, title: (s && s.title) || '', role, size: b.length, hash: crypto.createHash('md5').update(b).digest('hex').slice(0, 8) });
  }
  const cut = screens.filter(s => s.role === 'cut' || s.role === 'ghost').length;
  return { file: f, total: html.length, cut, screens };
}

const cardPath = f => path.join(CARD_DIR, f.replace('.html', '') + '.index.json');
const red = [];
let okN = 0;
for (const f of [...onfile].sort()) {
  const want = JSON.stringify(build(f), null, 1);
  if (WRITE) { fs.writeFileSync(cardPath(f), want); console.log('已重生成 ' + f); continue }
  if (!fs.existsSync(cardPath(f))) { red.push('缺索引卡 ' + f + '（跑 node tools/govcut_card.js ' + f + '）'); continue }
  const got = fs.readFileSync(cardPath(f), 'utf8');
  if (got === want) { okN++; continue }
  let why = '内容不一致';
  try {
    const g = JSON.parse(got), w = JSON.parse(want);
    if (g.total !== w.total) why = `total 陈旧 卡=${g.total} 实测=${w.total}（差 ${w.total - g.total}）`;
    else if ((g.screens || []).length !== w.screens.length) why = `屏数 卡=${(g.screens || []).length} 实测=${w.screens.length}`;
    else {
      const i = w.screens.findIndex((s, k) => { const t = g.screens[k]; return t.id !== s.id || t.size !== s.size || t.hash !== s.hash || t.role !== s.role });
      if (i >= 0) { const t = g.screens[i], s = w.screens[i]; why = `第${i + 1}屏 卡=${t.id}(${t.size}/${t.hash}/${t.role}) 实测=${s.id}(${s.size}/${s.hash}/${s.role})` }
    }
  } catch (e) { why = 'JSON 解析失败 ' + e.message }
  red.push('卡过期或被改 ' + f + '：' + why);
}
/* 孤儿卡：卡在册而文件不在（专版被删却没清卡） */
if (!WRITE && fs.existsSync(CARD_DIR)) for (const n of fs.readdirSync(CARD_DIR)) {
  const f = n.replace('.index.json', '.html');
  if (n.endsWith('.index.json') && !onfile.has(f)) red.push('孤儿卡 ' + n + '（专版已不在注册表在册名单，删卡或补登记）');
}
const total = onfile.size;
console.log(`索引卡体检：在册专版 ${total} 份 · 完全一致 ${WRITE ? '（已重生成）' : okN} · 异常 ${red.length}`);
if (red.length) { console.log(red.slice(0, 20).join('\n') + (red.length > 20 ? `\n…（共 ${red.length} 条）` : '')); process.exitCode = 1 }
if (CHECK && red.length) { console.log('CARDS DRIFT ' + red.length); process.exit(1) }
if (CHECK) console.log('CARDS CLEAN');
