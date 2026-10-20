/* 从 prototype/index.html 精确截取待办垃圾箱补丁的 from 载荷（避免手抄长行出错）。
 * 每项：name + 起始标记 + 结束标记（含）；命中必须恰好 1 次，否则退出。 */
const fs = require('fs');
const src = fs.readFileSync('prototype/index.html', 'utf8');
const specs = [
  ['d', '  todoChips:[', '☑️ 已完成 128','' /* 只用起点：见下 special */],
  ['titles', "'p-sub-recmg':['记录管理'", "'],"],
  ['rec', '        <div class="flex items-center justify-between"><span>回收站自动清理</span>', '按此期限自动彻底删除</div>'],
  ['cs', 'function cycleRecSet(el,key,opts){', '（模拟持久化）\');}'],
  ['rt', '    <span class="w-3 h-3 rounded-full ${D.quads[t.q].cls} shrink-0" title="${D.quads[t.q].name}"></span></div>`).join(\'\');', '\n}'],
  ['sp', "  if(p!=='p-records'){const _sb=$('#noteSelBar')", "classList.remove('flex');}}"],
  ['del', 'function delTaskFromSheet(){', '另批原型）\')}'],
];
function grab(name, startMark, endMark, plus) {
  const a = src.indexOf(startMark);
  if (a < 0) { console.log('FAIL ' + name + ' 起点未命中'); return false; }
  if (src.indexOf(startMark, a + 1) >= 0) { console.log('FAIL ' + name + ' 起点不唯一'); return false; }
  const b = src.indexOf(endMark, a);
  if (b < 0) { console.log('FAIL ' + name + ' 终点未命中'); return false; }
  const blk = src.slice(a, b + endMark.length + (plus || 0));
  const n = src.split(blk).length - 1;
  if (n !== 1) { console.log('FAIL ' + name + ' 整块命中 ' + n + ' 次'); return false; }
  fs.writeFileSync('tools/trash6/' + name + '_from.txt', blk);
  console.log('OK   ' + name + '  ' + blk.length + ' 字节  ' + JSON.stringify(blk.slice(0, 46)) + '…');
  return true;
}
let allOk = true;
allOk = grab('titles', specs[1][1], specs[1][2]) && allOk;
allOk = grab('rec', specs[2][1], specs[2][2]) && allOk;
allOk = grab('cs', specs[3][1], specs[3][2]) && allOk;
allOk = grab('rt', specs[4][1], specs[4][2]) && allOk;
allOk = grab('sp', specs[5][1], specs[5][2]) && allOk;
allOk = grab('del', specs[6][1], specs[6][2]) && allOk;
/* D.trash 数据锚点：todoChips 行首（取到该行行尾的换行） */
allOk = grab('d', '  todoChips:[', "'⏰ 已过期 2'],") && allOk;
console.log(allOk ? '== 全部 from 载荷已生成 ==' : '== 有项未命中，请修标记 ==');
process.exit(allOk ? 0 : 1);
