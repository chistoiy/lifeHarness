/* pstore_retire.js · 产品拍板「插件中心 删屏」：整簇从壳原型摘除
 * 用法：node tools/pstore_retire.js
 * 摘四件：p-pstore 屏 · sheetPlugin 弹层 · sheetPSDetail 详情弹层 · 插件中心 JS 簇（PS 数据与 renderPstore 等函数）
 * 外加 ICONS 里那枚图标路径。每块按同名标签配平取段（与 tools/pslice.js 同口径），命中断言＝1 才落盘。
 * 影音游专版 index-media.html 里的副本属冻结文件，本刀不碰（注册表随后按实测把家与文件条目改到位）。
 */
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const HTML = path.join(ROOT, 'prototype', 'index.html');
const SNAP = path.join(ROOT, 'tmp', 'index-html.before-pstore-20261007.html');
const orig = fs.readFileSync(HTML, 'utf8');
fs.writeFileSync(SNAP, orig, 'utf8');
let out = orig;

function blockAt(tag, id) {
  const re = new RegExp('<' + tag + '\\b[^>]*\\bid="' + id + '"');
  const m = re.exec(out);
  if (!m) throw new Error('找不到 <' + tag + ' id="' + id + '">——中止');
  const scan = new RegExp('<' + tag + '\\b|</' + tag + '>', 'gi');
  scan.lastIndex = m.index;
  let d = 0, x, end = -1;
  while ((x = scan.exec(out))) { d += x[0][1] === '/' ? -1 : 1; if (d === 0) { end = scan.lastIndex; break } }
  if (end < 0) throw new Error('块未配平：' + id + '——中止');
  return { i: m.index, j: end };
}
function cutBlock(tag, id, eatPrecedingComment) {
  const b = blockAt(tag, id);
  let i = b.i;
  if (eatPrecedingComment) {
    const before = out.lastIndexOf('<!--', i);
    if (before >= 0 && i - before < 400 && out.slice(before, i).trim().endsWith('-->')) i = before;
  }
  // 连带吃掉块后的换行与块前的缩进
  while (i > 0 && out[i - 1] === ' ') i--;
  if (out[i - 1] === '\n') i--;
  let j = b.j;
  if (out[j] === '\n') j++;
  const removed = out.slice(i, j);
  if (removed.length < 120) throw new Error('摘除体积异常：' + id);
  out = out.slice(0, i) + '      <!-- 插件中心屏已随 2026-10-07 产品拍板整簇下架（入口·屏·弹层·JS）；影音游专版里的副本另行裁定 -->\n'
    + out.slice(j);
  console.log('CUT ' + id + ' (' + removed.length + ')');
}
function cutSpan(name, from, to) {
  const n = out.split(from).length - 1;
  if (n !== 1) throw new Error('锚点 ' + name + ' 命中 ' + n + '——中止');
  const i = out.indexOf(from);
  const j = out.indexOf(to, i);
  if (j <= i) throw new Error('锚点顺序不对：' + name);
  console.log('CUT ' + name + ' (' + (j - i) + ')');
  out = out.slice(0, i) + out.slice(j);
}

cutBlock('section', 'p-pstore', true);
cutBlock('div', 'sheetPlugin', true);
cutBlock('div', 'sheetPSDetail', true);
cutSpan('插件中心 JS 簇',
  '/* ================= 插件中心（大模块插件化） ================= */',
  '/* ================= 日记 INS 风格');
function cutTo(name, from, terminator) {
  const n = out.split(from).length - 1;
  if (n !== 1) throw new Error('锚点 ' + name + ' 命中 ' + n + '——中止');
  const i = out.indexOf(from);
  const j = out.indexOf(terminator, i);
  if (j <= i) throw new Error('收束锚点找不到：' + name);
  const removed = out.slice(i, j + terminator.length);
  console.log('CUT ' + name + ' (' + removed.length + ')');
  out = out.slice(0, i) + out.slice(j + terminator.length);
}

cutTo('TITLES 标题', "'p-pstore':['插件中心'", "],");
// ICONS 整张表是一行：收束只认「值末尾的单引号＋逗号」（SVG 里只有双引号，不会误命中）。
cutTo('ICONS 图标', "'p-pstore':'", "',");

const delta = out.length - orig.length;
if (delta > -8000 || delta < -60000) throw new Error('总体积变化异常：' + delta + '——中止（快照在 tmp/）');
fs.writeFileSync(HTML, out, 'utf8');
console.log('DONE bytes ' + orig.length + ' → ' + out.length + ' (' + delta + ')');
