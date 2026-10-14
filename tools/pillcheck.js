/* 悬浮胶囊增强批 · 原型无头回归（2026-10-14 · 工单 docs/handoff/悬浮胶囊增强批-20261014.md §5 · 两形态定型）
 * 判什么：展开胶囊（书名截断+时间秒显+两钮不换行）· 拖到边缘折叠成贴边圆圈（只显时长）·
 *         点圆圈直接展开 · 圆圈可拖动换边 · 位置记忆 · C6 已拍板案A（＋笔记直开书摘新建页）·
 *         设置入口行 · 样张总览（两形态样卡＋app 外示意＋权限话术）。
 * 用法：node tools/pillcheck.js（需 Chrome；PAGE ERRORS 必须为 0） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href;
const PORT = Number(process.env.PILL_PORT || 9635);
let pass = 0, fail = 0; const errs = [];
const log = m => console.log(m);
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(m, p) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method: m, params: p || {} })) }) }
async function ev(x) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + x + '})())' });
  const r = m.result && m.result.result;
  try { return JSON.parse(r && r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 240) } }
}

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  const child = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.pill-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  if (!data) { bad('chrome 起服'); return finish() }
  ws = new WebSocket(data.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 200)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF });
  /* 轮询页面就绪（head 里有阻塞式 CDN 引用，冷启动/清过 profile 时固定等待会读到空 body） */
  let ready = false;
  for (let i = 0; i < 60; i++) {
    const s = await ev(`return {rs:document.readyState,nav:typeof navTo,pill:typeof pillFabify,bl:document.body?document.body.innerHTML.length:0}`);
    if (s && s.rs === 'complete' && s.nav === 'function' && s.pill === 'function' && (s.bl || 0) > 10000) { ready = true; break }
    await wait(500);
  }
  if (!ready) { bad('页面就绪（readyState/全局函数/body）超时'); return finish() }
  await wait(400);

  /* P1 设置入口行 + 样张总览：两形态样卡 / app 外示意 / 权限话术 / C6 已拍板案A / 影音同构注 */
  const p1 = await ev(`navTo('p-readset');rsSetTab=3;renderReadSet();
    var t=document.getElementById('p-readset').innerText;
    var hasEntry=/胶囊交互样张/.test(t);
    openSheet('sheetPillDemo');var d=document.getElementById('sheetPillDemo').innerText;
    return {entry:hasEntry,open:document.getElementById('sheetPillDemo').classList.contains('sheet-open'),
      forms:/紧凑胶囊（默认）/.test(d)&&/展开（点时间）/.test(d)&&/贴边圆圈/.test(d)&&/两形态严格互斥/.test(d),
      ext:/APP 外系统悬浮窗/.test(d)&&/SYSTEM_ALERT_WINDOW/.test(d),
      permit:/权限引导话术/.test(d)&&/显示在其他应用上层/.test(d)&&/不读取/.test(d),
      c6:/已拍板＝案A 复用记书摘/.test(d)&&/案B（就地输入框）作废/.test(d),
      media:/同构继承/.test(d)&&/C6 仅阅读侧/.test(d),
      kv:/read\\.pillPos/.test(d),noEmoji:(function(){var EM=[/[\\u{1F000}-\\u{1FAFF}]/u,/['\\u{2600}-\\u{27BF}']/u];return !EM.some(function(r){return r.test(d)})})()};`);
  (p1.entry && p1.open && p1.forms && p1.ext && p1.permit && p1.c6 && p1.media && p1.kv && p1.noEmoji)
    ? ok('P1 设置入口行在位 · 样张总览（两形态样卡＋app 外示意＋权限话术＋C6 已拍板案A＋影音同构注＋kv 位置记忆）· 零 emoji')
    : bad('P1', JSON.stringify(p1));

  /* P2 展开胶囊：默认紧凑不显书名 → 点时间才显/隐；时间秒显（m:ss→h:mm:ss 等宽）；两钮不换行；配色＝中性浮层 */
  const p2 = await ev(`closeSheet('sheetPillDemo');
    var f1=fmtPillSec(754),f2=fmtPillSec(3725),f3=fmtPillSec(3599);
    var b0=bsIng()[0]||BS_BOOKS[0];window.PILL_TGT='《'+b0.n+'》';timerTap('read',PILL_TGT);var tb=document.getElementById('timerBar');
    var lbl=document.getElementById('timerLabel');
    var compact=lbl.classList.contains('hidden');
    pillLabelToggle();var shown=!lbl.classList.contains('hidden')&&lbl.textContent.indexOf(b0.n)>=0;
    pillLabelToggle();var back=lbl.classList.contains('hidden');
    var btns=[].every.call(tb.querySelectorAll('button'),function(b){return getComputedStyle(b).whiteSpace==='nowrap'});
    return {f1:f1,f2:f2,f3:f3,vis:!tb.classList.contains('hidden'),compact:compact,shown:shown,back:back,
      lblTrunc:lbl.classList.contains('truncate'),btns:btns,
      barMax:/max-w-\\[calc\\(100%-24px\\)\\]/.test(tb.className),
      pal:/bg-white\\/95/.test(tb.className)&&/dark:bg-slate-900\\/90/.test(tb.className)&&/border-slate-200\\/80/.test(tb.className),
      sec:/^\\d{1,2}:\\d{2}$/.test(document.getElementById('timerSec').textContent),
      mono:document.getElementById('timerSec').classList.contains('font-mono')};`);
  (p2.f1 === '12:34' && p2.f2 === '1:02:05' && p2.f3 === '59:59' && p2.vis && p2.compact && p2.shown && p2.back
    && p2.lblTrunc && p2.btns && p2.barMax && p2.pal && p2.sec && p2.mono)
    ? ok('P2 默认紧凑（不显书名）· 点时间显/隐 · 书名 truncate · 两钮 nowrap · 中性浮层配色 · 秒显等宽', p2.f1 + ' / ' + p2.f2)
    : bad('P2', JSON.stringify(p2));

  /* P3 两形态互斥：拖到边缘 → 贴边圆圈（只显时长·胶囊藏）· 左右两向吸附 · 圆圈同配色 */
  const p3 = await ev(`var tb=document.getElementById('timerBar'),f=document.getElementById('pillFab');
    function vis(){var n=0;if(!tb.classList.contains('hidden'))n++;if(!f.classList.contains('hidden'))n++;return n}
    var fns=[pillDragStart,pillFabDragStart,pillFabify,pillFabExpand,pillShow].every(function(x){return typeof x==='function'});
    pillFabify('l');var a={barH:tb.classList.contains('hidden'),fab:!f.classList.contains('hidden'),
      sec:/^\\d{1,2}:\\d{2}$/.test(document.getElementById('pillFabSec').textContent),
      atL:f.style.left==='4px',pos:!!pillPos,only:vis()};
    pillFabify('r');var atR=f.style.right==='4px'&&f.style.left==='auto',onlyR=vis();
    var pal=/bg-white\\/95/.test(f.className)&&/border-slate-200\\/80/.test(f.className);
    pillFabify('l');
    return {fns:fns,a:a,atR:atR,onlyR:onlyR,pal:pal};`);
  (p3.fns && p3.a.barH && p3.a.fab && p3.a.sec && p3.a.atL && p3.a.pos && p3.a.only === 1 && p3.atR && p3.onlyR === 1 && p3.pal)
    ? ok('P3 边缘松手 → 贴边圆圈（只显时长·胶囊藏）· 左右两向吸附 · 任意时刻仅一态可见 · 圆圈同配色') : bad('P3', JSON.stringify(p3));

  /* P4 点圆圈 → 展开胶囊：圆圈藏、胶囊整条落在视口内（实伤：曾左端跑出屏外） */
  const p4 = await ev(`var tb=document.getElementById('timerBar'),f=document.getElementById('pillFab');
    function vis(){var n=0;if(!tb.classList.contains('hidden'))n++;if(!f.classList.contains('hidden'))n++;return n}
    pillFabExpand();var r=tb.getBoundingClientRect();
    return {fabH:f.classList.contains('hidden'),tb:!tb.classList.contains('hidden'),only:vis(),
      inView:r.left>=0&&r.right<=innerWidth+0.5&&r.top>=0,
      left:Math.round(r.left),right:Math.round(r.right),vw:innerWidth,
      timerAlive:!!timer,draggedGuard:typeof _pillDragged!=='undefined'};`);
  (p4.fabH && p4.tb && p4.only === 1 && p4.inView && p4.timerAlive && p4.draggedGuard)
    ? ok('P4 点圆圈 → 胶囊展开且整条在屏内（left ' + p4.left + '~' + p4.right + ' / vw ' + p4.vw + '）· 两态互斥') : bad('P4', JSON.stringify(p4));

  /* P5 C6 已拍板案A：＋笔记直开书摘新建页（预选在读书），无两案弹层 */
  const p5 = await ev(`var gone=!document.getElementById('sheetPillNote');
    pillNoteA();
    return {gone:gone,page:curPage,title:document.getElementById('pageTitle').textContent};`);
  (p5.gone && p5.page === 'p-quoteEdit' && /新增摘录/.test(p5.title))
    ? ok('P5 C6 案A 落地：＋笔记直开书摘新建页（预选在读书）· 两案演示弹层已摘', String(p5.title).slice(0, 40))
    : bad('P5', JSON.stringify(p5));

  /* P6 收尾干净：结束计时后胶囊与圆圈零残留 */
  const p6 = await ev(`pillFabify('l');stopTimerUI();
    return {tbH:document.getElementById('timerBar').classList.contains('hidden'),
      fabH:document.getElementById('pillFab').classList.contains('hidden')};`);
  (p6.tbH && p6.fabH) ? ok('P6 结束计时后胶囊与圆圈态零残留') : bad('P6', JSON.stringify(p6));

  finish();
})().catch(e => { bad('harness 崩溃 ' + String(e).slice(0, 200)); finish() });
function finish() { log((fail ? 'RESULT FAIL ' : 'RESULT PASS ') + pass + '/' + (pass + fail));
  if (errs.length) { log('PAGE ERRORS ' + errs.length + ': ' + errs.join(' || ')); fail = 1 }
  else log('PAGE ERRORS 0');
  try { if (ws) ws.close() } catch (e) { }
  process.exit(fail ? 1 : 0) }
