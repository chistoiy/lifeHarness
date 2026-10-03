/* 批三 R3-2 原书样式保真 · 原型门校验（CDP 无头 Chrome · 骨架照抄 f01typecheck.js）
 * 逐深链断言：?r32=st1 开态（五层色＋专名/书名线＋标签块 computed 值）· ?r32=st0 关态＝现状止血 · ?r32=stn 外观弹层提示行
 * 用法：node --experimental-websocket tools/r32stylecheck.js
 * 截图 4 张落 prototype/shots（gitignored，不入仓）。 */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = Number(process.env.R32_PORT || 9617);
const SHOTS = 'prototype/shots';
const FILE = 'prototype/index-bookshelf.html';
let pass = 0, fail = 0;
const ok = (n, i) => { pass++; console.log('PASS ' + n + (i ? '  →  ' + i : '')); };
const bad = (n, i) => { fail++; console.log('FAIL ' + n + '  →  ' + (i || '')); };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function get(u) {
  return new Promise((res) => {
    try {
      require('http').get(u, (r) => { let d = ''; r.on('data', (c) => { d += c; }); r.on('end', () => res(d)); })
        .on('error', () => res(''));
    } catch (e) { res(''); }
  });
}
let ws, idc = 0; const pend = new Map();
function cmd(method, params) {
  return new Promise((res) => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })); });
}
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())' });
  const r = m.result && m.result.result;
  try { return JSON.parse(r.value); } catch (e) { return { __err: (r && (r.value || r.description)) || 'ev fail' }; }
}
async function shot(name, clip) {
  const p = { format: 'png' }; if (clip) p.clip = Object.assign({ scale: 1 }, clip);
  const m = await cmd('Page.captureScreenshot', p);
  const b = m.result && m.result.data;
  if (!b) { bad('截图 ' + name); return; }
  fs.mkdirSync(SHOTS, { recursive: true });
  fs.writeFileSync(path.join(SHOTS, name), Buffer.from(b, 'base64'));
  console.log('  截图 ' + name + ' (' + Math.round(Buffer.from(b, 'base64').length / 1024) + 'KB)');
}
async function open(qs) {
  /* 每屏先清持久化再进深链：st0/st1 会写 brBooksCfg.b13.orig，防上轮状态污染 stn 默认态 */
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve(FILE)).href });
  await wait(1200);
  await ev("localStorage.removeItem('lh_reader_bs_v1');return 1");
  await cmd('Page.navigate', { url: url.pathToFileURL(path.resolve(FILE)).href + (qs || '') });
  await wait(2200);
}
function finish(chrome) {
  console.log(`\n结果：${pass} 绿 / ${fail} 红`);
  try { chrome.kill(); } catch (e) { }
  try { ws.close(); } catch (e) { }
  process.exit(fail ? 1 : 0);
}
const CS = `var ps=[].slice.call(document.querySelectorAll('#brBody p'));
  function byRe(re){return ps.filter(function(p){return re.test(p.textContent)})[0]||null}
  function info(p){if(!p)return null;var c=getComputedStyle(p);
    return{cls:p.className,color:c.color,bg:c.backgroundColor,fw:c.fontWeight,fsz:c.fontSize,
      tds:c.textDecorationStyle,tdl:c.textDecorationLine,blw:c.borderLeftWidth,bls:c.borderLeftStyle,
      bs:c.borderTopStyle,bt:c.borderTopWidth}}`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return process.exit(1); }
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--remote-debugging-port=' + PORT, '--user-data-dir=' + path.resolve('tools/.r32-profile'),
    '--disable-extensions', '--no-default-browser-check', '--window-size=430,900',
    '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) {
    const d = await get('http://127.0.0.1:' + PORT + '/json');
    if (d) { try { data = JSON.parse(d); if (data.some((x) => x.type === 'page')) break; } catch (e) { } }
    await wait(300);
  }
  if (!data) { bad('CDP 起不来'); return process.exit(1); }
  ws = new WebSocket(data.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => { ws.addEventListener('open', r); setTimeout(r, 3000); });
  ws.addEventListener('message', (e2) => {
    const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
  });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Emulation.setDeviceMetricsOverride', { width: 430, height: 900, deviceScaleFactor: 2, mobile: true });

  /* 0) 清持久化，防上轮状态污染 */
  await open('');
  await ev("localStorage.removeItem('lh_reader_bs_v1');return 1");

  /* 1) st1 开态：五层色＋两类线＋标签块 */
  await open('?r32=st1');
  let r = await ev("brV.mode='scroll';brRenderPage();" + CS + `
    var g=byRe(/起著雍攝提格/),rg=byRe(/初，智宣子將以瑤為後/),cm=byRe(/臣聞天子之職/),
        nt=byRe(/胡三省注：作，謂能創制/),co=byRe(/舊本訛作/),tg=byRe(/^臣光曰$/),bt=byRe(/帝賜名曰資治通鑑/);
    var nmp=rg,nm=nmp?nmp.querySelector('.brp-nm'):null;
    var nm1p=byRe(/司馬光編年/),nm1=nm1p?nm1p.querySelector('.brp-nm1'):null,nmg=nm1p?nm1p.querySelector('.brp-nm'):null;
    var bts=document.querySelector('#brBody .brp-bt');
    return{orig:brSt('b13').orig,g:info(g),rg:info(rg),cm:info(cm),nt:info(nt),co:info(co),tg:info(tg),bt:info(bt),
      nm:nm?{t:nm.textContent,blw:getComputedStyle(nm).borderLeftWidth,bls:getComputedStyle(nm).borderLeftStyle}:null,
      smg:nmg?nmg.textContent:'',
      nm1:nm1?{t:nm1.textContent,bs:getComputedStyle(nm1).borderTopStyle,bt:getComputedStyle(nm1).borderTopWidth}:null,
      bts:bts?{t:bts.textContent,tds:getComputedStyle(bts).textDecorationStyle,tdl:getComputedStyle(bts).textDecorationLine}:null,
      nRole:document.querySelectorAll('#brBody [class*=brp-]:not(.brp):not(.brp-h):not(.brp-h1):not(.brp-h2):not(.brp-fn):not(.brp-own):not(.brp-q)').length}`);
  const px = (v) => parseFloat(v || '0');
  (r.orig === true) ? ok('st1：orig 默认开') : bad('st1：orig 默认开', JSON.stringify(r.orig));
  (r.g && r.g.color === 'rgb(105, 105, 105)' && px(r.g.fsz) > 16 && px(r.g.fsz) < 17.2) ? ok('st1：按语＝DimGray .88em', r.g && r.g.fsz) : bad('st1：按语层', JSON.stringify(r.g));
  (r.rg && r.rg.color === 'rgb(139, 69, 19)' && r.rg.fw === '700') ? ok('st1：纪年＝SaddleBrown 700') : bad('st1：纪年层', JSON.stringify(r.rg));
  (r.cm && r.cm.color === 'rgb(0, 0, 128)') ? ok('st1：史评＝navy') : bad('st1：史评层', JSON.stringify(r.cm));
  (r.nt && r.nt.color === 'rgb(0, 100, 0)' && px(r.nt.fsz) > 13.9 && px(r.nt.fsz) < 14.6) ? ok('st1：注＝DarkGreen .75em', r.nt && r.nt.fsz) : bad('st1：注层', JSON.stringify(r.nt));
  (r.co && r.co.color === 'rgb(128, 0, 128)') ? ok('st1：校勘＝Purple') : bad('st1：校勘层', JSON.stringify(r.co));
  (r.tg && r.tg.bg === 'rgb(105, 105, 105)' && r.tg.color === 'rgb(255, 255, 255)' && r.tg.bs === 'double') ? ok('st1：臣光曰＝标签块（DimGray 底白字 double 框）') : bad('st1：标签块', JSON.stringify(r.tg));
  (r.nm && /智宣子/.test(r.nm.t) && px(r.nm.blw) >= 1 && r.nm.bls === 'solid') ? ok('st1：人名线＝左实线 .12em', JSON.stringify(r.nm)) : bad('st1：人名线', JSON.stringify(r.nm));
  (r.smg === '司馬光') ? ok('st1：人名线覆盖纪年段外「司馬光」') : bad('st1：司馬光线', JSON.stringify(r.smg));
  (r.nm1 && /三家分晉/.test(r.nm1.t) && r.nm1.bs === 'solid') ? ok('st1：朝代·称号线＝四周细框', JSON.stringify(r.nm1)) : bad('st1：称号线', JSON.stringify(r.nm1));
  (r.bts && /資治通鑑/.test(r.bts.t) && r.bts.tdl === 'underline' && r.bts.tds === 'wavy') ? ok('st1：书名线＝波浪下划线示意（原书 gif 平铺）', JSON.stringify(r.bts)) : bad('st1：书名线', JSON.stringify(r.bts));
  (r.bt && r.bt.color && r.bt.color !== 'rgb(0, 0, 0)' && px(r.bt.fsz) >= 19) ? ok('st1：书名线段本体走正文色（线只在 span 上）') : bad('st1：书名线段', JSON.stringify(r.bt));
  await shot('r32_st1_full.png');
  let rect = await ev("var b=document.getElementById('brBody');var q=b.closest('[id]')||b;var r=b.getBoundingClientRect();return{x:r.x,y:r.y,w:r.width,h:r.height}");
  await shot('r32_st1_body.png', rect.w ? { x: rect.x, y: Math.max(0, rect.y), width: rect.w, height: Math.min(820, rect.h) } : null);

  /* 2) st0 关态：＝现状止血口径，角色层全不挂 */
  await open('?r32=st0');
  r = await ev("brV.mode='scroll';brRenderPage();" + CS + `
    var fn=byRe(/胡三省注：作，謂能創制/),cm=byRe(/臣聞天子之職/);
    return{orig:brSt('b13').orig,
      role:document.querySelectorAll('#brBody .brp-cmt,#brBody .brp-note,#brBody .brp-corr,#brBody .brp-reign,#brBody .brp-gray,#brBody .brp-tag,#brBody .brp-nm,#brBody .brp-nm1,#brBody .brp-bt').length,
      fnCls:fn?fn.className:'none',fnHas:fn?/brp-fn/.test(fn.className):false,
      cmColor:cm?getComputedStyle(cm).color:'',stage:document.getElementById('brStage').style.color}`);
  (r.orig === false) ? ok('st0：orig 关') : bad('st0：orig 关', JSON.stringify(r.orig));
  (r.role === 0) ? ok('st0：无任何角色 class 上屏（＝现状不退化）') : bad('st0：关态残留角色', JSON.stringify(r.role));
  (r.fnHas) ? ok('st0：注释段仍走止血 brp-fn') : bad('st0：止血口径', JSON.stringify(r));
  (r.cmColor && r.cmColor === r.stage ? true : r.cmColor && r.stage && r.cmColor.replace(/\s/g, '') === r.stage.replace(/\s/g, '')) ? ok('st0：史评段＝主题正文色', r.cmColor) : bad('st0：正文色回落', JSON.stringify(r));
  await shot('r32_st0_full.png');

  /* 3) stn 外观弹层：开关行在位·默认开·不支持项提示行（数据驱动非静默） */
  await open('?r32=stn');
  r = await ev(`var t=document.getElementById('brApOrigTgl'),w=document.getElementById('brApOrigWarn'),
    sh=document.getElementById('sheetBrAppearance');
    var justRow=[].slice.call(document.querySelectorAll('#sheetBrAppearance span')).filter(function(x){return x.textContent==='两端对齐'})[0];
    return{sheetOpen:sh?(!sh.classList.contains('hidden')):false,
      tgl:!!t,on:t?t.classList.contains('on'):false,warn:!!w,warnHidden:w?w.classList.contains('hidden'):true,
      warnTxt:w?w.textContent:'',justRow:!!justRow,
      rowTxt:t?t.closest('div').textContent:''}`);
  (r.sheetOpen) ? ok('stn：外观弹层已开') : bad('stn：弹层未开');
  (r.tgl && r.on) ? ok('stn：「跟随原书样式」开关在位且默认开') : bad('stn：开关', JSON.stringify(r));
  (r.warn && !r.warnHidden && /竖排/.test(r.warnTxt) && /横排单栏/.test(r.warnTxt)) ? ok('stn：不支持项提示行可见（b13 unsupported:vertical）', r.warnTxt) : bad('stn：提示行', JSON.stringify(r));
  (r.justRow && /跟随原书样式/.test(r.rowTxt)) ? ok('stn：开关行落在「两端对齐」同组') : bad('stn：开关行位置', JSON.stringify(r));
  await shot('r32_stn_appearance.png');

  /* 4) 关态点开关→开态联动（开关真接线，不只是 BR_DEF） */
  r = await ev(`var t=document.getElementById('brApOrigTgl');t.click();
    var t2=document.getElementById('brApOrigTgl');
    var p=[].slice.call(document.querySelectorAll('#brBody p')).filter(function(x){return /臣光曰/.test(x.textContent)})[0];
    return{draft:brDraft.orig,on:t2?t2.classList.contains('on'):null,tagCls:p?p.className:'no-par'}`);
  (r.draft === false) ? ok('stn：点一下开关草稿值转关（接线活）', JSON.stringify(r)) : bad('stn：开关联动', JSON.stringify(r));

  finish(chrome);
})();
