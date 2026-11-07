/* 更新 kitscheck 断言以匹配验收轮2 新行为（尺子全屏舞台/游标/零点/紧凑网格）
 * 用法：node tools/kits/patch_kitscheck_r2.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const F = 'tools/kits/kitscheck.js';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';

const OLD_START = "await step('尺子长边默认读数'";
const OLD_END = "v.dir==='long'&&v.diff<=3);";
const NEW = `  await step('尺子全屏舞台与量程读数',\`(function(){openTool('ruler');var st=$('#rulerStage');
   var target=rulerTargetMm();var card=(document.getElementById('rulerSpanCard')||{}).textContent||'';
   return {open:!st.classList.contains('hidden'),
     span:document.getElementById('rulerSpan').textContent,
     target:target,cardMm:+(card.match(/(\\\\d+)/)||[0,0])[1],
     ticks:document.querySelectorAll('#rsScale i').length,majors:document.querySelectorAll('#rsScale b').length,
     cursorLeft:document.getElementById('rsCursor').style.left}})()\`,
   v=>v.open&&/长边 游标 \\\\d+ mm/.test(v.span)&&v.cardMm===v.target&&v.ticks>=v.target-2&&v.majors>=10&&/\\\\d+px/.test(v.cursorLeft));
  await step('尺子游标拖动即自动读数',\`(function(){openTool('ruler');
   var g=rsGeom(),x0=g.left+g.ppmm*120;rsSetFromX(x0,'cur');
   return {cur:KITS.rsCur,read:(document.getElementById('rulerSpan').textContent||''),big:document.getElementById('rsBig').textContent}})()\`,
   v=>Math.abs(v.cur-120)<=2&&new RegExp('游标 '+v.cur+' mm').test(v.read)&&v.big===v.cur+' mm');
  await step('尺子零点可挪且读数=游标-零点',\`(function(){openTool('ruler');
   KITS.rsZero=0;KITS.rsCur=150;rulerPaintRs();var a=KITS.rsCur-KITS.rsZero;
   var g=rsGeom();rsSetFromX(g.left+g.ppmm*40,'zero');var b=KITS.rsCur-KITS.rsZero;
   KITS.rsZero=0;rulerPaintRs();return {before:a,after:b,z:KITS.rsZero}})()\`,v=>v.before===150&&Math.abs(v.after-110)<=2&&v.z===40);
  await step('首页工具卡已紧凑化（5 列 · kit-tile）',\`(function(){setPage('p-tools');var g=document.querySelector('#toolGrid');
   var grids=[].slice.call(g.querySelectorAll(':scope > div'));
   return {cols:/grid-cols-5/.test(grids[0].className),tiles:g.querySelectorAll('.kit-tile').length,
     legacy:/class="card !p-2.5/.test(g.innerHTML)}})()\`,v=>v.cols&&v.tiles>=13&&!v.legacy);`;

/* 按行边界切片替换，避开正则转义地狱 */
const L = raw.split(/\r\n|\n/);
const ia = L.findIndex(l => l.includes(OLD_START));
const ib = L.findIndex((l, i) => i >= ia && l.includes(OLD_END));
if (ia < 0 || ib < 0 || ib <= ia) { console.error('!! 旧断言边界未找到'); process.exit(1); }
const outLines = L.slice(0, ia).concat(NEW.split('\n')).concat(L.slice(ib + 1));
const out = outLines.join(nl);
const b0 = Buffer.byteLength(raw), b1 = Buffer.byteLength(out);
if (b1 < b0 + 500 || b1 > b0 + 8000) { console.error('!! 体积异常 ' + b0 + ' → ' + b1); process.exit(2); }
console.log('PASS kitscheck 断言更新（替换第 ' + (ia + 1) + '-' + (ib + 1) + ' 行）· 体积 ' + b0 + ' → ' + b1);
if (!DRY) { fs.writeFileSync(path.resolve(F), out); console.log('已写入 ' + F); } else console.log('dry-run');
