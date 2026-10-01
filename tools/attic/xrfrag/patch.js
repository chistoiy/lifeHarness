// V1.54 X-Ray 批2 原型装配（一次性脚本 · 完成后入 tools/attic）
// 护栏：锚点唯一命中断言 / 按 UTF-8 读写 / 锚点跟随 CRLF / 体积校验
const fs = require('fs');
const path = require('path');
const FILE = 'prototype/index-bookshelf.html';
const FR = p => fs.readFileSync(path.join('tools/attic/xrfrag', p), 'utf8');

let src = fs.readFileSync(FILE, 'utf8');
const before = src.length;
if (!/\r\n/.test(src)) throw new Error('期望 CRLF 文件，行尾断言策略需调整');

const toCRLF = s => s.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n');

function insertAfterLine(anchor, frag, label) {
  const n = src.split(anchor).length - 1;
  if (n !== 1) throw new Error(`anchor count=${n} (${label})`);
  const i = src.indexOf(anchor);
  const eol = src.indexOf('\r\n', i + anchor.length);
  if (eol < 0) throw new Error(`no EOL after anchor (${label})`);
  src = src.slice(0, eol + 2) + toCRLF(frag) + src.slice(eol + 2);
  console.log(`insert-after OK: ${label}`);
}
function insertBeforeLine(anchor, frag, label) {
  const n = src.split(anchor).length - 1;
  if (n !== 1) throw new Error(`anchor count=${n} (${label})`);
  const i = src.indexOf(anchor);
  const bol = src.lastIndexOf('\n', i) + 1;
  src = src.slice(0, bol) + toCRLF(frag) + src.slice(bol);
  console.log(`insert-before OK: ${label}`);
}

const css = FR('css.frag');
const page = FR('page.frag');
const sheets = FR('sheets.frag');
const more = FR('more.frag');
const js = FR('js.frag');

insertAfterLine(
  '#shBody .br-flash-loc{box-shadow:0 0 0 3px rgba(99,102,241,.6);border-radius:14px}',
  css, 'css');
insertBeforeLine('  </main>', page, 'page p-xray');
insertBeforeLine(
  '  <!-- V1.53.4⑥ 系统「打开方式」接收 EPUB · 未导入=导入确认 / 已导入=提醒+定位（?br57=open|dup） -->',
  sheets, 'sheets');
insertAfterLine(
  `<div class="flex items-center justify-between py-1 cursor-pointer" onclick="closeSheet('sheetBrMore');brOpenDetail()"><span>书籍详情与资料页</span><span class="text-slate-300">›</span></div>`,
  more, 'reader-more row');
insertBeforeLine('/* R14-4 重放：bsInit 首帧渲染早于批3.5 shWall 覆盖', js, 'js block');

const expect = before + [css, page, sheets, more, js].reduce((a, s) => a + toCRLF(s).length, 0);
if (src.length !== expect) throw new Error(`size mismatch: ${src.length} != ${expect}`);
fs.writeFileSync(FILE, src, 'utf8');
console.log(`written ${FILE}: ${before} -> ${src.length}`);
