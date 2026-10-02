/* R3-3 批C · 给 tools/xraycheck.js 追加「过程可见性」断言（锚点命中＋体积只增校验）。 */
const fs = require('fs');
const P = 'D:/dev_workplace/flutter_te/lifeHarness/tools/xraycheck.js';
const src = fs.readFileSync(P, 'utf8');
const nl = src.includes('\r\n') ? '\r\n' : '\n';
const J = (a) => a.join(nl);

const anchor = J([
  "  (r.resume && /断点在第 5 批/.test(r.toast) && /继续/.test(r.txt)) ? ok('批4 暂停留断点、原地可续跑', r.toast) : bad('批4 暂停续跑', JSON.stringify(r));",
]);

const add = J([
  anchor,
  "  /* R3-3 批C · 精化过程可见性：汇总随跑随累 · 明细默认只显最近一批 · 失败批给归类原因 */",
  "  r = await ev(`var bar=document.getElementById('xrAiBar');",
  "    var tg=document.getElementById('xrAiLogTg'),sum=document.getElementById('xrAiSum');",
  "    var rows=[].slice.call(bar.querySelectorAll('[id^=\\\"xrAiRow-\\\"]'));",
  "    var fail=rows.filter(function(x){return /已跳过 · 不影响后续/.test(x.innerText)});",
  "    return{sum:sum?sum.textContent:'',tg:tg?tg.textContent:'',collapsed:rows.length,",
  "      all:XRAI.log.length, failTxt:fail.length?fail[0].innerText.replace(/\\\\s+/g,' '):'',",
  "      hasSec:rows.some(function(x){return /用时 .*s · 约 .* tokens/.test(x.innerText)})};`);",
  "  (r.sum && /已出建议 删 \\\\d+ · 改 \\\\d+ · 补 \\\\d+/.test(r.sum) && /明细 \\\\d+\\\\/\\\\d+/.test(r.tg)",
  "    && r.collapsed === 1 && r.all > 1 && r.hasSec && /超时|端点无响应|输出不合约定|未授权/.test(r.failTxt))",
  "    ? ok('批C 面板明细：汇总随跑随累 + 默认只显最近一批 + 失败批给归类原因', r.sum + ' | ' + r.failTxt)",
  "    : bad('批C 面板明细', JSON.stringify(r));",
  "  r = await ev(`xrAiLogToggle();",
  "    var rows=[].slice.call(document.querySelectorAll('[id^=\\\"xrAiRow-\\\"]'));",
  "    var tg=document.getElementById('xrAiLogTg').textContent;",
  "    xrAiLogToggle();",
  "    var back=[].slice.call(document.querySelectorAll('[id^=\\\"xrAiRow-\\\"]')).length;",
  "    return{exp:rows.length,all:XRAI.log.length,tg:tg,collapsed:back};`);",
  "  (r.exp === r.all && r.all > 1 && /收起明细/.test(r.tg) && r.collapsed === 1)",
  "    ? ok('批C 明细可展开可收起（展开=全量，收起=最近一批）', JSON.stringify(r))",
  "    : bad('批C 明细展开', JSON.stringify(r));",
  "  r = await ev(`navTo('p-xrwords');xrcTab('ai');",
  "    var l=document.getElementById('xrcAiLast');",
  "    return{sum:!!(l&&l.querySelector('#xrAiSum')),rows:l?l.querySelectorAll('[id^=\\\"xrAiRow-\\\"]')?1:0:0,",
  "      same:/已出建议/.test(l?l.innerText:'')};`);",
  "  (r.sum && r.same) ? ok('批C X-Ray 中心精化段与面板同源（两处同构）') : bad('批C 中心页明细', JSON.stringify(r));",
  "  r = await ev(`var keep=XRAI.log.length; xrAiReview();",
  "    return{kept:XRAI.log.length===keep,fns:[typeof xrAiLogHtml,typeof xrAiLogToggle].join(',')};`);",
  "  (r.kept && r.fns === 'function,function') ? ok('批C 进审阅后明细保留（供事后按日志追）') : bad('批C 明细保留', JSON.stringify(r));",
]);

let s = src;
const i = s.indexOf(anchor);
if (i < 0) throw new Error('ANCHOR MISS');
if (s.indexOf(anchor, i + anchor.length) >= 0) throw new Error('ANCHOR AMBIGUOUS');
const tail = s.slice(i + anchor.length);
s = s.slice(0, i) + add + tail;
if (!s.endsWith(tail)) throw new Error('TAIL LOST');
fs.writeFileSync(P, s, 'utf8');
const a = Buffer.byteLength(src, 'utf8'), b = Buffer.byteLength(s, 'utf8');
console.log('bytes', a, '->', b);
if (b <= a) throw new Error('体积没长大，可疑');
