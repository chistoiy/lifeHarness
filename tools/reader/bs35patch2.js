/* 批3.5 已执行片段补丁：①重选挂回成功后清 lostAt ②?br35=detail 演示卡改走基础详情入口（绕开本地书直达阅读包装） */
const fs = require('fs');
const P = 'prototype/index-bookshelf.html';
let H = fs.readFileSync(P, 'utf8');
const before = H.length;
let hits = 0;
function rep(name, find, sub) {
  const parts = H.split(find);
  if (parts.length - 1 !== 1) { console.error('ANCHOR ' + name + ' hits=' + (parts.length - 1)); process.exit(1); }
  H = parts.join(sub); hits++; console.log('ok ' + name);
}
rep('lostAt',
String.raw`    if(brImp.lostId===b.id){b.epub.st='pre';b.epub.pr=4;delete b.epub.lost;brPreStart(b.id,4);}`,
String.raw`    if(brImp.lostId===b.id){b.epub.st='pre';b.epub.pr=4;delete b.epub.lostAt;brPreStart(b.id,4);}`);
rep('detail-entry',
"    if(k==='detail'){br35Seed();setPage('p-bookshelf');renderShelf();BR35_OLD_SHOPEN('b1');toast('演示：本地卡 · 已清缓存 · 源文件可读');return}",
"    if(k==='detail'){br35Seed();CURBK='b1';bdTab='c';renderBookDetail();navTo('p-bookDetail');renderShelf();toast('演示：本地卡 · 已清缓存 · 源文件可读');return}");
if (H.length <= before) { console.error('SIZE SHRANK'); process.exit(1); }
fs.writeFileSync(P, H, 'utf8');
console.log('DONE ' + hits + ' · ' + before + ' -> ' + H.length);
