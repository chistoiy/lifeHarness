/* 批C · 把 XRAI 暴露到 window（原声明在函数作用域内，无头断言与两处同构取不到）。
   护栏：锚点唯一命中、只插入一行、体积只增、写盘前后再验一次行数增量。 */
const fs = require('fs');
const P = 'D:/dev_workplace/flutter_te/lifeHarness/prototype/index-bookshelf.html';
const s0 = fs.readFileSync(P, 'utf8');
const nl = s0.includes(String.fromCharCode(13)) ? String.fromCharCode(13, 10) : String.fromCharCode(10);
const anchor = "  var XRAI={st:'idle',b:0,n:0,err:0,budget:3000,scope:'book',sel:{},t:0,applied:0,log:[],open:false};";
if (!s0.includes(anchor)) throw new Error('ANCHOR MISS');
if (s0.indexOf(anchor) !== s0.lastIndexOf(anchor)) throw new Error('ANCHOR AMBIGUOUS');
if (s0.includes('window.XRAI=XRAI')) { console.log('already exposed'); process.exit(0); }
const add = nl + '  window.XRAI=XRAI; /* 批C：状态对象挂到全局，供两处同构渲染与无头断言共用 */';
const s = s0.replace(anchor, anchor + add);
const lines0 = s0.split(nl).length, lines1 = s.split(nl).length;
const b0 = Buffer.byteLength(s0, 'utf8'), b1 = Buffer.byteLength(s, 'utf8');
if (b1 <= b0) throw new Error('体积没长大');
if (lines1 !== lines0 + 1) throw new Error('行数增量应恰为 1，实际 ' + (lines1 - lines0));
fs.writeFileSync(P, s, 'utf8');
console.log('exposed · bytes', b0, '->', b1, '· lines +' + (lines1 - lines0));
