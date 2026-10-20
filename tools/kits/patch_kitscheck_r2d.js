/* 用真实几何重写「紧凑化」断言：单枚宽度必须 ≈ 行宽/5（能排 5 枚），并保留每行计数信息
 * 用法：node tools/kits/patch_kitscheck_r2d.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const F = 'tools/kits/kitscheck.js';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';
const L = raw.split(/\r\n|\n/);
const START = "await step('首页工具卡已紧凑化";
const END = "!v.legacy&&v.nCol===5";
const ia = L.findIndex(l => l.includes(START));
const ib = L.findIndex((l, i) => i >= ia && l.includes(END));
if (ia < 0 || ib < 0) { console.error('!! 边界未找到'); process.exit(1); }
const BT = '`';
const NEW = [
  "  await step('首页工具卡已紧凑化（每行可排 5 枚 · kit-tile）'," + BT + "(function(){setPage('p-tools');var g=document.querySelector('#toolGrid');",
  "   var grids=[].slice.call(g.querySelectorAll('.grid'));var gr0=grids[0]?getComputedStyle(grids[0]):null;",
  "   var t0=grids[0]?grids[0].querySelector('.kit-tile'):null;",
  "   var gw=grids[0]?grids[0].getBoundingClientRect().width:0;",
  "   var tw=t0?t0.getBoundingClientRect().width:0;",
  "   var kids=grids[0]?[].slice.call(grids[0].children).map(x=>x.getBoundingClientRect()):[];",
  "   var y=kids.length?kids[0].top:0;",
  "   return {tiles:g.querySelectorAll('.kit-tile').length,disp:gr0?gr0.display:'',perRow:kids.filter(r=>Math.abs(r.top-y)<2).length,",
  "     fits5:tw>0&&Math.floor(gw/tw)===5,minW:t0?getComputedStyle(t0).minWidth:'',",
  "     legacy:/class=\"card !p-2.5/.test(g.innerHTML)}})()" + BT + ",",
  "   v=>v.tiles>=13&&!v.legacy&&v.fits5&&v.minW==='0px'&&v.perRow>=2);",
].join('\n');
const out = L.slice(0, ia).concat(NEW.split('\n')).concat(L.slice(ib + 1)).join(nl);
if (Buffer.byteLength(out) < Buffer.byteLength(raw) - 600) { console.error('!! 体积异常'); process.exit(2); }
console.log('替换第 ' + (ia + 1) + '-' + (ib + 1) + ' 行 · 体积 ' + Buffer.byteLength(raw) + ' → ' + Buffer.byteLength(out));
if (!DRY) { fs.writeFileSync(path.resolve(F), out); console.log('已写入 ' + F); } else console.log('dry-run');
