/* 修上一批断言自身的三处笔误（正则多吞一层转义 / 网格选择器取错子元素 / 零点断言取复位后的值）
 * 用法：node tools/kits/patch_kitscheck_r2b.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const F = 'tools/kits/kitscheck.js';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';
const EDITS = [
  { id: '量程断言正则去多余转义', from: `v=>v.open&&/长边 游标 \\\\d+ mm/.test(v.span)&&v.cardMm===v.target&&v.ticks>=v.target-2&&v.majors>=10&&/\\\\d+px/.test(v.cursorLeft));`,
    to: `v=>v.open&&/长边 游标 \\d+ mm/.test(v.span)&&v.cardMm===v.target&&v.ticks>=v.target-2&&v.majors>=10&&/\\d+px/.test(v.cursorLeft));` },
  { id: '零点断言在复位前取值', from: `   KITS.rsZero=0;KITS.rsCur=150;rulerPaintRs();var a=KITS.rsCur-KITS.rsZero;
   var g=rsGeom();rsSetFromX(g.left+g.ppmm*40,'zero');var b=KITS.rsCur-KITS.rsZero;
   KITS.rsZero=0;rulerPaintRs();return {before:a,after:b,z:KITS.rsZero}})()\`,v=>v.before===150&&Math.abs(v.after-110)<=2&&v.z===40);`,
    to: `   KITS.rsZero=0;KITS.rsCur=150;rulerPaintRs();var a=KITS.rsCur-KITS.rsZero;
   var g=rsGeom();rsSetFromX(g.left+g.ppmm*40,'zero');var b=KITS.rsCur-KITS.rsZero,z=KITS.rsZero;
   KITS.rsZero=0;rulerPaintRs();return {before:a,after:b,z:z}})()\`,v=>v.before===150&&Math.abs(v.after-110)<=2&&Math.abs(v.z-40)<=2);` },
  { id: '网格断言取真正的网格容器', from: `   var grids=[].slice.call(g.querySelectorAll(':scope > div'));
   return {cols:/grid-cols-5/.test(grids[0].className),tiles:g.querySelectorAll('.kit-tile').length,`,
    to: `   var grids=[].slice.call(g.querySelectorAll('.grid'));
   return {cols:grids.length>0&&/grid-cols-5/.test(grids[0].className),tiles:g.querySelectorAll('.kit-tile').length,` },
];
let src = raw;
for (const e of EDITS) {
  const from = e.from.replace(/\n/g, nl), to = e.to.replace(/\n/g, nl);
  const n = src.split(from).length - 1;
  if (n !== 1) { console.error('!! ' + e.id + ' 命中 ' + n + '，零写入'); process.exit(1); }
  src = src.replace(from, to); console.log('PASS ' + e.id);
}
if (!DRY) { fs.writeFileSync(path.resolve(F), src); console.log('已写入 ' + F); } else console.log('dry-run');
