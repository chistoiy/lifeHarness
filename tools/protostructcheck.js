/* 原型结构体检：防「HTML 少一个/多一个闭合标签」把壳层拆坏
 * —— 这类破坏不会报 JS 语法错（checkinline 查不出），也不会让按 id 取节点的断言失败，
 *    只有量结构与宽度才看得见。用法：node --experimental-websocket tools/protostructcheck.js */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const F = 'prototype/index.html';
const PORT = Number(process.env.PS_PORT || 9591);
const LOG = 'tools/protostruct-run.log';
let pass = 0, fail = 0; const errs = [];
const log = m => { fs.appendFileSync(LOG, m + '\n'); console.log(m) };
fs.writeFileSync(LOG, '== protostructcheck start ' + new Date().toISOString() + ' ==\n');
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })) }) }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result; try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 200) } }
}
/* 静态配平基线：index.html 历史上就比闭合多一个 <div（浏览器在 </body> 处自动收口），
   所以这里锁「等于基线值」而不是等于 0——多一个或少一个闭合都立刻红。 */
const BASE_DIV_DIFF = 1, BASE_SECTION_DIFF = 0;
const src = fs.readFileSync(F, 'utf8');
const divDiff = (src.match(/<div[\s>]/g) || []).length - (src.match(/<\/div>/g) || []).length;
const secDiff = (src.match(/<section[\s>]/g) || []).length - (src.match(/<\/section>/g) || []).length;
(divDiff === BASE_DIV_DIFF ? ok : bad)('静态 div 配平 = 基线 ' + BASE_DIV_DIFF, '实际 ' + divDiff);
(secDiff === BASE_SECTION_DIFF ? ok : bad)('静态 section 配平 = 基线 ' + BASE_SECTION_DIFF, '实际 ' + secDiff);

/* 治理批拍板：p-records/p-habits 等代表屏已下架（直达专版），关键页表随之收敛为壳 home 屏 */
const PAGES = ['p-dashboard', 'p-todo', 'p-calendar', 'p-profile', 'p-inbox',
  'p-sub-ai', 'p-aiUsage', 'p-logs', 'p-timeStats'];

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.ps-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  ws = new WebSocket(data.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 200)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve(F)).href }); await wait(2800);

  /* ① 所有 .page 段都必须在壳层容器里（漏闭合标签会把后续段甩到壳外） */
  const r1 = await ev(`var all=$$('section.page'),inMain=0;
    [].forEach.call(all,function(s){if(s.closest('main'))inMain++;});
    return {all:all.length,inMain:inMain,mainW:Math.round((document.querySelector('main')||{getBoundingClientRect:()=>({width:0})}).getBoundingClientRect().width)};`);
  (r1.all > 20 && r1.all === r1.inMain && r1.mainW > 380)
    ? ok('① ' + r1.all + ' 个 page 段全部在 main 壳内 · 壳宽 ' + r1.mainW + 'px') : bad('① page 段归属', JSON.stringify(r1));

  /* ② 逐页激活量宽：被拆坏的页会塌成 padding 宽（≈40px） */
  const r2 = await ev(`var out=[];['${PAGES.join("','")}'].forEach(function(p){
      var el=document.getElementById(p);if(!el){out.push(p+':missing');return}
      $$('.page').forEach(function(s){s.classList.remove('active')});
      el.classList.add('active');
      out.push(p+':'+Math.round(el.getBoundingClientRect().width));
    });return {out:out};`);
  const thin = (r2.out || []).filter(x => !/:missing/.test(x) && parseInt(x.split(':')[1], 10) < 350);
  const missing = (r2.out || []).filter(x => /missing/.test(x));
  (thin.length === 0 && missing.length === 0)
    ? ok('② ' + r2.out.length + ' 个关键页激活后宽度均 >350px', r2.out.join(' ')) : bad('② 页面宽度', '窄=' + thin.join(',') + ' 缺=' + missing.join(','));

  /* ③ 关键节点父子关系没被拆散（服务商列表在卡内、AI 记录页在壳内） */
  const r3 = await ev(`var list=document.getElementById('aiProvList');
    var card=list?list.closest('.card'):null;
    var au=document.getElementById('p-aiUsage');
    return {listInCard:!!card,cardHasTitle:!!(card&&/服务商管理/.test(card.textContent)),
      auInMain:!!(au&&au.closest('main')),
      usageCardInAiPage:!!(document.getElementById('auK1')&&document.getElementById('auK1').closest('#p-sub-ai'))};`);
  (r3.listInCard && r3.cardHasTitle && r3.auInMain && r3.usageCardInAiPage)
    ? ok('③ 服务商卡与 AI 使用记录入口卡层级正确') : bad('③ 层级', JSON.stringify(r3));

  /* ④ 零 JS 异常 */
  (errs.length === 0 ? ok : bad)('④ 运行期零 JS 异常', errs.join(' | '));
  finish();
  try { chrome.kill('SIGKILL') } catch (e) { }
})();

function finish() { log('== ' + pass + ' PASS / ' + fail + ' FAIL =='); process.exit(fail ? 1 : 0); }
