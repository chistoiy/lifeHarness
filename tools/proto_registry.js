/* proto_registry.js · 原型注册表 size/hash 统一重算与体检（排期池候选批·2026-10-06）
 *
 * 为什么要这枚工具：`prototype/_modules.json` 的 screens[].files 里 size/hash 两列自登记后
 * **没有任何工具读过**（2026-10-05 实测：255 条里仅 146 条能用 pslice 块 md5[:8] 复现，
 * 122 条 size 同而 hash 复现不了，34 条 size 已漂移，另有 380 处 file 条目对应的块已不存在）。
 * 读不到＝这两列是装饰，「内容变了但没重算」永远不会红。本件把它变成活闸。
 *
 * 口径（与 tools/pslice.js 逐字一致，勿改其一）：
 *   块＝`<(section|div)[^>]* id="X">` 起、按同名标签配平到闭合止的整段文本（含开闭标签）；
 *   div 仅当 id 以 sheet/drawer 开头才算屏级块；size＝块字符数；hash＝块文本 md5 前 8 位。
 *
 * 用法：node tools/proto_registry.js            # 体检报告（不改文件）
 *       node tools/proto_registry.js --write    # 按实测回写 size/hash，并删掉块已不存在的 file 条目
 *       node tools/proto_registry.js --check    # 有漂移即 exit 1（接进 doclint 当收口闸）
 */
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const DIR = 'prototype', REG = path.join(DIR, '_modules.json');
const argv = process.argv.slice(2);
const WRITE = argv.includes('--write'), CHECK = argv.includes('--check');

function extractBlock(html, tagName, openStart) {
  const re = new RegExp('<' + tagName + '\\b|</' + tagName + '>', 'gi');
  re.lastIndex = openStart;
  let depth = 0, m, end = -1;
  while ((m = re.exec(html))) {
    depth += m[0][1] === '/' ? -1 : 1;
    if (depth === 0) { end = re.lastIndex; break }
  }
  return end < 0 ? null : html.slice(openStart, end);
}
function harvest(file) {
  const html = fs.readFileSync(file, 'utf8'), out = new Map();
  const re = /<(section|div)\b[^>]*\bid="([^"]+)"/gi;
  let m;
  /* 注意：命中外层块后**不跳过**其内部——页内弹层（sheet 住在 section 里）很常见，
     跳过会把它们误判成「块已不存在」而剪掉正当登记（本件首版就栽在这，17 条屏被误删）。 */
  while ((m = re.exec(html))) {
    const tag = m[1].toLowerCase(), id = m[2];
    if (tag === 'div' && !(id.startsWith('sheet') || id.startsWith('drawer'))) continue;
    const b = extractBlock(html, tag, m.index);
    if (!b) { if (!out.has(id)) out.set(id, null); continue }
    if (!out.has(id)) out.set(id, { size: b.length, hash: crypto.createHash('md5').update(b).digest('hex').slice(0, 8) });
  }
  return out;
}

const reg = JSON.parse(fs.readFileSync(REG, 'utf8'));
const frozen = new Set(reg.frozen || []);
const files = fs.readdirSync(DIR).filter(f => f.endsWith('.html') && !frozen.has(f));
const cache = {};
const got = (f) => cache[f] || (cache[f] = harvest(path.join(DIR, f)));
const log = [];
let driftHash = 0, driftSize = 0, gone = 0, unreg = 0, okN = 0, unparsed = 0;

for (const s of reg.screens) {
  for (const f of Object.keys(s.files || {})) {
    const g = got(f).get(s.id);
    const e = s.files[f];
    if (g === null) { unparsed++; log.push('块配平失败 ' + s.id + ' @ ' + f + '（id 在文件里但标签不配平，不剪不写）'); continue }
    if (!g) { gone++; log.push('块缺失 ' + s.id + ' @ ' + f + '（登记 size=' + e.size + '）'); if (WRITE) delete s.files[f]; continue }
    if (g.size !== e.size) driftSize++;
    if (g.hash !== e.hash) driftHash++;
    if (g.size === e.size && g.hash === e.hash) okN++;
    if (WRITE) { e.size = g.size; e.hash = g.hash }
  }
}
/* 反向：现行文件里画着、注册表没登记的屏级 id（与 protogate 闸1 同源） */
const known = new Set(reg.screens.map(s => s.id));
const missing = [];
for (const f of files) {
  for (const [id, g] of got(f)) {
    if (!g || known.has(id)) continue;
    if (!missing.some(m => m.id === id)) missing.push({ id, file: f, g });
  }
}
unreg = missing.length;
for (const m of missing) log.push('未登记 ' + m.id + ' @ ' + m.file)
/* --add-missing：把未登记 id 入册（家＝首次出现的文件；kind 由标签定；size/hash 实测）。
   只在单文件出现时按 exclusive 登记；多文件出现不自动决定归属，交人判（屏单一归属规矩）。 */
if (WRITE && argv.includes('--add-missing')) {
  for (const m of missing) {
    const where = files.filter(f => got(f).has(m.id));
    if (where.length !== 1) { console.log('SKIP 多文件同款，需人工定家：' + m.id + ' → ' + where.join(' ')); continue }
    reg.screens.push({ id: m.id, kind: m.id.startsWith('sheet') || m.id.startsWith('drawer') ? 'sheet' : 'screen',
      title: '', home: where[0], reps: [], status: 'exclusive',
      files: { [where[0]]: { size: m.g.size, hash: m.g.hash } } });
    console.log('入册 ' + m.id + ' @ ' + where[0]);
  }
}
const total = Object.values(reg.screens).reduce((t, s) => t + Object.keys(s.files || {}).length, 0);
console.log('file 条目合计 ' + total + ' · 完全复现 ' + okN + ' · size 漂移 ' + driftSize + ' · hash 漂移 ' + driftHash + ' · 块已不存在 ' + gone + ' · 配平失败 ' + unparsed + ' · 未登记 id ' + unreg);
if (log.length) console.log(log.slice(0, 24).join('\n') + (log.length > 24 ? '\n…（共 ' + log.length + ' 条）' : ''));

if (WRITE) {
  const before = fs.readFileSync(REG, 'utf8');
  /* 格式自证（对**未改写**的解析结果做序列化）：证明「parse→stringify(indent 1)+换行」逐字节等于原文件，
     否则禁写——不然一次回写会把整份注册表重排，diff 炸成不可读，还可能吞字段。 */
  const pristine = JSON.stringify(JSON.parse(before), null, 2) + '\n';
  if (pristine !== before) {
    let d = -1; for (let i = 0; i < Math.min(before.length, pristine.length); i++) { if (before[i] !== pristine[i]) { d = i; break } }
    console.log('REFUSE 回写：JSON.parse→stringify(.,null,1) 与原文件不逐字节相等（原 ' + before.length + ' · 序列化 ' + pristine.length + ' · 首个差异第 ' + d + ' 字符），先对齐序列化口径');
    process.exit(2);
  }
  const after = JSON.stringify(reg, null, 2) + '\n';
  /* 剪掉块已不存在的 file 条目后，files 空＝该屏在现行原型里彻底没了 → 整条登记作废 */
  const dead = reg.screens.filter(s => !Object.keys(s.files || {}).length).map(s => s.id);
  if (dead.length) reg.screens = reg.screens.filter(s => Object.keys(s.files || {}).length);
  fs.writeFileSync(REG, JSON.stringify(reg, null, 2) + '\n', 'utf8');
  JSON.parse(fs.readFileSync(REG, 'utf8'));
  console.log('已回写 ' + REG + ' · screens ' + reg.screens.length + ' 条（整条作废 ' + dead.length + '：' + dead.slice(0, 12).join(' ') + (dead.length > 12 ? ' …' : '') + '）');
}
if (CHECK) {
  const bad = driftHash + driftSize + gone + unreg + unparsed;
  console.log(bad ? 'REGISTRY DRIFT ' + bad : 'REGISTRY CLEAN');
  process.exit(bad ? 1 : 0);
}
