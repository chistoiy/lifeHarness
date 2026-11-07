/* 「我的」页一级屏 · 分组结构原型门（批B · 2026-10-11）
 *
 * 断言：① 4 枚分组标题在册且文案正确
 *      ② 屏内元素顺序＝期望序列（标题/行/关于卡交错位置全对）
 *      ③ 8 枚二级入口一枚不少
 *      ④ 每组首行无 border-t（组首上方不留分隔线）
 *      ⑤ 关于卡仍在页尾
 * 截图：浅/深 × 整页（CDP setDeviceMetricsOverride 出真 390 视口；
 *      prefers-color-scheme 显式钉——本机 headless 缺省是 dark，不钉会全截成深色）。
 * 用法：node tools/profilecheck.js            # 断言
 *      PC_SHOTS=1 node tools/profilecheck.js  # 断言 + 出图到 prototype/shots/profile-group/
 * 变异自证：摘掉任一 LABEL / 把某行搬到别组 / 给组首行加回 border-t ⇒ ①②④ 各红其位。
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.PC_PORT || 9621);
const SHOTS = process.env.PC_SHOTS === '1';
const SHOTDIR = path.resolve('prototype/shots/profile-group');
const SHELL = 'file:///' + path.resolve('prototype/index.html').replace(/\\/g, '/');
let pass = 0, fail = 0; const errs = [];
let child = null, ws, idc = 0; const pend = new Map();
const ok = (n, i) => { pass++; console.log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; console.log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
function cmd(method, params) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })) }) }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result;
  try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 240) } }
}
async function shot(name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
  if (m.result && m.result.data) {
    fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64'));
    console.log('SHOT ' + name + '.png');
  }
}
async function emulate(mode) {
  await cmd('Emulation.setEmulatedMedia', { media: '', features: [{ name: 'prefers-color-scheme', value: mode }] });
  await wait(360);
}
async function setViewport(w, h) {
  await cmd('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 2, mobile: true });
  await wait(260);
}

/* 屏内元素序列：标题 T: / 入口行 R: / 关于卡 ABOUT */
const READ = `
  var sec=document.getElementById('p-profile');
  var out=[];
  Array.prototype.forEach.call(sec.children,function(el){
    var cls=el.className||'';
    if(el.tagName==='DIV'&&/text-xs font-extrabold text-slate-400/.test(cls)){
      out.push('T:'+el.textContent.trim()); return;
    }
    if(el.tagName==='DIV'&&/card/.test(cls)&&/LifeHarness/.test(el.textContent)){ out.push('ABOUT'); return; }
    var btns=[];
    if(el.tagName==='BUTTON'){ btns=[el]; }
    else if(el.tagName==='DIV'&&/card/.test(cls)){
      btns=el.querySelectorAll(':scope > button');
      if(!btns.length){
        var rt=el.querySelector('.row-title');
        if(rt) out.push('C:'+rt.textContent.trim());
      }
    }
    Array.prototype.forEach.call(btns,function(b){
      var t=(b.querySelector('b')||{}).textContent||'';
      if(t) out.push('R:'+t.trim());
    });
  });
  var firsts=[];
  Array.prototype.forEach.call(sec.querySelectorAll('.card > button:first-child'),function(b){
    firsts.push(b.className.indexOf('border-t')<0);
  });
  return {seq:out, firstNoBorder:firsts.length, firstClean:firsts.filter(Boolean).length,
    dark:document.documentElement.classList.contains('dark'),
    cds:!!document.querySelector('script[src*="tailwind"]'),
    h:document.documentElement.scrollHeight};
`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  child = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.pc-profile'), '--disable-extensions', '--no-default-browser-check',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) {
    const d = await get('http://127.0.0.1:' + PORT + '/json');
    if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } }
    await wait(300);
  }
  if (!data) { bad('chrome 起服'); return finish() }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => {
    const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 220));
  });
  await cmd('Runtime.enable'); await cmd('Page.enable');

  await setViewport(390, 1400);
  await cmd('Page.navigate', { url: SHELL + '#p-profile' });
  await wait(3200);
  await ev(`setPage('p-profile');return 1;`);
  await wait(700);

  const diag = await ev(`return {href:location.href,ready:document.readyState,
    secs:document.querySelectorAll('section').length,hasP:!!document.getElementById('p-profile'),
    n:document.body?document.body.innerHTML.length:0,
    hasFn:typeof setPage};`);
  console.log('DIAG ' + JSON.stringify(diag));

  const WANT = ['T:记录', 'R:分类管理', 'R:记录管理',
    'T:数据与提醒', 'R:数据与同步', 'R:提醒通知', 'R:AI 增强',
    'T:外观与交互', 'R:外观', 'C:底部导航栏自定义',
    'T:系统与维护', 'R:日志管理', 'R:回收站', 'R:图片存储清理', 'ABOUT'];

  for (const mode of ['light', 'dark']) {
    await emulate(mode);
    await ev(`setPage('p-profile');window.scrollTo(0,0);return 1;`);
    await wait(500);
    const s = await ev(READ);
    if (s.__err) { bad(mode + ' 读数可用', JSON.stringify(s)); continue }
    if (mode === 'light') {
      const seq = s.seq;
      JSON.stringify(seq) === JSON.stringify(WANT)
        ? ok('② 屏内顺序＝期望序列（4 标题 + 10 行 + 关于卡）', seq.join(' / '))
        : bad('② 顺序', 'got ' + seq.join(' / '));
      const wantRows = WANT.filter(x => x.startsWith('R:'));
      (wantRows.every(t => seq.includes(t)))
        ? ok('③ 二级入口一枚不少（' + wantRows.length + ' 枚）')
        : bad('③ 入口缺员', wantRows.filter(t => !seq.includes(t)).join(','));
      s.firstClean === s.firstNoBorder && s.firstNoBorder > 0
        ? ok('④ 各组首行无 border-t（' + s.firstClean + '/' + s.firstNoBorder + '）')
        : bad('④ 组首分隔线', s.firstClean + '/' + s.firstNoBorder);
      seq[seq.length - 1] === 'ABOUT' ? ok('⑤ 关于卡在页尾') : bad('⑤ 页尾', seq[seq.length - 1]);
      console.log('  · 视口宽 390 · 页面高 ' + s.h + ' · tailwind CDN ' + (s.cds ? 'in-dom' : 'missing'));
    } else {
      s.dark ? ok('⑥ 深色档整页 .dark 生效') : bad('⑥ 深色未生效（emulate 未钉住？）');
    }
    if (SHOTS) {
      await setViewport(390, 2400);
      await ev(`setPage('p-profile');window.scrollTo(0,0);return 1;`);
      await wait(520);
      const hh = await ev(`var s=document.getElementById('p-profile');
        var last=s.lastElementChild, r=last.getBoundingClientRect();
        return {h:Math.round(r.bottom+window.scrollY)+40,
          dark:document.documentElement.classList.contains('dark')};`);
      const h = Math.min(Math.max(hh.h, 1200), 2600);
      await setViewport(390, h);
      await ev(`setPage('p-profile');window.scrollTo(0,0);return 1;`);
      await wait(460);
      const d2 = await ev(`return {dark:document.documentElement.classList.contains('dark')};`);
      (mode === 'dark') === !!d2.dark ? ok('截图自检 ' + mode + '（.dark=' + d2.dark + ' · 高 ' + h + '）')
        : bad('截图自检 ' + mode, '.dark=' + d2.dark);
      await shot('profile-' + mode);
    }
  }

  if (errs.length) bad('页面无 JS 异常（' + errs.length + '）', errs[0]); else ok('页面无 JS 异常');
  finish();

  function finish() {
    try { if (child) child.kill() } catch (e) { }
    console.log('\nprofilecheck: ' + pass + ' PASS / ' + fail + ' FAIL');
    process.exit(fail ? 1 : 0);
  }
})();
