/* 小工具整模块下架 · 共享面原型回归校验（CDP 无头）
 * 断言：屏/弹层/JS 段/入口/栏目池全部归零，且全站 boot 与逐屏切换无残留引用报错
 * 用法：node --experimental-websocket tools/kits/r6check.js [--shots] */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.R6_PORT || 9533);
const SHOTS = process.argv.includes('--shots');
const SHOTDIR = 'prototype/shots/r6';
const LOG = 'tools/kits/r6-run.log';
let pass = 0, fail = 0;
const log = m => { fs.appendFileSync(LOG, m + '\n'); console.log(m); };
fs.writeFileSync(LOG, '== r6check start ' + new Date().toISOString() + ' ==\n');
function ok(n, i) { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')); }
function bad(n, i) { fail++; log('FAIL ' + n + '  →  ' + (i || '')); }
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)); }).on('error', () => res(null)); } catch (e) { res(null); } }); }

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在', CHROME); return fin(); }
  if (SHOTS) fs.mkdirSync(SHOTDIR, { recursive: true });
  log('launch chrome · port ' + PORT);
  spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/kits/.chrome-r6'), '--disable-extensions',
    '--no-default-browser-check', '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); break; } catch (e) { } } await wait(300); }
  if (!data || !data.length) { bad('CDP 启动', '端口无响应（换 R6_PORT 重试）'); return fin(); }
  const pt = data.find(t => t.type === 'page' && /about:blank/.test(t.url)) || data.find(t => t.type === 'page');
  if (!pt) { bad('CDP 目标', '无 page 目标：' + data.map(t => t.type).join(',')); return fin(); }
  const ws = new WebSocket(pt.webSocketDebuggerUrl);
  let idc = 0; const pend = new Map(); const errs = [];
  ws.addEventListener('message', ev => { const m = JSON.parse(ev.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || JSON.stringify(m.params.exceptionDetails)).slice(0, 200));
    if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') errs.push(String((m.params.args[0] || {}).value || '').slice(0, 140)); });
  const send = (m, p = {}) => new Promise(r => { const id = ++idc; pend.set(id, r); ws.send(JSON.stringify({ id, method: m, params: p })); });
  const evl = (expr, aw) => send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: !!aw })
    .then(r => r.result && r.result.exceptionDetails
      ? { __err: [r.result.exceptionDetails.text, (r.result.exceptionDetails.exception || {}).description || (r.result.exceptionDetails.exception || {}).value].filter(Boolean).join(' | ').slice(0, 200) }
      : (r.result && r.result.result ? r.result.result.value : undefined));
  const evj = async expr => {
    const r = await evl('(()=>{try{return JSON.stringify(' + expr + ')}catch(e){return JSON.stringify({__thunk:String(e&&e.message||e)})}})()');
    if (!r || r.__err) return { __err: (r && r.__err) || 'empty' };
    try { return JSON.parse(r); } catch (e) { return { __err: 'parse:' + String(r).slice(0, 120) }; }
  };
  const shot = async name => {
    if (!SHOTS) return;
    await evl('new Promise(r=>setTimeout(r,350))', true);
    const s = await send('Page.captureScreenshot', { format: 'png' });
    if (s.result && s.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(s.result.data, 'base64'));
  };
  await new Promise(r => ws.addEventListener('open', r));
  await send('Runtime.enable'); await send('Page.enable');
  await send('Page.navigate', { url: URLF });
  await wait(1500);
  await evl('localStorage.clear();1');
  await send('Page.navigate', { url: URLF }); await wait(900);
  let ready = false;
  for (let i = 0; i < 40; i++) { if ((await evl('typeof setPage')) === 'function') { ready = true; log('脚本就绪 · 第 ' + (i + 1) + ' 次轮询'); break; } await wait(500); }
  if (!ready) { bad('脚本就绪', 'setPage 未定义 · 内联脚本没跑起来（多半是删出悬空引用）'); return fin(); }
  await evl('new Promise(r=>setTimeout(r,500))', true);

  /* ① 符号与 DOM 归零 */
  const g = await evj(`({tools:typeof TOOLS,cats:typeof TOOL_CATS,plugs:typeof PLUGINS,
    renderTools:typeof renderTools,openTool:typeof openTool,renderPlugins:typeof renderPlugins,
    sec:!!document.querySelector('#p-tools'),det:!!document.querySelector('#p-toolDetail'),
    grid:!!document.querySelector('#toolGrid'),sheet:!!document.querySelector('#sheetPlugin'),
    navHasTools:NAV_MODS.some(m=>m[0]==='p-tools'),
    gridLabels:D.grid.map(x=>x[1]),
    aiTile:D.grid.find(x=>x[1]==='AI 验证'),
    n:D.grid.length})`);
  if (g.__err) bad('符号读取', g.__err);
  else {
    log('符号 ' + JSON.stringify({ tools: g.tools, renderTools: g.renderTools, openTool: g.openTool, n: g.n }));
    (g.tools === 'undefined' && g.cats === 'undefined' && g.plugs === 'undefined') ? ok('TOOLS/TOOL_CATS/PLUGINS 符号归零') : bad('JS 符号残留', JSON.stringify(g));
    (g.renderTools === 'undefined' && g.openTool === 'undefined' && g.renderPlugins === 'undefined') ? ok('renderTools/openTool/renderPlugins 归零') : bad('函数残留', JSON.stringify(g));
    (!g.sec && !g.det && !g.grid && !g.sheet) ? ok('两屏 + 网格容器 + 插件弹层 DOM 归零') : bad('DOM 残留', JSON.stringify(g));
    !g.navHasTools ? ok('底栏栏目池无「工具」') : bad('栏目池残留 p-tools', '');
    g.gridLabels.includes('小工具') ? bad('宫格仍有小工具枚', '') : ok('宫格无小工具枚');
    g.n === 14 ? ok('宫格 14 枚（15 摘 1）') : bad('宫格枚数', g.n);
    (g.aiTile && g.aiTile[2] === 'p-sub-ai') ? ok('AI 验证枚改指 p-sub-ai（不再借道小工具）') : bad('AI 验证枚指向', JSON.stringify(g.aiTile));
  }

  /* ② 底栏设置渲染：无「工具」行 */
  const ns = await evj(`(()=>{navTab('p-profile');
    const t=document.querySelector('#navSetList').textContent;
    return{has:/工具/.test(t),len:t.length}})()`);
  (ns && !ns.has && ns.len > 20) ? ok('底栏设置列表无「工具」栏且已实读 ' + ns.len + ' 字') : bad('底栏设置', JSON.stringify(ns));

  /* ③ AI 验证枚点击 → 落 AI 增强屏 */
  await evj(`(()=>{navTab('p-dashboard');
    const f=l=>[...document.querySelectorAll('#appGrid button')].find(x=>x.textContent.trim().endsWith(l));
    f('AI 验证').click();return{}})()`);
  const ai = await evj(`({cur:curPage,title:(document.querySelector('#pageTitle')||{}).textContent||'',
    body:(document.querySelector('#p-sub-ai')||{textContent:''}).textContent.slice(0,40)})`);
  (ai && ai.cur === 'p-sub-ai' && /AI/.test(ai.title)) ? ok('点 AI 验证 → 落「' + ai.title + '」') : bad('AI 验证落点', JSON.stringify(ai));
  await shot('1-ai-page');

  /* ④ 逐屏走查：栏目池 + 关键屏 setPage 不报错 */
  const pages = ['p-dashboard', 'p-todo', 'p-calendar', 'p-records', 'p-inbox', 'p-finance', 'p-items', 'p-days', 'p-habits', 'p-goals', 'p-care', 'p-profile', 'p-pstore', 'p-sub-ai', 'p-logs'];
  let broken = [];
  for (const p of pages) {
    const r = await evj(`(()=>{setPage('${p}');return{cur:curPage,vis:!document.querySelector('#'+curPage).classList.contains('hidden')}})()`);
    if (!r || r.__err || r.cur !== p || !r.vis) broken.push(p + (r && r.__err ? '(' + r.__err.slice(0, 40) + ')' : ''));
  }
  broken.length === 0 ? ok('逐屏切换 ' + pages.length + ' 屏全部正常') : bad('逐屏切换异常', broken.join(','));

  /* ⑤ 全站文本节点不得再出现「小工具」（逐屏扫，非只当前屏） */
  const leak = await evj(`(()=>{const bad=[];
    for(const p of ${JSON.stringify(pages)}){const e=document.querySelector('#'+p);
      if(e&&/小工具/.test(e.textContent))bad.push(p);}
    return{bad:bad.join(','),n:bad.length}})()`);
  (leak && leak.n === 0) ? ok('逐屏文本零「小工具」泄漏') : bad('文案泄漏', JSON.stringify(leak));

  if (errs.length) bad('运行期错误', errs.slice(0, 4).join(' || ')); else ok('零 console/exception 错误（无悬空引用）');
  fin();
})().catch(e => { bad('未捕获', String(e).slice(0, 200)); fin(); });

function fin() { console.log('== r6check ' + pass + ' PASS / ' + fail + ' FAIL =='); fs.appendFileSync(LOG, '== ' + pass + ' PASS / ' + fail + ' FAIL ==\n'); process.exit(fail ? 1 : 0); }
