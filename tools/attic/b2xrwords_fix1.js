/* 批2 修① · xrUserDictFlip 翻转时刷新管理页与菜单行（校验器红灯：只刷了面板） */
const fs = require('fs'), path = require('path');
const F = path.resolve('prototype/index-bookshelf.html');
fs.copyFileSync(F, path.resolve('tools/attic/index-bookshelf.bak-20261002-xrwords-fix1.html'));
let src = fs.readFileSync(F, 'utf8');
const anchor = `  window.xrUserDictFlip=function(){BS_SET.xrUserDict=!xrUserDictOn();xrRender();
    toast(xrUserDictOn()?'养词库已开启 · 我的词条与屏蔽恢复生效':'已切纯预置视角 · 已整理状态不回滚，重开即恢复')};`.replace(/\n/g, '\r\n');
const rep2 = `  window.xrUserDictFlip=function(){BS_SET.xrUserDict=!xrUserDictOn();xrRender();
    if(document.getElementById('xrwSum'))renderXrWords();
    var mb=document.getElementById('brMoreXrw');if(mb)mb.textContent='养词库 '+(xrUserDictOn()?'开':'关');
    toast(xrUserDictOn()?'养词库已开启 · 我的词条与屏蔽恢复生效':'已切纯预置视角 · 已整理状态不回滚，重开即恢复')};`.replace(/\n/g, '\r\n');
const n = src.split(anchor).length - 1;
if (n !== 1) { console.error('锚点非唯一(' + n + ')'); process.exit(1); }
src = src.replace(anchor, rep2);
fs.writeFileSync(F, src);
console.log('OK xrUserDictFlip 三面刷新');
