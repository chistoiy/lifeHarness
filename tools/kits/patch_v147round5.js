/* 修紧凑网格溢出：.kit-tile 无 min-width:0/overflow，被名称固有宽度撑到 90px，5 列挤成 2 列
 * 用法：node tools/kits/patch_v147round5.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const F = 'prototype/index-kits.html';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';
const EDITS = [
  { id: 'tile 允许收缩并裁切溢出', from: '.kit-tile{display:flex;flex-direction:column;align-items:center;gap:4px;cursor:pointer;position:relative;padding:6px 2px 7px;border-radius:14px;transition:transform .12s}',
    to: '.kit-tile{display:flex;flex-direction:column;align-items:center;gap:4px;cursor:pointer;position:relative;min-width:0;overflow:hidden;padding:6px 1px 7px;border-radius:14px;transition:transform .12s}' },
  { id: '名称按列宽裁切', from: '.kit-tile .kt-nm{font-size:9.5px;font-weight:700;line-height:1.2;text-align:center;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
    to: '.kit-tile .kt-nm{font-size:9.5px;font-weight:700;line-height:1.2;text-align:center;width:100%;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' },
  { id: '图标块可收缩', from: '.kit-tile .kt-ic{width:30px;height:30px;border-radius:9px;', to: '.kit-tile .kt-ic{width:30px;height:30px;flex-shrink:0;border-radius:9px;' },
];
let src = raw;
for (const e of EDITS) {
  const n = src.split(e.from).length - 1;
  if (n !== 1) { console.error('!! ' + e.id + ' 命中 ' + n + '，零写入'); process.exit(1); }
  src = src.replace(e.from, e.to); console.log('PASS ' + e.id);
}
if (Math.abs(Buffer.byteLength(src) - Buffer.byteLength(raw)) > 600) { console.error('!! 体积异常'); process.exit(2); }
if (!DRY) { fs.writeFileSync(path.resolve(F), src); console.log('已写入 ' + F); } else console.log('dry-run');
