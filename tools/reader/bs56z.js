/* V1.53.2 轮5.1b · 阅读器弹层层级修正
   现象：外观弹层的「取消/保存应用」被阅读器底栏（z-[70]）遮住。
   根因：sheetBrAppearance 等仍是 z-50，低于 brTop/brBottom 的 z-[70]；
        #p-readerPage 是 position:relative + z-index:auto，不构成层叠上下文，
        所以底栏与弹层直接在 #phone 内比较 z，弹层输。
   修法：所有 sheetBr* 前缀的阅读器等层弹层统一提到 z-[80]
        （高于底栏 70 / 色板 73 / 注释卡 76，且彼此一致）。 */
const fs = require('fs');
const F = 'prototype/index-bookshelf.html';
let src = fs.readFileSync(F, 'utf8');
const origLen = src.length;
const lines = src.split('\n');
let bumped = 0, listed = [];
for (let i = 0; i < lines.length; i++) {
  const l = lines[i];
  if (!/id="sheetBr[A-Za-z]*"/.test(l)) continue;
  const m = l.match(/z-(50|\[70\])/);
  if (!m) continue;
  lines[i] = l.replace(/z-(50|\[70\])/, 'z-[80]');
  bumped++;
  listed.push((l.match(/id="(sheetBr[A-Za-z]*)"/) || [])[1]);
}
if (bumped === 0) { console.error('未命中任何 sheetBr* 弹层'); process.exit(1); }
src = lines.join('\n');
fs.writeFileSync(F, src);
console.log('bumped=' + bumped + ' → ' + listed.join(', '));
console.log('size ' + origLen + ' → ' + src.length);
if (src.length < origLen * 0.95) { console.error('体积异常缩小'); process.exit(1); }
