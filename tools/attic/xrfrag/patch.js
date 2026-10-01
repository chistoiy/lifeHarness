// V1.54 X-Ray 批2 原型装配 v2（上拉面板改造版 · 一次性脚本 · 完成后入 tools/attic）
// 护栏：锚点唯一命中断言 / UTF-8 读写 / CRLF 锚点跟随 / 体积下限校验
const fs = require('fs');
const path = require('path');
const FILE = 'prototype/index-bookshelf.html';
const FR = p => fs.readFileSync(path.join('tools/attic/xrfrag', p), 'utf8');

let src = fs.readFileSync(FILE, 'utf8');
const before = src.length;
if (!/\r\n/.test(src)) throw new Error('期望 CRLF 文件');
const toCRLF = s => s.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n');
const count = s => src.split(s).length - 1;

function insertAfterLine(anchor, frag, label) {
  if (count(anchor) !== 1) throw new Error(`anchor x${count(anchor)} (${label})`);
  const i = src.indexOf(anchor);
  const eol = src.indexOf('\r\n', i + anchor.length);
  src = src.slice(0, eol + 2) + toCRLF(frag) + src.slice(eol + 2);
  console.log('insert-after OK: ' + label);
}
function insertBeforeLine(anchor, frag, label) {
  if (count(anchor) !== 1) throw new Error(`anchor x${count(anchor)} (${label})`);
  const i = src.indexOf(anchor);
  const bol = src.lastIndexOf('\n', i) + 1;
  src = src.slice(0, bol) + toCRLF(frag) + src.slice(bol);
  console.log('insert-before OK: ' + label);
}
function replaceLine(anchor, newline, label) {
  if (count(anchor) !== 1) throw new Error(`anchor x${count(anchor)} (${label})`);
  src = src.replace(anchor, newline);
  console.log('replace OK: ' + label);
}

insertAfterLine(
  '#shBody .br-flash-loc{box-shadow:0 0 0 3px rgba(99,102,241,.6);border-radius:14px}',
  FR('css.frag'), 'css');
insertBeforeLine('  </main>', FR('page.frag'), 'page comment');
insertBeforeLine(
  '  <!-- V1.53.4⑥ 系统「打开方式」接收 EPUB · 未导入=导入确认 / 已导入=提醒+定位（?br57=open|dup） -->',
  FR('sheets.frag'), 'sheets');
insertAfterLine(
  `<div class="flex items-center justify-between py-1 cursor-pointer" onclick="closeSheet('sheetBrMore');brOpenDetail()"><span>书籍详情与资料页</span><span class="text-slate-300">›</span></div>`,
  FR('more.frag'), 'reader-more row');
// —— 抽屉 → 上拉全屏面板（目录｜X-Ray 双段） ——
replaceLine('<div id="brDrPanel" class="br-dr out">',
  '<div id="brDrPanel" class="xr-sheet out">', 'panel class');
replaceLine('<div id="brDrWide" class="relative w-[78%] max-w-[300px] h-full bg-white dark:bg-slate-900 flex flex-col rounded-r-2xl shadow-[12px_0_32px_rgba(15,23,42,.18)]">',
  '<div id="brDrWide" class="relative w-full h-[94%] bg-white dark:bg-slate-900 flex flex-col rounded-t-3xl shadow-[0_-12px_40px_rgba(15,23,42,.25)]">', 'wide class');
replaceLine('<div class="px-3.5 pt-4 pb-2 shrink-0 flex items-center gap-1.5">',
  '<div class="hidden px-3.5 pt-4 pb-2 shrink-0 items-center gap-1.5">', 'old header hidden');
replaceLine('<div id="brDrSearchBox" class="hidden px-3.5 pb-2 shrink-0">',
  '<div id="brDrSearchBox" style="display:none" class="hidden px-3.5 pb-2 shrink-0">', 'old search box pinned hidden');
insertBeforeLine('<div class="hidden px-3.5 pt-4 pb-2 shrink-0 items-center gap-1.5">',
  FR('hdr.frag'), 'new header row');
insertBeforeLine('<button id="brDrPill"', FR('pane.frag'), 'xr pane');
// —— JS 主体 ——
insertBeforeLine('/* R14-4 重放：bsInit 首帧渲染早于批3.5 shWall 覆盖', FR('js.frag'), 'js block');

if (src.length <= before) throw new Error(`size not grown: ${before} -> ${src.length}`);
fs.writeFileSync(FILE, src, 'utf8');
console.log(`written ${FILE}: ${before} -> ${src.length}`);
