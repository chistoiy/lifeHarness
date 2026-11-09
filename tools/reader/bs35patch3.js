/* 批3.5 已执行片段补丁②：导入页副标题改预载口径 */
const fs = require('fs');
const P = 'prototype/index-bookshelf.html';
let H = fs.readFileSync(P, 'utf8');
const before = H.length;
const find = String.raw`'p-localImport':['导入本地图书','EPUB · Android 13+ 隐私适配']`;
const sub = String.raw`'p-localImport':['导入本地图书','EPUB · 导入后后台预载整本 · 源文件保留原位']`;
if (H.split(find).length - 1 !== 1) { console.error('ANCHOR hits=' + (H.split(find).length - 1)); process.exit(1); }
H = H.split(find).join(sub);
if (H.length <= before) { console.error('SIZE SHRANK'); process.exit(1); }
fs.writeFileSync(P, H, 'utf8');
console.log('DONE ' + before + ' -> ' + H.length);
