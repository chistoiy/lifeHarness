/* 网格溢出根治（简版）：给工具/插件网格加 .kgrid，显式 minmax(0,1fr) + 容器裁切
 * 用法：node tools/kits/patch_v147round6.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const F = 'prototype/index-kits.html';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';
const EDITS = [
  { id: 'CSS .kgrid 轨道锁 5 列',
    from: '  .kit-tile{display:flex;flex-direction:column;align-items:center;gap:4px;cursor:pointer;position:relative;min-width:0;overflow:hidden;padding:6px 1px 7px;border-radius:14px;transition:transform .12s}',
    to: '  .kgrid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr))!important;column-gap:6px;row-gap:8px;width:100%;overflow:hidden}\n' +
      '  .kit-tile{display:flex;flex-direction:column;align-items:center;gap:4px;cursor:pointer;position:relative;min-width:0;overflow:hidden;padding:6px 1px 7px;border-radius:14px;transition:transform .12s}' },
  { id: '工具与插件网格挂 .kgrid', from: '</div><div class="grid grid-cols-5 gap-1.5">`+',
    to: '</div><div class="grid grid-cols-5 gap-1.5 kgrid">`+', expect: 2 },
];
let src = raw;
for (const e of EDITS) {
  const from = e.from.replace(/\n/g, nl), to = e.to.replace(/\n/g, nl);
  const n = src.split(from).length - 1, want = e.expect || 1;
  if (n !== want) { console.error('!! ' + e.id + ' 命中 ' + n + '（期望 ' + want + '）'); process.exit(1); }
  src = src.split(from).join(to); console.log('PASS ' + e.id);
}
const b0 = Buffer.byteLength(raw), b1 = Buffer.byteLength(src);
if (b1 < b0 || b1 > b0 + 1500) { console.error('!! 体积异常 ' + b0 + ' → ' + b1); process.exit(2); }
console.log('体积 ' + b0 + ' → ' + b1);
if (!DRY) { fs.writeFileSync(path.resolve(F), src); console.log('已写入 ' + F); } else console.log('dry-run');
