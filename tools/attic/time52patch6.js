const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const size0 = s.length;
const stale = [
  "function tpAdd(keep){const sd=+WHEELS.tpSd.items[WHEELS.tpSd.i].slice(3);",
  "  let s=tpMin('tpSh')*60+tpMin('tpSm');let e=tpEd();if(e<=s)e=Math.min(s+60,1439);",
  "  const name=tpSel.sub||tpSel.cat;",
  "  blocks.push({s:s,e:Math.min(1439,e),cat:tpSel.cat,note:$('#tpNote').value.trim()||(name+(tpSel.sub?' · '+tpSel.cat:''))});",
  "  renderCal();",
  "  const cross=sd!==19?'（模拟：演示仅展示 9/19 · 真实版按所选日期落库）':'';",
  "  if(keep){$('#tpNote').value='';toast('✔ 已添加 '+fmt(s)+'-'+fmt(Math.min(1439,e))+' · '+name+'（9月'+sd+'日）'+cross)}",
  "  else{closeSheet('sheetTimePick');toast('✔ 已添加 · 轴/块/日/周四视图与时间账本同步（L4）'+cross)}}",
].join('\n');
const n = s.split(stale).length - 1;
if (n !== 1) { console.log('stale count:', n); process.exit(1); }
s = s.replace(stale, '/* V1.52：旧 tpAdd 已删除（与统一计时版重名冲突·见块视图数据段） */');
fs.writeFileSync(P, s);
console.log('removed stale tpAdd | ' + size0 + ' -> ' + s.length);
