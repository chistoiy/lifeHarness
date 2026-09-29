/* 修尺子全屏舞台读数区三行重叠（rsRead / rsGuideTip / rsZeroPos 纵向排布）
 * 用法：node tools/kits/patch_v147round4.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const F = 'prototype/index-kits.html';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';
const EDITS = [
  { id: '读数块上移并留高', from: '#rsRead{position:absolute;left:0;right:0;top:196px;text-align:center;padding:0 14px}',
    to: '#rsRead{position:absolute;left:0;right:0;top:190px;height:96px;text-align:center;padding:0 14px;overflow:hidden}' },
  { id: '零点行并入读数块内（不再压提示）', from: '  #rsRead .sub{font-size:11px;opacity:.62;margin-top:3px;font-variant-numeric:tabular-nums}',
    to: '  #rsRead .sub{font-size:11px;opacity:.62;margin-top:3px;font-variant-numeric:tabular-nums}\n  #rsZeroPos{margin-top:2px;font-size:10px;opacity:.5}' },
  { id: '提示行下移', from: '#rsGuideTip{position:absolute;top:252px;left:14px;right:14px;text-align:center;font-size:10px;opacity:.5}',
    to: '#rsGuideTip{position:absolute;top:294px;left:14px;right:14px;text-align:center;font-size:10px;opacity:.5;line-height:1.5}' },
  { id: '参照框再下移让位', from: '#rsGuide{position:absolute;top:270px;bottom:56px;left:14px;right:14px;border:1.5px dashed rgba(100,116,139,.45);border-radius:18px;pointer-events:none}',
    to: '#rsGuide{position:absolute;top:326px;bottom:56px;left:14px;right:14px;border:1.5px dashed rgba(100,116,139,.45);border-radius:18px;pointer-events:none}' },
  { id: '量程读数改一行内联（去掉重复的游标行）', from: '<div id="rsRead"><div class="big" id="rsBig">0 mm</div><div class="sub" id="rulerSpan"></div><div class="sub" id="rsZeroPos"></div></div>',
    to: '<div id="rsRead"><div class="big" id="rsBig">0 mm</div><div class="sub" id="rulerSpan"></div><div id="rsZeroPos"></div></div>' },
];
let src = raw;
for (const e of EDITS) {
  const from = e.from.replace(/\n/g, nl), to = e.to.replace(/\n/g, nl);
  const n = src.split(from).length - 1;
  if (n !== 1) { console.error('!! ' + e.id + ' 命中 ' + n + '，零写入'); process.exit(1); }
  src = src.replace(from, to); console.log('PASS ' + e.id);
}
const b0 = Buffer.byteLength(raw), b1 = Buffer.byteLength(src);
if (Math.abs(b1 - b0) > 1200) { console.error('!! 体积异常 ' + b0 + ' → ' + b1); process.exit(2); }
console.log('体积 ' + b0 + ' → ' + b1);
if (!DRY) { fs.writeFileSync(path.resolve(F), src); console.log('已写入 ' + F); } else console.log('dry-run');
