/* 一次性诊断：批C 明细在 ?xr=airun 后为空的真因。打印页面侧的关键事实。 */
const fs = require('fs');
const P = 'D:/dev_workplace/flutter_te/lifeHarness/tools/xraycheck.js';
const s0 = fs.readFileSync(P, 'utf8');
const CR = String.fromCharCode(13), LF = String.fromCharCode(10);
const nl = s0.includes(CR) ? CR + LF : LF;
const anchor = "  console.log('   [批C 探针] '+JSON.stringify(r).slice(0,400));";
if (!s0.includes(anchor)) throw new Error('probe anchor missing');
const diag = [
  "  console.log('   [诊断] ' + JSON.stringify(await ev(`return{st:XRAI.st,n:XRAI.n,b:XRAI.b,",
  "    logLen:XRAI.log?XRAI.log.length:'no-log',fn:typeof xrAiSimRow,html:typeof xrAiLogHtml,",
  "    demoHasSim:(window.xrAiDemo+'').indexOf('xrAiSimRow')>=0,",
  "    barHtml:(document.getElementById('xrAiBar')||{innerHTML:'no-bar'}).innerHTML.slice(0,120)};`)));",
].join(nl);
const s = s0.replace(anchor, anchor + nl + diag);
fs.writeFileSync(P, s, 'utf8');
console.log('diag added');
