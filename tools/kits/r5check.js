/* 反馈轮5 共享面原型回归校验 · CDP 无头
 * 断言：宫格枚数/日记笔记摘除/阅读带段名点击落记录阅读视图/我的页无小工具入口行
 * 用法：node --experimental-websocket tools/kits/r5check.js */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.R5_PORT || 9531);
const SHOTS = process.argv.includes('--shots');
const SHOTDIR = 'prototype/shots/r5';
const LOG = 'tools/kits/r5-run.log';
let pass = 0, fail = 0;
const log = m => { fs.appendFileSync(LOG, m + '\n'); console.log(m); };
fs.writeFileSync(LOG, '== r5check start ' + new Date().toISOString() + ' ==\n');
function ok(n, i) { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')); }
function bad(n, i) { fail++; log('FAIL ' + n + '  →  ' + (i || '')); }
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)); }).on('error', () => res(null)); } catch (e) { res(null); } }); }

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在', CHROME); return fin(); }
  if (SHOTS) fs.mkdirSync(SHOTDIR, { recursive: true });
  log('launch chrome · port ' + PORT);
  spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/kits/.chrome-r5'), '--disable-extensions',
    '--no-default-browser-check', '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); break; } catch (e) { } } await wait(300); }
  if (!data || !data.length) { bad('CDP 启动', '端口无响应（换 R5_PORT 重试）'); return fin(); }
  /* 必须挑 type==='page' 的目标：新 profile 会带扩展 background_page，data[0] 未必是页面 */
  const pageTarget = data.find(t => t.type === 'page' && /about:blank|^$/.test(t.url)) || data.find(t => t.type === 'page');
  if (!pageTarget) { bad('CDP 目标', '无 page 目标：' + data.map(t => t.type).join(',')); return fin(); }
  const ws = new WebSocket(pageTarget.webSocketDebuggerUrl);
  let idc = 0; const pend = new Map(); const errs = [];
  ws.addEventListener('message', ev => { const m = JSON.parse(ev.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || JSON.stringify(m.params.exceptionDetails)).slice(0, 240));
    if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') errs.push(String((m.params.args[0] || {}).value || '').slice(0, 160)); });
  const send = (m, p = {}) => new Promise(r => { const id = ++idc; pend.set(id, r); ws.send(JSON.stringify({ id, method: m, params: p })); });
  const evl = (expr, aw) => send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: !!aw })
    .then(r => r.result && r.result.exceptionDetails
      ? { __err: [r.result.exceptionDetails.text, (r.result.exceptionDetails.exception || {}).description || (r.result.exceptionDetails.exception || {}).value].filter(Boolean).join(' | ').slice(0, 200) }
      : (r.result && r.result.result ? r.result.result.value : undefined));
  await new Promise(r => ws.addEventListener('open', r));
  await send('Runtime.enable'); await send('Page.enable');
  await send('Page.navigate', { url: URLF });
  await wait(1500);
  await evl('localStorage.clear();1');
  await send('Page.navigate', { url: URLF }); await wait(900);
  let ready = false;
  for (let i = 0; i < 40; i++) { if ((await evl('typeof setPage')) === 'function') { ready = true; log('脚本就绪 · 第 ' + (i + 1) + ' 次轮询'); break; } await wait(500); }
  if (!ready) { bad('脚本就绪', 'setPage 未定义 · 内联脚本没跑起来'); return fin(); }
  await evl('new Promise(r=>setTimeout(r,400))', true);

  /* 截图归档（--shots）：三张取证图落 prototype/shots/r5 */
  const shot = async name => {
    if (!SHOTS) return;
    await evl('new Promise(r=>setTimeout(r,350))', true);
    const s = await send('Page.captureScreenshot', { format: 'png' });
    if (s.result && s.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(s.result.data, 'base64'));
  };

  /* ① 数据面：宫格枚数与条目 */
  const g = await evl(`(()=>{const l=D.grid;return{n:l.length,
    labels:l.map(x=>x[1]),seg:l.filter(x=>x[3]).map(x=>x[1]+':'+x[2]+':'+x[3]),
    book:l.find(x=>x[1]==='阅读')||null}})()`);
  if (g && g.__err) bad('D.grid 读取', g.__err);
  else {
    log('D.grid ' + JSON.stringify(g));
    g.n === 15 ? ok('宫格 15 枚（原 17 摘除日记/笔记）') : bad('宫格枚数', g.n);
    !g.labels.includes('日记') && !g.labels.includes('笔记') ? ok('日记/笔记已从宫格下架') : bad('宫格残留日记/笔记', g.labels.join(','));
    (g.book && g.book[2] === 'p-records' && g.book[3] === 'book') ? ok('阅读枚带段名 book') : bad('阅读枚段名', JSON.stringify(g.book));
    g.seg.length === 1 ? ok('仅阅读一枚带段切换') : bad('带段枚数', g.seg.join('|'));
  }

  /* ② 渲染面：主页网格 DOM */
  const d = await evl(`(()=>{navTab('p-dashboard');
    const b=[...document.querySelectorAll('#appGrid button')];
    return{btns:b.length,texts:b.map(x=>x.textContent.trim())}})()`);
  if (d && d.__err) bad('宫格 DOM', d.__err);
  else {
    d.btns === 15 ? ok('#appGrid 渲染 15 枚') : bad('#appGrid 枚数', d.btns);
    !d.texts.some(t => t.includes('日记') || t.includes('笔记')) ? ok('DOM 无日记/笔记瓦片') : bad('DOM 残留', d.texts.filter(t => t.includes('日记') || t.includes('笔记')).join(','));
  }
  await evl('(()=>{const e=document.querySelector("#appGrid");if(e)e.scrollIntoView({block:"center"});return 1})()');
  await shot('1-dashboard-grid');

  /* 探针统一走页内 JSON.stringify：绕开 CDP 按值序列化把整包丢成 {} 的坑 */
  const evj = async expr => {
    const r = await evl('(()=>{try{return JSON.stringify(' + expr + ')}catch(e){return JSON.stringify({__thunk:String(e&&e.message||e)})}})()');
    if (!r || r.__err) return { __err: (r && r.__err) || 'empty' };
    try { return JSON.parse(r); } catch (e) { return { __err: 'parse:' + String(r).slice(0, 120) }; }
  };

  /* ③ 交互面：点「阅读」→ 记录页阅读视图 */
  const c = await evj(`(()=>{
    const f=l=>[...document.querySelectorAll('#appGrid button')].find(x=>x.textContent.trim().endsWith(l));
    const b=f('阅读');
    if(!b)return{__no:'btn',all:[...document.querySelectorAll('#appGrid button')].map(x=>x.textContent.trim()).join(',')};
    b.click();
    return{cur:curPage,rec:recTab,title:(document.querySelector('#pageTitle')||{}).textContent||'',
      stack:stack.length,navActive:[...document.querySelectorAll('#navBar button.on')].map(x=>x.textContent.trim()),
      bookShown:!!document.querySelector('#recBook')&&!document.querySelector('#recBook').classList.contains('hidden'),
      diaryShown:!!document.querySelector('#recDiary')&&!document.querySelector('#recDiary').classList.contains('hidden')}})()`);
  if (c && c.__err) bad('点阅读', c.__err);
  else {
    log('点阅读 → ' + JSON.stringify(c));
    c.cur === 'p-records' ? ok('落位 p-records') : bad('落位页面', c.cur || c.__no);
    c.rec === 'book' ? ok('recTab=book') : bad('recTab', c.rec);
    c.title === '记录 · 阅读' ? ok('标题「记录 · 阅读」') : bad('标题', c.title);
    c.bookShown && !c.diaryShown ? ok('仅阅读视图可见') : bad('视图可见性', JSON.stringify({ book: c.bookShown, diary: c.diaryShown }));
    (c.navActive || []).includes('记录') ? ok('底栏「记录」高亮') : bad('底栏高亮', (c.navActive || []).join(','));
  }
  await shot('2-records-book');

  /* ④ 回落面：切走再回来不残留 */
  const back = await evj(`(()=>{switchRecord('diary');
    return{rec:recTab,title:(document.querySelector('#pageTitle')||{}).textContent||''}})()`);
  (back && back.rec === 'diary' && back.title === '记录 · 日记') ? ok('段内切换仍正常') : bad('段内切换', JSON.stringify(back));

  /* ⑤ 我的页：小工具合集入口行已摘 */
  const p = await evj(`(()=>{navTab('p-profile');
    const el=document.querySelector('#p-profile');
    return{txt:el?el.textContent:'',len:el?el.textContent.length:0,
      toNav:[...document.querySelectorAll('#p-profile button')].filter(b=>/navTo\('p-tools'\)/.test(b.getAttribute('onclick')||'')).length}})()`);
  if (p && p.__err) bad('我的页读取', p.__err);
  else {
    p.len > 200 ? ok('我的页文本已实读 ' + p.len + ' 字') : bad('我的页读取为空', p.len);
    !p.txt.includes('小工具合集') ? ok('我的页无「小工具合集」入口行') : bad('我的页残留入口行', '');
    p.toNav === 0 ? ok('我的页无 navTo(p-tools) 入口按钮') : bad('我的页仍有 p-tools 跳转', p.toNav);
    /底栏|导航/.test(p.txt) ? ok('我的页其余内容完好（底栏设置仍在）') : bad('我的页内容缺失', p.len);
  }
  await shot('3-profile-no-kits-row');

  /* ⑥ 其余宫格点击行为回归（未带段名的枚数走原机制）
   * 一次 eval 里连点两枚会把整包结果吞掉（CDP 返回空 result），拆成点/读两步 */
  await evl(`(()=>{navTab('p-dashboard');
    const f=l=>[...document.querySelectorAll('#appGrid button')].find(x=>x.textContent.trim().endsWith(l));
    f('待办').click();})()`);
  const t1 = await evl('String(curPage)');
  await evl(`(()=>{navTab('p-dashboard');
    const f=l=>[...document.querySelectorAll('#appGrid button')].find(x=>x.textContent.trim().endsWith(l));
    f('小工具').click();})()`);
  const k1 = await evl('String(curPage)');
  (t1 === 'p-todo' && k1 === 'p-tools') ? ok('其余瓦片跳转未受影响（待办/小工具）') : bad('其余瓦片', t1 + ' / ' + k1);

  if (errs.length) bad('运行期错误', errs.slice(0, 3).join(' || ')); else ok('零 console/exception 错误');
  fin();
})().catch(e => { bad('未捕获', String(e).slice(0, 200)); fin(); });

function fin() { console.log('== r5check ' + pass + ' PASS / ' + fail + ' FAIL =='); fs.appendFileSync(LOG, '== ' + pass + ' PASS / ' + fail + ' FAIL ==\n'); process.exit(fail ? 1 : 0); }
