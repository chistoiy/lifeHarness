/* 生成 sync7 的 from 载荷（从 prototype/index-sync.html 精确截取）。
 * 统一按 LF 截取，patch.js 落盘前会按目标文件主导行尾自适应。 */
const fs = require('fs');
const src = fs.readFileSync('prototype/index-sync.html', 'utf8').replace(/\r\n/g, '\n');
function grab(name, startMark, endMark) {
  const a = src.indexOf(startMark);
  if (a < 0 || src.indexOf(startMark, a + 1) >= 0) { console.log('FAIL ' + name + ' 起点问题'); return false; }
  const b = src.indexOf(endMark, a);
  if (b < 0) { console.log('FAIL ' + name + ' 终点问题'); return false; }
  const blk = src.slice(a, b + endMark.length);
  if (src.split(blk).length - 1 !== 1) { console.log('FAIL ' + name + ' 整块不唯一'); return false; }
  fs.writeFileSync('tools/sync7/' + name + '_from.txt', blk);
  console.log('OK   ' + name + '  ' + blk.length + ' 字节 ' + JSON.stringify(blk.slice(0, 40)) + '…');
  return true;
}
let all = true;
all = grab('tier', 'function pickTier(el){', "  computeDiff();\n}") && all;
all = grab('row', '      <div id="svcForm"></div>', '</div>') && all;
console.log(all ? '== from 载荷就绪 ==' : '== 有项未命中 ==');
process.exit(all ? 0 : 1);
