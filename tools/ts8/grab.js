/* 生成 ts8 的 from 载荷（含 `${c}` 的模板串不能手抄，统一从原文截取；按 LF 归一，patch 时自适应）。 */
const fs = require('fs');
const src = fs.readFileSync('prototype/index.html', 'utf8').replace(/\r\n/g, '\n');
function grab(name, startMark, endMark) {
  const a = src.indexOf(startMark);
  if (a < 0 || src.indexOf(startMark, a + 1) >= 0) { console.log('FAIL ' + name + ' 起点问题'); return false; }
  const b = src.indexOf(endMark, a);
  if (b < 0) { console.log('FAIL ' + name + ' 终点问题'); return false; }
  const blk = src.slice(a, b + endMark.length);
  if (src.split(blk).length - 1 !== 1) { console.log('FAIL ' + name + ' 整块不唯一（命中 ' + (src.split(blk).length - 1) + '）'); return false; }
  fs.writeFileSync('tools/ts8/' + name + '_from.txt', blk);
  console.log('OK   ' + name + '  ' + blk.length + ' 字节 ' + JSON.stringify(blk.slice(0, 46)) + '…');
  return true;
}
let all = true;
all = grab('rank', "onclick=\"toast('${c} 明细列表（模拟）", "\')\"") && all;
all = grab('anchor', "let tsScope='w';", "let tsScope='w';") && all;
console.log(all ? '== from 载荷就绪 ==' : '== 有项未命中 ==');
process.exit(all ? 0 : 1);
