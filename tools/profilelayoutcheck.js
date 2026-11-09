/* 「我的」页 · 版式三选门（2026-10-12 · 待产品过门）
 *
 * 断言：
 *   ① 默认态：body.lay-hero、hero 身份卡显示、旧顶区两处隐藏（回归守护·默认＝方向一）
 *   ② chapters：hero 隐藏、旧顶区可见、组标题 ::before 含 "01"、卡片去卡（透明底＋无阴影）
 *   ③ minimal：hero 隐藏、旧顶区可见、组标题无编号、卡片去卡（去发丝）
 *   ④ 持久化：setMyLayout 写 localStorage lh.myLayout；setMyLayout('hero') 复原
 *   ⑤ 切换卡：#myLayoutCard 在册、三分段唯一选中、点按钮可切换
 *   ⑥ setMyLayout('hero') 复原（hero 显示、旧顶区隐藏）
 *   ⑦ 全程无 JS 异常
 * 截图：三版式 × 浅/深（6 张），CDP 真 390 视口 + prefers-color-scheme 显式钉。
 * 用法：node tools/profilelayoutcheck.js            # 断言
 *      PL_SHOTS=1 node tools/profilelayoutcheck.js  # 断言 + 出图
 * 变异自证：改默认值 / 删编号CSS / 删去卡CSS / 改持久化key ⇒ ① / ② / ② / ④ 各红其位。
 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.PL_PORT || 9624);
const SHOTS = process.env.PL_SHOTS === '1';
const SHOTDIR = path.resolve('prototype/shots/profile-layout');
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

const READ = `
  var vis=function(el){return !!el && getComputedStyle(el).display!=='none';};
  var sec=document.getElementById('p-profile');
  var hero=document.querySelector('.pf-hero');
  var legs=document.querySelectorAll('.pf-legacy');
  var gts=document.querySelectorAll('#p-profile .pf-gt');
  var gt0=gts[0]||null;
  var gt0before=gt0?getComputedStyle(gt0,'::before').content:'';
  var card=document.querySelector('#p-profile>.card');
  var cs=card?getComputedStyle(card):null;
  var cur='hero'; ['hero','chapters','minimal'].forEach(function(k){ if(document.body.classList.contains('lay-'+k)) cur=k; });
  var segSel=['layHero','layChapters','layMinimal'].filter(function(id){var b=document.getElementById(id);return b&&b.classList.contains('seg-on');});
  return {
    heroVisible:vis(hero),
    legacyVisible:[].slice.call(legs).map(vis),
    legacyN:legs.length,
    gtN:gts.length,
    gt0before:gt0before,
    cardBg:cs?cs.backgroundColor:'',
    cardShadow:cs?cs.boxShadow:'',
    lay:cur,
    bodyClass:document.body.className,
    ls:(function(){try{return localStorage.getItem('lh.myLayout')}catch(e){return 'ERR'}})(),
    segSel:segSel,
    hasCard:!!document.getElementById('myLayoutCard'),
    hint:(function(){var h=document.getElementById('myLayoutHint');return h?h.textContent.trim().slice(0,10):null;})(),
    dark:document.documentElement.classList.contains('dark'),
    h:document.documentElement.scrollHeight
  };
`;

const transparentBg = s => /rgba\(0, 0, 0, 0\)/.test(s) || s === 'transparent';

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  child = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.pl-profile'), '--disable-extensions', '--no-default-browser-check',
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
  await setViewport(390, 1500);

  async function load(qs) {
    await cmd('Page.navigate', { url: SHELL + qs + '#p-profile' });
    await wait(3200);
    await ev(`setPage('p-profile');window.scrollTo(0,0);return 1;`);
    await wait(650);
  }

  /* 清掉可能残留的持久化值，保证默认态可复现 */
  await emulate('light');
  await load('');
  await ev(`try{localStorage.removeItem('lh.myLayout')}catch(e){}return 1;`);

  /* ---- ① 默认态（无参数、无持久化） ---- */
  await load('');
  let s = await ev(READ);
  if (s.__err) { bad('默认态读数可用', JSON.stringify(s)); }
  else {
    s.lay === 'hero' ? ok('①a 默认版式=hero（方向一）') : bad('①a 默认版式', 'lay=' + s.lay + ' body="' + s.bodyClass + '"');
    s.heroVisible ? ok('①b hero 身份卡显示') : bad('①b hero 显示', 'visible=false');
    (s.legacyN === 2 && s.legacyVisible.every(v => !v)) ? ok('①c 旧顶区两处隐藏')
      : bad('①c 旧顶区', 'n=' + s.legacyN + ' vis=' + JSON.stringify(s.legacyVisible));
  }

  /* ---- ② chapters ---- */
  await load('?mylayout=chapters');
  s = await ev(READ);
  if (s.__err) { bad('chapters 读数可用', JSON.stringify(s)); }
  else {
    s.lay === 'chapters' ? ok('②a 版式=chapters') : bad('②a 版式', 'lay=' + s.lay);
    (!s.heroVisible && s.legacyN === 2 && s.legacyVisible.every(Boolean)) ? ok('②b hero 隐藏 / 旧顶区可见')
      : bad('②b 显隐', 'hero=' + s.heroVisible + ' legacy=' + JSON.stringify(s.legacyVisible));
    (s.gtN === 4) ? ok('②c 四组标题在册') : bad('②c 组标题数', 'gtN=' + s.gtN);
    (/'01'|"01"/.test(s.gt0before) || s.gt0before.indexOf('01') >= 0) ? ok('②d 首组标题编号 01（' + s.gt0before + '）')
      : bad('②d 编号', 'before=' + s.gt0before);
    (transparentBg(s.cardBg) && s.cardShadow === 'none') ? ok('②e 卡片去卡（透明底＋无阴影）')
      : bad('②e 去卡', 'bg=' + s.cardBg + ' sh=' + s.cardShadow);
  }

  /* ---- ③ minimal ---- */
  await load('?mylayout=minimal');
  s = await ev(READ);
  if (s.__err) { bad('minimal 读数可用', JSON.stringify(s)); }
  else {
    s.lay === 'minimal' ? ok('③a 版式=minimal') : bad('③a 版式', 'lay=' + s.lay);
    (!s.heroVisible && s.legacyN === 2 && s.legacyVisible.every(Boolean)) ? ok('③b hero 隐藏 / 旧顶区可见')
      : bad('③b 显隐', 'hero=' + s.heroVisible + ' legacy=' + JSON.stringify(s.legacyVisible));
    (s.gt0before.indexOf('01') < 0) ? ok('③c 组标题无编号（minimal 不用章节标）')
      : bad('③c 编号', 'before=' + s.gt0before);
    (transparentBg(s.cardBg) && s.cardShadow === 'none') ? ok('③d 卡片去卡')
      : bad('③d 去卡', 'bg=' + s.cardBg + ' sh=' + s.cardShadow);
  }

  /* ---- ④ 持久化 + ⑥ 复原 ---- */
  await ev(`window.setMyLayout('minimal');return 1;`); await wait(260);
  let s4 = await ev(READ);
  (s4.ls === 'minimal' && s4.lay === 'minimal') ? ok('④a setMyLayout 写持久化（lh.myLayout=minimal）')
    : bad('④a 持久化', 'ls=' + s4.ls + ' lay=' + s4.lay);
  await ev(`window.setMyLayout('hero');return 1;`); await wait(300);
  let s6 = await ev(READ);
  (s6.heroVisible && s6.legacyVisible.every(v => !v) && s6.lay === 'hero' && s6.ls === 'hero')
    ? ok('⑥ setMyLayout(hero) 复原 + 持久化=hero')
    : bad('⑥ 复原', 'hero=' + s6.heroVisible + ' legacy=' + JSON.stringify(s6.legacyVisible) + ' ls=' + s6.ls);

  /* ---- ⑤ 切换卡 ---- */
  let s5 = await ev(READ);
  s5.hasCard ? ok('⑤a #myLayoutCard 在册') : bad('⑤a 切换卡', 'missing');
  (s5.segSel.length === 1 && s5.segSel[0] === 'layHero') ? ok('⑤b 三分段唯一选中跟随（当前 hero）')
    : bad('⑤b 选中态', JSON.stringify(s5.segSel));
  await ev(`document.getElementById('layChapters').click();return 1;`); await wait(300);
  let s5b = await ev(READ);
  (s5b.lay === 'chapters' && s5b.segSel.length === 1 && s5b.segSel[0] === 'layChapters')
    ? ok('⑤c 点按钮可切换（layChapters）') : bad('⑤c 按钮切换', 'lay=' + s5b.lay + ' seg=' + JSON.stringify(s5b.segSel));
  await ev(`window.setMyLayout('hero');return 1;`); await wait(220);

  /* ---- 截图：三版式 × 浅/深 ---- */
  if (SHOTS) {
    for (const mode of ['light', 'dark']) {
      await emulate(mode);
      for (const lay of ['hero', 'chapters', 'minimal']) {
        await ev(`try{localStorage.removeItem('lh.myLayout')}catch(e){}return 1;`);
        await load('?mylayout=' + lay);
        const hh = await ev(`var s=document.getElementById('p-profile');
          var last=s.lastElementChild, r=last.getBoundingClientRect();
          return {h:Math.round(r.bottom+window.scrollY)+40,
            dark:document.documentElement.classList.contains('dark')};`);
        const h = Math.min(Math.max(hh.h, 1000), 2800);
        await setViewport(390, h);
        await ev(`window.scrollTo(0,0);return 1;`);
        await wait(420);
        const d2 = await ev(`return {dark:document.documentElement.classList.contains('dark')};`);
        const wantDark = (mode === 'dark');
        (wantDark === !!d2.dark) ? ok('截图自检 ' + mode + '/' + lay + '（.dark=' + d2.dark + ' · 高 ' + h + '）')
          : bad('截图自检 ' + mode + '/' + lay, '.dark=' + d2.dark);
        await shot('layout-' + lay + '-' + mode);
      }
    }
    await ev(`try{localStorage.removeItem('lh.myLayout')}catch(e){}return 1;`);
  }

  if (errs.length) bad('页面无 JS 异常（' + errs.length + '）', errs[0]); else ok('⑦ 页面无 JS 异常');
  finish();

  function finish() {
    try { if (child) child.kill() } catch (e) { }
    console.log('\nprofilelayoutcheck: ' + pass + ' PASS / ' + fail + ' FAIL');
    process.exit(fail ? 1 : 0);
  }
})();
