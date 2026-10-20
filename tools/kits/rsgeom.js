/* 量具：尺子全屏舞台与紧凑网格的真实几何（截图缩放会骗人，这里只认像素矩形）
 * 用法：node --experimental-websocket tools/kits/rsgeom.js */
const { spawn } = require('child_process');
const path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF = url.pathToFileURL(path.resolve('prototype/index-kits.html')).href;
const PORT = Number(process.env.RS_PORT || 9437);
const wait = ms => new Promise(r => setTimeout(r, ms));
const get = u => new Promise(res => { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) });
(async () => {
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/kits/.chrome-rsgeom'), '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 40; i++) { data = await get(`http://127.0.0.1:${PORT}/json/version`); if (data) break; await wait(250); }
  const ws = new WebSocket(JSON.parse(data).webSocketDebuggerUrl);
  let id = 0; const pending = new Map();
  const send = (m, p, s) => new Promise((res, rej) => { const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method: m, params: p, sessionId: s })); });
  ws.onmessage = ev => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { const q = pending.get(m.id); pending.delete(m.id); m.error ? q.rej(new Error(JSON.stringify(m.error))) : q.res(m.result); } };
  await new Promise(r => ws.onopen = r);
  const { targetId } = await send('Target.createTarget', { url: URLF + '#p-tools' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  await wait(1800);
  const evl = expr => send('Runtime.evaluate', { expression: '(async()=>{const sleep=ms=>new Promise(r=>setTimeout(r,ms));' + expr + '})()', returnByValue: true, awaitPromise: true }, sessionId)
    .then(r => r.exceptionDetails ? 'EXC ' + JSON.stringify(r.exceptionDetails.exception && r.exceptionDetails.exception.description) : r.result.value);
  console.log('— 工具网格 —');
  console.log(JSON.stringify(await evl(`
    var g=document.querySelector('#toolGrid .grid'),gr=getComputedStyle(g);
    var t=[...g.querySelectorAll('.kit-tile')].slice(0,5).map(x=>{var r=x.getBoundingClientRect();return {x:Math.round(r.left),y:Math.round(r.top),w:Math.round(r.width),h:Math.round(r.height)}});
    return {phoneW:Math.round(document.getElementById('phone').getBoundingClientRect().width),
      cols:gr.gridTemplateColumns.split(' ').length,tpl:gr.gridTemplateColumns,gap:gr.columnGap,tiles:t[0].w+'x'+t[0].h,firstRowXs:t.map(a=>a.x).join(','),gridW:Math.round(g.getBoundingClientRect().width),parentW:Math.round(g.parentElement.getBoundingClientRect().width),cls:g.className,minW:getComputedStyle(g.querySelector('.kit-tile')).minWidth,btnDisp:getComputedStyle(g.querySelector('.kit-tile')).display,
      tileCount:document.querySelectorAll('#toolGrid .kit-tile').length,
      real:(function(){var t=document.querySelector('#toolGrid .kit-tile');var p=t.parentElement;var cs=getComputedStyle(p);return {cls:p.className,tpl:cs.gridTemplateColumns,w:Math.round(p.getBoundingClientRect().width),disp:cs.display,gap:cs.columnGap}})(),
      sec:(function(){var e=document.querySelector('#toolGrid');var cs=getComputedStyle(e);return {cls:e.className,w:Math.round(e.getBoundingClientRect().width),disp:cs.display,tpl:cs.gridTemplateColumns}})(),
      perRow:(function(){return [...document.querySelectorAll('#toolGrid .grid')].map(function(g){var t=[...g.children].map(x=>x.getBoundingClientRect());var y=t[0].top;return g.previousElementSibling.innerText.split('
')[0]+':'+t.filter(r=>Math.abs(r.top-y)<2).length+'/'+t.length+'@w'+Math.round(t[0].width)}).join(' | ')})(),
      dbg:(function(){var g=document.querySelector('#toolGrid .grid');var r=g.getBoundingClientRect();var c0=g.children[0].getBoundingClientRect(),c1=g.children[1].getBoundingClientRect();var p=g.parentElement,pr=p.getBoundingClientRect();var cs=getComputedStyle(g);return {gridRect:[Math.round(r.left),Math.round(r.top),Math.round(r.width)],parentTag:p.tagName+':'+p.className.slice(0,20),parentRect:[Math.round(pr.left),Math.round(pr.width)],c0:[Math.round(c0.left),Math.round(c0.top),Math.round(c0.width)],c1:[Math.round(c1.left),Math.round(c1.top),Math.round(c1.width)],boxSizing:cs.boxSizing,autoFlow:cs.gridAutoFlow,innerW:innerWidth}})(),
      xs:(function(){var g=document.querySelector('#toolGrid .grid');return [...g.children].slice(0,6).map(x=>{var r=x.getBoundingClientRect();return x.className.slice(0,8)+'@'+Math.round(r.left)+'/'+Math.round(r.width)})})(),
      secW:Math.round(document.querySelector('#p-tools section, #p-tools').getBoundingClientRect().width)}`), null, 1));
  console.log('— 尺子舞台 —');
  console.log(JSON.stringify(await evl(`
    openTool('ruler');await sleep(300);
    var q=id=>{var e=document.getElementById(id);var r=e.getBoundingClientRect();return {y:Math.round(r.top),h:Math.round(r.height),txt:(e.innerText||'').replace(/\\s+/g,' ').slice(0,40)}};
    return {tape:q('rsTape'),read:q('rsRead'),tip:q('rsGuideTip'),guide:q('rsGuide'),ctl:q('rsCtl'),
      span:q('rulerSpan'),zero:q('rsZeroPos'),big:q('rsBig')}`), null, 1));
  ws.close(); chrome.kill(); process.exit(0);
})().catch(e => { console.log('FAIL ' + e.message); process.exit(1); });
