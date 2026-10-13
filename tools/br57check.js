/* V1.53.4 阅读器选区体验批 · 原型专项校验（CDP 无头 Chrome · 深链逐屏）
 * 覆盖：④粒度两态 ⑤工具条配置渲染+设置行 ②二选一 ③审阅默认折叠可展开 ⑥打开方式两态+书架定位。
 * 用法：node --experimental-websocket tools/br57check.js
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const F = 'prototype/index-bookshelf.html';
const PORT = Number(process.env.B57_PORT || 9598);
const SHOTS = 'prototype/shots';
let pass = 0, fail = 0; const errs = [];
const log = (m) => console.log(m);
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')); };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')); };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function get(u) { return new Promise((res) => { try { require('http').get(u, (r) => { let d = ''; r.on('data', (c) => d += c); r.on('end', () => res(d)); }).on('error', () => res(null)); } catch (e) { res(null); } }); }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise((res) => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })); }); }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result;
  try { return JSON.parse(r.value); } catch (e) { return { __err: (r && (r.value || r.description)) || JSON.stringify(m).slice(0, 200) }; }
}
async function shot(name) {
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  const b = m.result && m.result.data;
  if (!b) { bad('截图 ' + name); return; }
  fs.mkdirSync(SHOTS, { recursive: true });
  fs.writeFileSync(path.join(SHOTS, name), Buffer.from(b, 'base64'));
  log('  截图 ' + name + ' (' + Math.round(Buffer.from(b, 'base64').length / 1024) + 'KB)');
}
async function go(q) {
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve(F)).href + (q ? '?' + q : '') });
  await wait(2600);
}

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish(); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.br57-profile'),
    '--disable-extensions', '--no-default-browser-check', '--window-size=430,900',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some((x) => x.type === 'page')) break; } catch (e) { } } await wait(300); }
  ws = new WebSocket(data.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => { ws.addEventListener('open', r); setTimeout(r, 3000); });
  ws.addEventListener('message', (e2) => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') { const t = ((m.params.exceptionDetails.exception || {}).description || m.params.exceptionDetails.text || '').slice(0, 160);
      if (!/tailwind is not defined/.test(t)) errs.push(t); /* Tailwind CDN 首帧竞态＝环境噪声，白名单 */ } });
  await cmd('Runtime.enable'); await cmd('Page.enable');

  /* ④ 选字：长按命中单字 */
  await go('br57=gran');
  let r = await ev(`var s=brV.sel;return{sel:s,o:s?(s.o1-s.o0):-1,chips:[].map.call(document.querySelectorAll('#brSelActs .sdb span'),function(x){return x.textContent}),
    bar:!document.getElementById('brSelBar').classList.contains('hidden')};`);
  (r.sel && r.o === 1 && r.chips.length === 8 && r.bar) ? ok('④选字 长按命中单字 · 默认8枚工具条', 'len=' + r.o) : bad('④选字', JSON.stringify(r));
  await shot('br57-gran.png');

  /* ④ 选句：命中整句 */
  await go('br57=sent');
  r = await ev(`var s=brV.sel;return{s:s,gran:BS_SET.brSelGran};`);
  (r.s && r.s.o1 - r.s.o0 >= 3 && r.gran === '选句') ? ok('④选句 长按命中整句', 'len=' + (r.s.o1 - r.s.o0)) : bad('④选句', JSON.stringify(r));
  await shot('br57-sent.png');

  /* ⑤ 工具条按配置渲染 */
  await go('br57=bar');
  r = await ev(`return{chips:[].map.call(document.querySelectorAll('#brSelActs .sdb span'),function(x){return x.textContent})};`);
  JSON.stringify(r.chips) === JSON.stringify(['AI 解读', '复制', '划线', '分享', '书摘']) ? ok('⑤工具条顺序/显隐随配置', r.chips.join('|')) : bad('⑤工具条渲染', JSON.stringify(r.chips));
  await shot('br57-bar.png');

  /* ⑤ 设置行与移除动作 */
  await go('br57=set');
  r = await ev(`var t=document.getElementById('rsGroups').innerText;
    var on=document.getElementById('rsGroups').querySelectorAll('[onclick^="bpMv"]').length;
    var b4=[].slice.call(document.querySelectorAll('#rsGroups .chip')).find(function(x){return /选字/.test(x.textContent)});
    return{hasGran:/长按选择粒度/.test(t),hasOps:/选区工具条工具/.test(t),n8:/8 项/.test(t),mvBtns:on,onTxt:b4?b4.className:'?'};`);
  (r.hasGran && r.hasOps && r.n8 && r.mvBtns === 16 && /chip-on/.test(r.onTxt)) ? ok('④⑤ 设置两行 · 8 项 · ↑↓钮 · 选字选中', JSON.stringify(r)) : bad('⑤设置行', JSON.stringify(r));
  await shot('br57-set.png');
  r = await ev(`bpRm(5);var t=document.getElementById('rsGroups').innerText;return{t:/7 项/.test(t),off:/＋ X-Ray/.test(t)};`);
  (r.t && r.off) ? ok('⑤ 移除后 7 项 · 未启用区出现「＋ X-Ray」') : bad('⑤ 移除动作', JSON.stringify(r));

  /* ② 二选一 → ③ 审阅默认折叠 → 发送 → 结果 */
  await go('br57=choice');
  r = await ev(`return{choice:!document.getElementById('sheetBrAiChoice').classList.contains('hidden'),q:(document.getElementById('brChoiceQuote').textContent||'').length,
    btns:[].map.call(document.querySelectorAll('#sheetBrAiChoice button b'),function(x){return x.textContent})};`);
  (r.choice && r.q > 0 && r.btns[0] === '解释词句' && r.btns[1] === '深度解读') ? ok('② 二选一弹层 · 引文与两行', r.btns.join('|')) : bad('②二选一', JSON.stringify(r));
  await shot('br57-choice.png');

  r = await ev(`brAiPick('explain');var sys=document.getElementById('brRvSysBox'),usr=document.getElementById('brRvUsrBox');
    return{rv:!document.getElementById('sheetAiReview').classList.contains('hidden'),
      task:document.getElementById('brRvTask').textContent,
      sysHidden:sys.classList.contains('hidden'),usrHidden:usr.classList.contains('hidden'),
      peek:(document.getElementById('brRvSysPeek').textContent||'').length,chev:document.getElementById('brRvSysChev').textContent};`);
  (r.rv && r.sysHidden && r.usrHidden && r.peek > 4 && r.chev === '∨' && r.task === '阅读 · 词句解释') ? ok('③ 审阅 System/User 默认折叠 · 标题行可辨', JSON.stringify(r)) : bad('③审阅折叠', JSON.stringify(r));
  await shot('br57-review-fold.png');

  r = await ev(`brRvTog('Sys');var sys=document.getElementById('brRvSysBox');
    return{open:!sys.classList.contains('hidden'),chev:document.getElementById('brRvSysChev').textContent,txt:(sys.textContent||'').slice(0,18)};`);
  (r.open && r.chev === '∧') ? ok('③ 点标题展开 · 箭头翻转', r.txt) : bad('③展开', JSON.stringify(r));
  await shot('br57-review-open.png');

  r = await ev(`brAiSend();return{ai:!document.getElementById('sheetBrAi').classList.contains('hidden'),
    title:document.getElementById('brAiTitle').textContent};`);
  (r.ai && r.title === 'AI 解释') ? ok('② 发送后结果弹层 · 标题按模式', r.title) : bad('②结果弹层', JSON.stringify(r));
  await wait(1600);
  r = await ev(`return{out:(document.getElementById('brAiOut').innerText||'').slice(0,20)};`);
  /【释义】/.test(r.out) ? ok('② 解释结果逐段流出', r.out) : bad('②流出', JSON.stringify(r));
  await shot('br57-result.png');

  /* ⑥ 打开方式两态 + 书架定位 */
  await go('br57=open');
  r = await ev(`var b=document.getElementById('brOpenBody');return{sh:!document.getElementById('sheetBrOpen').classList.contains('hidden'),
    t:(b.innerText||'').slice(0,40),hasImport:!!b.querySelector('[onclick="brOpenConfirm()"]')};`);
  (r.sh && /导入这本书/.test(r.t) && /我们仨/.test(r.t) && r.hasImport) ? ok('⑥ 未导入=导入确认弹层', r.t) : bad('⑥导入确认', JSON.stringify(r));
  await shot('br57-open-new.png');

  await go('br57=dup');
  r = await ev(`var b=document.getElementById('brOpenBody');return{t:(b.innerText||'').slice(0,44),
    loc:!!b.querySelector('[onclick^="shLocate"]')};`);
  (r.loc && /已在书架/.test(r.t) && /思考，快与慢/.test(r.t)) ? ok('⑥ 已导入=提醒+定位钮', r.t) : bad('⑥已导入', JSON.stringify(r));
  await shot('br57-open-dup.png');

  await ev(`shLocate('b1');return 1;`); // 触发即走
  await wait(700);
  r = await ev(`var el=document.querySelector('#shBody .br-flash-loc');
    return{page:curPage,flash:!!el,toast:/已在书架定位/.test((document.getElementById('toast')||{}).innerText||'')};`);
  (r.page === 'p-bookshelf' && r.flash) ? ok('⑥ 跳书架并高亮定位（闪烁环在）', JSON.stringify(r)) : bad('⑥定位', JSON.stringify(r));
  await shot('br57-locate.png');

  /* 收尾：异常与 emoji */
  const EM = '[\\u{1F300}-\\u{1FAFF}\\u{FE0F}]';
  r = await ev(`var re=new RegExp(${JSON.stringify(EM)},'gu');var out='';
    ['sheetBrAiChoice','sheetAiReview','sheetBrOpen'].forEach(function(id){var el=document.getElementById(id);out+=(el?el.innerText:'')});
    var m=out.match(re)||[];return{emoji:m.join(''),js:typeof brSelGranWord+typeof brOpenEpub+typeof bpMv+typeof shLocate};`);
  (!r.emoji && r.js === 'functionfunctionfunctionfunction') ? ok('新增三弹层零 emoji · 四函数在位') : bad('emoji/函数缺位', JSON.stringify(r));
  if (errs.length) bad('运行期异常', errs.join(' | ')); else ok('全程零 JS 异常');
  return finish();
})().catch((e) => { bad('脚本自身', String(e).slice(0, 200)); finish(); });

function finish() { try { ws && ws.close(); } catch (e) { } log(''); log('结果：' + pass + ' 绿 / ' + fail + ' 红'); process.exit(fail ? 1 : 0); }
