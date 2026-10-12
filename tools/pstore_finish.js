/* pstore_finish.js · 插件中心下架收尾两件：壳 init 行里的 renderPstore() 死调用摘掉；
 * 注册表三件（p-pstore/sheetPlugin/sheetPSDetail）的 home 改指唯一还留着副本的 index-media.html
 * （影音游专版冻结文件，随该模块开工批再定去留——见交棒工单 §3）。
 * 用法：node tools/pstore_finish.js
 */
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const HTML = path.join(ROOT, 'prototype', 'index.html');
const REG = path.join(ROOT, 'prototype', '_modules.json');

let s = fs.readFileSync(HTML, 'utf8');
const n = s.split('renderPstore();').length - 1;
if (n !== 1) throw new Error('renderPstore 调用命中 ' + n + ' 处——中止');
s = s.replace('renderPstore();', '');
fs.writeFileSync(HTML, s, 'utf8');
console.log('CUT renderPstore() 死调用');

const ids = ['p-pstore', 'sheetPlugin', 'sheetPSDetail'];
let r = fs.readFileSync(REG, 'utf8');
const reg = JSON.parse(r);
let moved = 0;
for (const sc of reg.screens) {
  if (!ids.includes(sc.id)) continue;
  const files = Object.keys(sc.files || {});
  if (!files.includes('index-media.html')) throw new Error(sc.id + ' 在影音游专版没有副本，不能改家——中止');
  if (sc.home !== 'index-media.html') { sc.home = 'index-media.html'; moved++; }
  sc.status = 'exclusive';
  if (Array.isArray(sc.reps)) sc.reps = [];
}
if (moved !== ids.length) throw new Error('home 改动数=' + moved + '（期望 ' + ids.length + '）——中止');
fs.writeFileSync(REG, JSON.stringify(reg, null, 2) + '\n', 'utf8');
console.log('REHOMED ' + ids.join(' ') + ' → index-media.html');
