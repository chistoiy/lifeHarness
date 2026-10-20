/* UX 审计真机批 · U4＋U10 原型门回归（2026-10-06）
 * U4＝阅读热力图默认视口不再停 1 月（当年贴最近有数据的周／按月贴该月首列／往年贴首个有数据列）＋卡内月份刻度
 * U10＝壳层「底部导航栏自定义」固定栏目出锁定态，不再画成「可关」
 * 用法：node --experimental-websocket tools/u410check.js（截图：U410_SHOTS=1，落仓库外 tempWork） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.U410_PORT || 9581);
const SHOTS = process.env.U410_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/u410-shots';
const SHELF = url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href;
const SHELL = url.pathToFileURL(path.resolve('prototype/index.html')).href;
let pass = 0, fail = 0; const errs = [];
let child = null;
const log = m => console.log(m);
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
async function shot(name) { if (!SHOTS) return; fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }
async function open(u) { await cmd('Page.navigate', { url: u }); await wait(2600) }

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  child = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.u410-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  if (!data) { bad('chrome 起服'); return finish() }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 260)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');

  /* ================= U4：书架专版 · 阅读统计热力图 ================= */
  await open(SHELF);
  const u4 = await ev(`setPage('p-readstat');
    var hw=document.getElementById('rsHeatWrap'),inner=document.querySelector('.rs-hm-in');
    var cells=document.querySelectorAll('#rsHeat i'),L=rsLog(rsYearCur),last=-1;
    L.forEach(function(d,i){if(rsVal(d)>0)last=i});
    var r=cells[Math.max(0,last)].getBoundingClientRect(),h=hw.getBoundingClientRect();
    var lab=[].map.call(document.querySelectorAll('#rsHeatMonths b'),function(b){return {t:b.textContent.trim(),l:b.offsetLeft,w:b.offsetWidth}});
    var align=[0,1,2,3,4,5,6,7,8,9,10,11].map(function(m){var c=Math.floor(m*30/7);var i2=cells[c*7];
      return Math.abs(lab[m].l-(i2.getBoundingClientRect().left-inner.getBoundingClientRect().left))});
    var gaps=lab.slice(1).map(function(x,i2){return x.l-(lab[i2].l+lab[i2].w)});
    return {cols:cells.length,sl:Math.round(hw.scrollLeft),sw:Math.round(hw.scrollWidth),cw:Math.round(hw.clientWidth),
      last:last,lastCol:Math.floor(last/7),visEnd:Math.round(h.right),cellRight:Math.round(r.right),cellLeft:Math.round(r.left),boxLeft:Math.round(h.left),
      n:lab.length,ls:lab.map(function(x){return x.l}).join(','),alignMax:Math.max.apply(null,align),
      gapMin:Math.min.apply(null,gaps),txt:document.getElementById('rsHeatMonths').textContent.replace(/\\s+/g,' ').trim()};`);
  if (u4.__err) bad('U4 读数', JSON.stringify(u4));
  else {
    (u4.n === 12) ? ok('U4 月份刻度 12 枚在册') : bad('U4 刻度枚数', JSON.stringify(u4));
    (u4.ls.split(',').map(Number).every((v, i, a) => i === 0 || v > a[i - 1]) && Number(u4.ls.split(',')[0]) === 0)
      ? ok('U4 刻度自左向右递增且首枚贴 0（1 月）') : bad('U4 刻度序', u4.ls);
    (u4.alignMax <= 3) ? ok('U4 刻度与热力列同节距对齐（偏差 ≤3px）') : bad('U4 刻度对齐', 'max=' + u4.alignMax);
    (u4.gapMin >= 2) ? ok('U4 刻度互不重叠（最小间隙 ' + u4.gapMin + 'px）') : bad('U4 刻度重叠', 'gapMin=' + u4.gapMin);
    (u4.sl > 0) ? ok('U4 进屏即离开 1 月（scrollLeft=' + u4.sl + '／总宽 ' + u4.sw + '）') : bad('U4 默认视口', JSON.stringify(u4));
    (u4.cellLeft >= u4.boxLeft - 1 && u4.cellRight <= u4.visEnd + 1)
      ? ok('U4 最后一个有数据的周落在可视区内（第 ' + u4.lastCol + ' 列）') : bad('U4 数据列不可见', JSON.stringify(u4));
    await ev(`var c=document.getElementById('rsHeatWrap');var pg=document.getElementById('p-readstat');
      pg.scrollTop=c.getBoundingClientRect().top-pg.getBoundingClientRect().top+pg.scrollTop-70;return 1;`);
    await wait(500);
    await shot('u4-01-heat-default');
    await ev(`document.getElementById('rsHeatWrap').scrollLeft=0;return 1;`);
    await wait(300);
    await shot('u4-01b-heat-january');
    await ev(`document.getElementById('rsHeatWrap').scrollLeft=${u4.sl};return 1;`);
  }
  const u4m = await ev(`rsMonth=0;rsPickM(10);
    var hw=document.getElementById('rsHeatWrap'),cells=document.querySelectorAll('#rsHeat i');
    var col=Math.floor((10-1)*30/7),c=cells[col*7];
    var r=c.getBoundingClientRect(),h=hw.getBoundingClientRect();
    var o={sl:Math.round(hw.scrollLeft),cw:Math.round(hw.clientWidth),sw:Math.round(hw.scrollWidth),full:Math.round(hw.scrollWidth-hw.clientWidth),
      col:col,ideal:col*16,rel:Math.round(r.left-h.left),inView:(r.left>=h.left-1&&r.left<=h.right-1),
      txt:document.getElementById('rsHeatMonths').textContent.trim()};
    rsPickM(0);return o;`);
  const mOk = !u4m.__err && /^10 月$/.test(u4m.txt) && (u4m.ideal < u4m.full ? Math.abs(u4m.rel) <= 20 : u4m.inView);
  mOk ? ok('U4 按月筛选＝单枚该月刻度贴首列，首列进视口', JSON.stringify(u4m)) : bad('U4 按月定位', JSON.stringify(u4m));
  const u4y = await ev(`rsYearCur=2023;renderReadStat();
    var hw=document.getElementById('rsHeatWrap'),cells=document.querySelectorAll('#rsHeat i'),L=rsLog(2023),f=-1;
    for(var i=0;i<L.length;i++){if(rsVal(L[i])>0){f=i;break}}
    var col=Math.floor((f<0?0:f)/7),r=cells[col*7].getBoundingClientRect(),h=hw.getBoundingClientRect();
    var o={sl:Math.round(hw.scrollLeft),full:Math.round(hw.scrollWidth-hw.clientWidth),first:f,col:col,ideal:col*16,
      rel:Math.round(r.left-h.left),jan:Math.round(cells[0].getBoundingClientRect().left-h.left)};
    rsPickY(BS_CUR_YEAR);return o;`);
  const yOk = !u4y.__err && (u4y.ideal >= u4y.full ? u4y.sl === u4y.full : Math.abs(u4y.sl - u4y.ideal) <= 2);
  yOk ? ok('U4 往年＝视口左缘贴该年第一个有数据的列（第 ' + u4y.col + ' 列）', JSON.stringify(u4y))
    : bad('U4 往年定位', JSON.stringify(u4y));

  /* ================= U10：壳层 · 底部导航栏自定义 ================= */
  await open(SHELL);
  const u10 = await ev(`setPage('p-profile');renderNavSet();
    var rows=[].slice.call(document.querySelectorAll('#navSetList>div'));
    var locked=rows.filter(function(r){return r.querySelector('.toggle.lock')});
    var free=rows.filter(function(r){return r.querySelector('.toggle:not(.lock)')});
    var cs=locked.map(function(r){var t=r.querySelector('.toggle');var s=getComputedStyle(t);
      return {op:Number(s.opacity),pe:s.pointerEvents,on:/\\bon\\b/.test(t.className),oc:!!t.onclick,
        lab:r.querySelector('.setnav').textContent.replace(/\\s+/g,' ').trim()}});
    return {n:rows.length,lockN:locked.length,freeN:free.length,cs:cs,
      cntBefore:document.getElementById('navCount').textContent,
      tabsBefore:activeTabs.join('|')};`);
  if (u10.__err) bad('U10 读数', JSON.stringify(u10));
  else {
    (u10.lockN === 2 && u10.freeN === 11) ? ok('U10 两枚固定＝锁定态，其余 11 枚仍可切') : bad('U10 锁定枚数', JSON.stringify(u10));
    (u10.cs.every(x => x.on && !x.oc && x.pe === 'none' && x.op < 1))
      ? ok('U10 锁定开关＝常开＋无点击＋置灰（opacity ' + u10.cs[0].op + '）') : bad('U10 锁定形态', JSON.stringify(u10.cs));
    (/今天/.test(u10.cs[0].lab) && /我的/.test(u10.cs[1].lab))
      ? ok('U10 固定两枚＝今天／我的（带「固定」标）', u10.cs.map(x => x.lab).join(' · ')) : bad('U10 固定项归属', JSON.stringify(u10.cs.map(x => x.lab)));
    await ev(`var c=document.getElementById('navSetList');var pg=document.getElementById('p-profile');
      pg.scrollTop=c.getBoundingClientRect().top-pg.getBoundingClientRect().top+pg.scrollTop-90;return 1;`);
    await shot('u4-02-nav-fixed');
  }
  const u10b = await ev(`var t=document.querySelector('#navSetList>div:nth-child(1) .toggle');t.click();
    return {tabs:activeTabs.join('|'),cnt:document.getElementById('navCount').textContent,toast:$('#toast').textContent};`);
  (u10b.tabs !== u10.tabsBefore || u10b.cnt !== u10.cntBefore) ? bad('U10 点锁定开关竟改状态', JSON.stringify(u10b))
    : ok('U10 点锁定开关无反应（已启用仍 ' + u10b.cnt + '/5，无提示条）');
  const u10c = await ev(`var r=[].slice.call(document.querySelectorAll('#navSetList>div')).filter(function(x){return /待办/.test(x.querySelector('.setnav').textContent)})[0];
    var t=r.querySelector('.toggle');t.click();var a={n:document.getElementById('navCount').textContent,off:!t.classList.contains('on')};
    r=document.querySelectorAll('#navSetList>div');
    var r2=[].slice.call(r).filter(function(x){return /待办/.test(x.querySelector('.setnav').textContent)})[0];
    r2.querySelector('.toggle').click();
    return {off:a.n,on:document.getElementById('navCount').textContent,tabs:activeTabs.join('|')};`);
  (u10c.off !== '4' || u10c.on !== '5') ? bad('U10 非固定项可切回归', JSON.stringify(u10c))
    : ok('U10 非固定项仍可开可关（待办 5→4→5）');

  finish();
})().catch(e => { bad('harness 崩溃 ' + String(e).slice(0, 200)); finish() });
function finish() { log((fail ? 'RESULT FAIL ' : 'RESULT PASS ') + pass + '/' + (pass + fail));
  if (errs.length) { log('PAGE ERRORS ' + errs.length + ': ' + errs.join(' || ')); fail = 1 }
  else log('PAGE ERRORS 0');
  log('U4/U10 断言：' + pass + ' 绿 / ' + fail + ' 红');
  try { if (ws) ws.close() } catch (e) { }
  try { if (child) child.kill() } catch (e) { }
  setTimeout(() => process.exit(fail ? 1 : 0), 400) }
