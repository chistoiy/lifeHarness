/* ux162check.js · 2026-10-07 产品五条反馈的原型硬闸（无头 CDP 逐屏断言）
 * 用法：node --experimental-websocket tools/ux162check.js（截图：U162_SHOTS=1）
 * 变异自证见 tools/ux162_mut.js（摘 mcAll 同步→U1 红；天气行留在主页→U3 红；Key 配置卡回来→U6 红）
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index.html')).href;
const PORT = Number(process.env.U162_PORT || 9587);
const LOG = 'tools/u162-run.log';
let pass = 0, fail = 0; const errs = [];
const log = m => { fs.appendFileSync(LOG, m + '\n'); console.log(m) };
fs.writeFileSync(LOG, '== ux162check start ' + new Date().toISOString() + ' ==\n');
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })) }) }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result; try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 260) } }
}

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.u162-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  if (!data) { bad('CDP 就绪'); try { chrome.kill('SIGKILL') } catch (e) { } return finish() }
  ws = new WebSocket(data.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 240)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF }); await wait(2800);

  /* U1 图片存储清理：全选↔取消全选，勾数与按钮文案同步 */
  const u1 = await ev(`setPage('p-sub-mediaclean');mcScan&&0;
    var btn=document.getElementById('mcAllBtn');var has=!!btn;
    if(!has)return {has:has};
    btn.click();var a={n:mcOn.size,total:MC_FILES.length,label:btn.textContent};
    btn.click();var b={n:mcOn.size,label:btn.textContent};
    return {has:has,a:a,b:b,rows:document.querySelectorAll('#mcList input[type=checkbox]').length};`);
  (u1.has && u1.a.n === u1.a.total && u1.a.total > 0 && u1.a.label === '取消全选'
    && u1.b.n === 0 && u1.b.label === '全选' && u1.rows === u1.a.total)
    ? ok('U1 清理屏全选钮：一次勾满、再点清空、文案与勾数同步', JSON.stringify(u1.a)) : bad('U1', JSON.stringify(u1));

  /* U2 无数据时全选钮隐藏（不摆一个点不动的钮） */
  const u2 = await ev(`var keep=MC_FILES.slice();MC_FILES.length=0;mcRender();
    var h=document.getElementById('mcAllBtn').style.display;MC_FILES.push.apply(MC_FILES,keep);mcRender();
    return {hidden:h,back:document.getElementById('mcAllBtn').style.display};`);
  (u2.hidden === 'none' && u2.back === '') ? ok('U2 空列表时全选钮自动隐藏') : bad('U2', JSON.stringify(u2));

  /* U3 日记天气：主页不再有，记录管理「日记」段里有且能开城市弹层 */
  const u3 = await ev(`var prof=document.getElementById('p-profile').textContent;
    setPage('p-sub-recmg');var rec=document.getElementById('p-sub-recmg').textContent;
    var row=document.getElementById('rwCity');var t=false;
    if(row){row.click();t=document.querySelector('#sheetCityPick.sheet-open')!==null;closeSheet('sheetCityPick');}
    return {inProfile:/日记天气/.test(prof),inRecmg:/日记天气/.test(rec),hasRow:!!row,opens:t};`);
  (!u3.inProfile && u3.inRecmg && u3.hasRow && u3.opens)
    ? ok('U3 日记天气已挪进记录管理并保留城市选择弹层') : bad('U3', JSON.stringify(u3));

  /* U4 服务商收成一行：页面上不再逐条铺开 */
  const u4 = await ev(`setPage('p-sub-ai');
    var sec=document.getElementById('p-sub-ai');
    var visibleRows=[].filter.call(sec.querySelectorAll('#aiProvList > div'),function(d){return d.offsetParent!==null});
    return {hasRow:!!document.getElementById('aiCurRow'),spread:visibleRows.length,
      name:(document.getElementById('aiCurName')||{}).textContent||'',
      detail:(document.getElementById('apCur')||{}).textContent||''};`);
  (u4.hasRow && u4.spread === 0 && /DeepSeek/.test(u4.name) && /api\.deepseek\.com/.test(u4.detail) && /Key 已单独保存/.test(u4.detail))
    ? ok('U4 服务商只显当前一行（列表不在页面上铺开）', JSON.stringify({ name: u4.name, detail: u4.detail.slice(0, 40) })) : bad('U4', JSON.stringify(u4));

  /* U5 点当前行 → 半屏选单，选另一家即收起并换人 */
  const u5 = await ev(`document.getElementById('aiCurRow').click();
    var open=!!document.querySelector('#sheetAiPick.sheet-open');
    var rows=[].map.call(document.querySelectorAll('#aiProvList > div'),function(d){return d.textContent.replace(/\\s+/g,' ').slice(0,18)});
    var btn=[].filter.call(document.querySelectorAll('#sheetAiPick button'),function(b){return /选用/.test(b.textContent)})[0];
    var picked=btn?btn.closest('div.card,div[class*=rounded]').textContent.slice(0,12):'';
    if(btn)btn.click();
    return {open:open,n:rows.length,picked:picked,closed:!document.querySelector('#sheetAiPick.sheet-open'),
      now:(document.getElementById('aiCurName')||{}).textContent||''};`);
  (u5.open && u5.n >= 3 && u5.closed && !/DeepSeek/.test(u5.now))
    ? ok('U5 选单开合与换人当场生效', JSON.stringify({ n: u5.n, now: u5.now })) : bad('U5', JSON.stringify(u5));

  /* U6 Key 配置卡摘除，验证状态与重新验证钮留在服务商卡 */
  const u6 = await ev(`var sec=document.getElementById('p-sub-ai').textContent;
    var vf=document.getElementById('apVerifyState');
    var card=vf?vf.closest('.card'):null;
    var inProv=card?/服务商/.test(card.textContent):false;
    var btn=[].filter.call(document.querySelectorAll('#p-sub-ai button'),function(b){return /重新验证/.test(b.textContent)})[0];
    var cur=curPage;if(btn)btn.click();
    return {hasKeyCfg:/Key 配置/.test(sec),hasEye:!!document.getElementById('gkKey'),
      inProv:inProv,verifyNow:curPage};`);
  (!u6.hasKeyCfg && !u6.hasEye && u6.inProv && u6.verifyNow === 'p-sub-aiVerify')
    ? ok('U6 Key 配置卡已摘，验证入口留在服务商卡并进验证页') : bad('U6', JSON.stringify(u6));

  /* U7 缩进同基准（原型侧：外观/记录管理两枚入口卡与组卡同为 card+p-3.5，不随实现漂移） */
  const u7 = await ev(`var p=document.getElementById('p-profile');
    var ap=[].filter.call(p.querySelectorAll('button'),function(b){return /外观/.test(b.textContent)})[0];
    var rg=[].filter.call(p.querySelectorAll('button'),function(b){return /记录管理/.test(b.textContent)})[0];
    function pad(el){var cs=getComputedStyle(el);return cs.paddingLeft+'|'+cs.paddingTop}
    return {ap:ap?pad(ap):'',rg:rg?pad(rg):'',apCard:ap?/card/.test(ap.className):false};`);
  (u7.ap && u7.ap === u7.rg && u7.apCard)
    ? ok('U7 外观/记录管理入口与组卡同缩进基准', u7.ap) : bad('U7', JSON.stringify(u7));

  (!errs.length) ? ok('U8 控制台无未捕获异常') : bad('U8', errs.slice(0, 3).join(' | '));
  finish();
  try { chrome.kill('SIGKILL') } catch (e) { }
})();
function finish() { log('== ' + pass + ' PASS / ' + fail + ' FAIL =='); process.exit(fail ? 1 : 0) }
