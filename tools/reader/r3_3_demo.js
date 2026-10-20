/* 批C · 深链演示态（xrAiDemo）也生成逐批明细：否则 ?xr=airun/airev 两屏看不到新链路。 */
const fs = require('fs');
const P = 'D:/dev_workplace/flutter_te/lifeHarness/prototype/index-bookshelf.html';
const s0 = fs.readFileSync(P, 'utf8');
const CR = String.fromCharCode(13), LF = String.fromCharCode(10);
const nl = s0.includes(CR) ? CR + LF : LF;

function rep(from, to, label) {
  if (!s0.includes(from)) throw new Error('ANCHOR MISS: ' + label);
  if (s0.indexOf(from) !== s0.lastIndexOf(from)) throw new Error('AMBIGUOUS: ' + label);
  return s0.replace(from, to);
}

let s = s0;
// run 态：1..5 批各一条明细（第 4 批＝失败样例，与 XRAI.err 对齐）
s = rep(
  "    if(mode==='run'){XRAI.st='run';XRAI.n=dn;XRAI.b=5;XRAI.err=4;if(XRAI.t){clearInterval(XRAI.t);XRAI.t=0}xrAiBarRender();return}",
  "    if(mode==='run'){XRAI.st='run';XRAI.n=dn;XRAI.b=5;XRAI.err=4;XRAI.open=false;"
  + "XRAI.log=[];for(var q=1;q<=5;q++)XRAI.log.push(xrAiSimRow(q,dn));"
  + "if(XRAI.t){clearInterval(XRAI.t);XRAI.t=0}xrAiBarRender();return}",
  'demo-run'
);
// rev 态：跑完整本，明细保留全量（工单：中止/完成后明细留得住）
s = rep(
  "    if(mode==='rev'){XRAI.st='done';XRAI.n=dn;XRAI.b=dn;XRAI.sel={};XRAI_SUG.forEach(function(x){XRAI.sel[x.k]=true});xrAiBarRender();xrAiReview();return}",
  "    if(mode==='rev'){XRAI.st='done';XRAI.n=dn;XRAI.b=dn;XRAI.err=4;XRAI.open=false;"
  + "XRAI.log=[];for(var q=1;q<=dn;q++)XRAI.log.push(xrAiSimRow(q,dn));"
  + "XRAI.sel={};XRAI_SUG.forEach(function(x){XRAI.sel[x.k]=true});xrAiBarRender();xrAiReview();return}",
  'demo-rev'
);

const b0 = Buffer.byteLength(s0, 'utf8'), b1 = Buffer.byteLength(s, 'utf8');
if (b1 <= b0) throw new Error('体积没长大');
fs.writeFileSync(P, s, 'utf8');
console.log('demo wired · bytes', b0, '->', b1, '· lines +' + (s.split(nl).length - s0.split(nl).length));
