/* media_pstore_cut.js · 影音游专版里的插件中心副本一并摘净（产品拍板「删屏」，该模块不承接插件演示）
 * 用法：node tools/media_pstore_cut.js
 * 与壳同口径：p-pstore 屏＋sheetPlugin/sheetPSDetail 两弹层＋插件中心 JS 簇＋TITLES/ICONS 条目＋renderPstore 调用。
 * 命中断言＝1 才落盘；改前快照落 tmp/；体积守卫＝净减 8000~60000 字节。
 */
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const HTML = path.join(ROOT, 'prototype', 'index-media.html');
const SNAP = path.join(ROOT, 'tmp', 'index-media.before-pstore-20261007.html');
const orig = fs.readFileSync(HTML, 'utf8');
fs.writeFileSync(SNAP, orig, 'utf8');
let out = orig, cuts = 0;

function blockAt(tag, id) {
  const re = new RegExp('<' + tag + '\\b[^>]*\\bid="' + id + '"');
  const m = re.exec(out);
  if (!m) return null;
  const scan = new RegExp('<' + tag + '\\b|</' + tag + '>', 'gi');
  scan.lastIndex = m.index;
  let d = 0, x, end = -1;
  while ((x = scan.exec(out))) { d += x[0][1] === '/' ? -1 : 1; if (d === 0) { end = scan.lastIndex; break } }
  if (end < 0) throw new Error('块未配平：' + id + '——中止');
  return { i: m.index, j: end };
}
function cutBlock(tag, id) {
  const b = blockAt(tag, id);
  if (!b) { console.log('SKIP(不存在) ' + id); return }
  let i = b.i;
  const before = out.lastIndexOf('<!--', i);
  if (before >= 0 && i - before < 400 && out.slice(before, i).trim().endsWith('-->')) i = before;
  while (i > 0 && (out[i - 1] === ' ' || out[i - 1] === '\t')) i--;
  if (out[i - 1] === '\n') i--;
  let j = b.j; if (out[j] === '\n') j++;
  out = out.slice(0, i) + out.slice(j);
  cuts++; console.log('CUT ' + id + ' (' + (j - i) + ')');
}
function cutSpan(name, from, to) {
  const n = out.split(from).length - 1;
  if (n === 0) { console.log('SKIP(不存在) ' + name); return }
  if (n !== 1) throw new Error('锚点 ' + name + ' 命中 ' + n + '——中止');
  const i = out.indexOf(from), j = out.indexOf(to, i + from.length);
  if (j <= i) throw new Error('收束锚点找不到：' + name);
  out = out.slice(0, i) + out.slice(j);
  cuts++; console.log('CUT ' + name + ' (' + (j - i) + ')');
}
function cutKey2(from, endTok, label) {
  const n = out.split(from).length - 1;
  if (n === 0) { console.log('SKIP(不存在) ' + label); return }
  if (n !== 1) throw new Error('键锚点 ' + label + ' 命中 ' + n + '——中止');
  const i = out.indexOf(from);
  const j = out.indexOf(endTok, i);
  if (j < 0) throw new Error('键收束找不到：' + label);
  const k = j + endTok.length;
  console.log('CUT KEY ' + label + ' (' + (k - i) + ')');
  out = out.slice(0, i) + out.slice(k);
  cuts++;
}

cutBlock('section', 'p-pstore');
cutBlock('div', 'sheetPlugin');
cutBlock('div', 'sheetPSDetail');
cutSpan('插件中心 JS 簇', '/* ================= 插件中心（大模块插件化） ================= */', '/* ================= ');
cutKey2("'p-pstore':['", "],", 'TITLES 标题');
cutKey2("'p-pstore':'", "',", 'ICONS 图标');
const calls = out.split('renderPstore();').length - 1;
out = out.split('renderPstore();').join('');
if (calls) { console.log('CUT renderPstore() 调用 x' + calls); cuts += calls; }

const delta = out.length - orig.length;
if (delta > -8000 || delta < -80000) throw new Error('总体积变化异常：' + delta + '——中止（快照在 tmp/）');
fs.writeFileSync(HTML, out, 'utf8');
console.log('DONE bytes ' + orig.length + ' → ' + out.length + ' (' + delta + ')  cuts=' + cuts);
