/* 给 kitscheck 的紧凑化断言补几何项（5 列必须真的排得下，防 min-width 回归）
 * 用法：node tools/kits/patch_kitscheck_r2c.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const F = 'tools/kits/kitscheck.js';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';
const FROM = `   var grids=[].slice.call(g.querySelectorAll('.grid'));
   return {cols:grids.length>0&&/grid-cols-5/.test(grids[0].className),tiles:g.querySelectorAll('.kit-tile').length,
     legacy:/class="card !p-2.5/.test(g.innerHTML)}})()\`,v=>v.cols&&v.tiles>=13&&!v.legacy);`.replace(/\n/g, nl);
const TO = `   var grids=[].slice.call(g.querySelectorAll('.grid'));var gr0=grids[0]?getComputedStyle(grids[0]):null;
   var t0=grids[0]?grids[0].querySelector('.kit-tile'):null;
   var tpl=gr0?gr0.gridTemplateColumns.split(' ').map(parseFloat):[];
   var gw=grids[0]?grids[0].getBoundingClientRect().width:0;
   var sum=tpl.reduce((a,b)=>a+b,0)+(tpl.length-1)*parseFloat(gr0?gr0.columnGap:0);
   return {cols:grids.length>0&&/grid-cols-5/.test(grids[0].className),tiles:g.querySelectorAll('.kit-tile').length,
     nCol:tpl.length,fits:sum<=gw+1,minW:t0?getComputedStyle(t0).minWidth:'',
     legacy:/class="card !p-2.5/.test(g.innerHTML)}})()\`,v=>v.cols&&v.tiles>=13&&!v.legacy&&v.nCol===5&&v.fits&&v.minW==='0px');`.replace(/\n/g, nl);
const n = raw.split(FROM).length - 1;
if (n !== 1) { console.error('!! 命中 ' + n + '，零写入'); process.exit(1); }
const out = raw.replace(FROM, TO);
if (!DRY) { fs.writeFileSync(path.resolve(F), out); console.log('PASS 已写入 ' + F); } else console.log('PASS dry-run');
