/* T13 三档分拣表生成器（2026-10-06·只出事实不动代码）
 * 档① 注释级＝不违令（守护排除注释行）
 * 档② 表情级·原型同款＝原型即事实源，要清必须先逐屏改原型 → 产品裁定是否值得做专项批
 * 档③ 表情级·仅代码出现＝真违令，可随批清扫（含教学句同族）
 * 另立一档⓪ 符号级（✓ ✕ ✔  × › ★ 等非图形表情）＝不属「禁 emoji 图标」令内，登记但不清扫
 * 用法：node tools/emoji_triage.js [--md 输出路径] */
const fs = require('fs'), path = require('path');
const EMOJI = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]/gu;
/* 符号级白名单（几何/勾叉/星号类，非表情图形） */
const SYMBOL = new Set(['✓', '✔', '✕', '', '×', '', '☐', '★', '☆', '›', '‹', '→', '←', '↑', '↓', '•', '·', '▪', '▸', '', '', '', '…']);
const out = process.argv.indexOf('--md');
const MD = out > -1 ? process.argv[out + 1] : null;

function walk(d, ext, keep, acc) {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f), st = fs.statSync(p);
    if (st.isDirectory()) { if (!keep.some(k => f === k)) walk(p, ext, keep, acc) }
    else if (ext.test(f)) acc.push(p);
  }
  return acc;
}
/* 原型侧出现过的字形（含专版与冻结件，宽口径＝只要原型任何地方画过就算「同款」） */
const protoGlyphs = new Set();
for (const f of walk('prototype', /\.(html|js)$/, ['shots', 'attic'], [])) {
  for (const m of fs.readFileSync(f, 'utf8').matchAll(EMOJI)) protoGlyphs.add(m[0]);
}
const rows = [];
const files = walk('lib', /\.dart$/, ['build', '.dart_tool', 'archive'], []);
for (const f of files) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  lines.forEach((ln, i) => {
    const gs = [...ln.matchAll(EMOJI)].map(m => m[0]).filter(g => g !== '️');
    if (!gs.length) return;
    const trimmed = ln.trim();
    const isComment = trimmed.startsWith('//') || trimmed.startsWith('///') || trimmed.startsWith('/*') || trimmed.startsWith('*');
    for (const g of gs) {
      rows.push({
        file: f.split(path.sep).join('/'), line: i + 1, glyph: g,
        tier: isComment ? '①' : (SYMBOL.has(g) ? '⓪' : (protoGlyphs.has(g) ? '②' : '③')),
      });
    }
  });
}
const cnt = t => rows.filter(r => r.tier === t).length;
const byGlyph = {};
for (const r of rows.filter(r => r.tier === '②' || r.tier === '③')) {
  const k = r.tier + ' ' + r.glyph;
  byGlyph[k] = byGlyph[k] || { glyph: r.glyph, tier: r.tier, n: 0, files: new Set() };
  byGlyph[k].n++; byGlyph[k].files.add(r.file);
}
const list = Object.values(byGlyph).sort((a, b) => a.tier.localeCompare(b.tier) || b.n - a.n);
const head = ['T13 emoji 三档分拣（生成＝`node tools/emoji_triage.js --md <路径>`·只出事实不动代码）', '',
  'lib 实测：命中 ' + rows.length + ' 枚 / ' + new Set(rows.map(r => r.file)).size + ' 文件（扫 ' + files.length + ' 个 dart）；分档＝⓪符号级 ' + cnt('⓪') +
  ' ①注释级 ' + cnt('①') + ' ②表情级·原型同款 ' + cnt('②') + ' ③表情级·仅代码 ' + cnt('③'), '',
  '| 档 | 字形 | 枚数 | 涉及文件数 | 处置建议 |', '|---|---|---|---|---|'];
const body = list.map(x => '| ' + x.tier + ' | `' + x.glyph + '` | ' + x.n + ' | ' + x.files.size +
  ' | ' + (x.tier === '②' ? '原型即事实源：要清先逐屏改原型（产品裁定）' : '真违令：可随批清扫＋上守护') + ' |');
/* 档③ 逐条明细＝本批唯一可直接清扫的清单（代码自造、原型无同款） */
const t3 = rows.filter(r => r.tier === '③');
const sec3 = ['', '## 档③ 明细（代码里有、原型里没有＝可直接随批清扫）', '',
  '| 文件 | 行 | 字形 |', '|---|---|---|']
  .concat(t3.map(r => '| `' + r.file + '` | ' + r.line + ' | `' + r.glyph + '` |')).join('\n') + '\n';
const text = head.concat(body).join('\n') + '\n\n' + sec3 + '\n口径：⓪符号级＝勾叉/箭头/星号类，不属「禁 emoji 表情图标」令内；①注释级＝守护上闸前先剔（`tools/emoji_inv.js` 的 `#` 行同口径）；'
  + '②＝该字形在 `prototype/**` 任何位置出现过（宽口径，含演示数据文本），清扫＝UI 变更须先过原型门；③＝代码里有、原型里没有，属实现自造，直接可清。\n\n'
  + '守护上闸次序（工单既定）：先跑存量红＝②③分拣后违令清单清零，再上 strict；注释级与符号级由守护排除。\n';
if (MD) { fs.writeFileSync(MD, text, 'utf8'); console.log('已写 ' + MD) }
console.log(text.split('\n').slice(0, 8).join('\n'));
console.log('…（共 ' + list.length + ' 个字形分档）');
