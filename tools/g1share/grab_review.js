/* 取「季度复盘」按钮块原文（含 `${archived...}` 与 \' 转义，命令行里极易被 shell 吞掉，故用脚本落文件）。 */
const fs = require('fs');
const src = fs.readFileSync('prototype/index-day_aim__goods.html', 'utf8');
const startMark = '  <div class="mt-3 flex gap-2">\n    <button class="flex-1 py-3 rounded-xl grad text-white text-sm font-bold" $' + '{archived';
const endMark = "Try → 下季草稿</button>'}";
const a = src.indexOf(startMark);
if (a < 0) { console.log('未找到复盘按钮块起点'); process.exit(1); }
const b = src.indexOf(endMark, a);
if (b < 0) { console.log('未找到复盘按钮块终点'); process.exit(1); }
const blk = src.slice(a, b + endMark.length + 1); /* +1 = 行尾换行 */
fs.writeFileSync('tools/g1share/day_review_from.txt', blk);
console.log('命中 ' + (src.split(blk).length - 1) + ' 次，长度 ' + blk.length + ' 字节');
