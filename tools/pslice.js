/* pslice.js · 原型屏级切片器（§4-6 读侧工具）——按屏读码不再整读大文件。
 * 用法：node tools/pslice.js <file.html> --list
 *       node tools/pslice.js <file.html> <屏或弹层id> [--css|--js|--startline|--full]
 * 示例：node tools/pslice.js prototype/index-bookshelf.html p-bookshelf
 *       node tools/pslice.js prototype/index.html --css
 */
const fs = require('fs');
const path = require('path');

function extractBlock(html, tagName, openStart) {
  const re = new RegExp('<' + tagName + '\\b|</' + tagName + '>', 'gi');
  re.lastIndex = openStart;
  let depth = 0, m, end = -1, startLine = 0;
  while ((m = re.exec(html))) {
    depth += m[0][1] === '/' ? -1 : 1;
    if (depth === 0) { end = re.lastIndex; break; }
  }
  if (end < 0) return null;
  return { block: html.slice(openStart, end), start: openStart, end };
}
function harvest(html) {
  const out = [];
  const re = /<(section|div)\b[^>]*\bid="([^"]+)"/gi;
  let m;
  while ((m = re.exec(html))) {
    const tag = m[1].toLowerCase();
    if (tag === 'div' && !(m[2].startsWith('sheet') || m[2].startsWith('drawer'))) continue;
    const b = extractBlock(html, tag, m.index);
    if (!b) continue;
    out.push({ id: m[2], kind: tag === 'section' ? 'screen' : 'sheet', startLine: html.slice(0, b.start).split('\n').length, endLine: html.slice(0, b.end).split('\n').length, size: b.block.length, block: b.block });
    re.lastIndex = b.end;
  }
  return out;
}
const lineNo = (html, idx) => html.slice(0, idx).split('\n').length;

const args = process.argv.slice(2);
if (!args.length) { console.log('用法见文件头注释'); process.exit(2); }
const file = args[0];
const html = fs.readFileSync(file, 'utf8');
const base = path.basename(file).replace('.html', '');
const idxCard = 'prototype/screens/' + base + '.index.json';

if (args.includes('--list')) {
  if (fs.existsSync(idxCard)) {
    const card = JSON.parse(fs.readFileSync(idxCard, 'utf8'));
    for (const s of card.screens) console.log(`${s.role.padEnd(4)} ${s.id.padEnd(22)} ${s.kind.padEnd(6)} ${(s.size / 1000).toFixed(1)}k  ${s.title || ''}`);
    console.log(`-- 合计 ${(card.total / 1000).toFixed(0)}k，待删副本 ${card.cut} 个（详见 prototype/_modules.json）`);
  } else {
    for (const s of harvest(html)) console.log(`${s.id.padEnd(22)} ${s.kind.padEnd(6)} ${(s.size / 1000).toFixed(1)}k  行${s.startLine}-${s.endLine}`);
  }
  process.exit(0);
}
const flags = args.filter(a => a.startsWith('--'));
const target = args[0].endsWith('.html') ? args.slice(1).find(a => !a.startsWith('--')) : args.find(a => !a.startsWith('--') && a !== args[0]);
if (flags.includes('--css')) {
  const m = html.match(/<style>[\s\S]*?<\/style>/i);
  console.log(m ? m[0] : '(无 style 块)'); process.exit(0);
}
if (flags.includes('--js')) {
  const ms = [...html.matchAll(/<script>[\s\S]*?<\/script>/gi)];
  const big = ms.sort((a, b) => b[0].length - a[0].length)[0];
  if (!big) { console.log('(无 script 块)'); process.exit(0); }
  console.log('/* script 块 行' + lineNo(html, big.index) + ' 起，' + (big[0].length / 1000).toFixed(1) + 'k 字符 */');
  console.log(big[0]);
  process.exit(0);
}
const blocks = harvest(html);
const hit = blocks.find(b => b.id === target || b.id === 'p-' + target || b.id === 'sheet' + target);
if (!hit) {
  console.log('未找到屏/弹层：' + target + '（--list 查全表；未登记可先跑 psearch）');
  const near = blocks.filter(b => b.id.includes(target)).slice(0, 8).map(b => b.id);
  if (near.length) console.log('近似：' + near.join(' '));
  process.exit(1);
}
console.log(`/* ${hit.id} ${hit.kind} 行${hit.startLine}-${hit.endLine} ${(hit.size / 1000).toFixed(1)}k */`);
console.log(hit.block);
