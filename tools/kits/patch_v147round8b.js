/* 清理上一批替换留下的孤儿行（原函数尾的 ` renderPlugins()}`）
 * 用法：node tools/kits/patch_v147round8b.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const F = 'prototype/index-kits.html';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';
const L = raw.split(/\r\n|\n/);
const i = L.findIndex(l => l.includes("items.length>0)}"));
if (i < 0 || L[i + 1] !== ' renderPlugins()}') { console.error('!! 孤儿行不在预期位置：' + JSON.stringify(L.slice(i, i + 2))); process.exit(1); }
L[i] = L[i].replace(/\}$/, '') + '}';
L.splice(i + 1, 1);
const out = L.join(nl);
console.log('已删孤儿行并闭合函数 @' + (i + 1));
if (!DRY) { fs.writeFileSync(path.resolve(F), out); console.log('已写入 ' + F); } else console.log('dry-run');
