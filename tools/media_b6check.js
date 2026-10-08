/* media_b6check.js · 影音游批6「条目封面」原型先行无头闸
 * 规格依据＝docs/handoff/交棒话术-20261008-影音游批6条目封面原型.md §2（三源口径：计划 §四 L216「封面上传 canvas 压缩」＋ 需求侧无新键；原型此前零命中）
 * 纪律沿用 media_b5check.js＝期望值一律页面内现算不硬编码；截图默认关（MB6_SHOTS=1 才拍）；工装改名复用同一 boot
 * 标记类：.mds-item 架面卡 · .cover 封面层 · .covimg 用户上传图层 · .covmono 色板首字回落
 * 用法：node --experimental-websocket tools/media_b6check.js */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index-media.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.MB6_PORT || 9616);
const SHOTS = process.env.MB6_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/media-b6-shots';
let chrome, pass = 0, fail = 0; const errs = [];
const log = m => { console.log(m) };
const ok = (n, i) => { pass++; log('PASS ' + n + (i ? '  →  ' + i : '')) };
const bad = (n, i) => { fail++; log('FAIL ' + n + '  →  ' + (i || '')) };
const wait = ms => new Promise(r => setTimeout(r, ms));
function get(u) { return new Promise(res => { try { http.get(u, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res(d)) }).on('error', () => res(null)) } catch (e) { res(null) } }) }
let ws, idc = 0; const pend = new Map();
function cmd(method, params) { return new Promise(res => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params: params || {} })) }) }
async function ev(expr) {
  const m = await cmd('Runtime.evaluate', { expression: 'JSON.stringify((function(){' + expr + '})())', returnByValue: false });
  const r = m.result && m.result.result; try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 300) } }
}
/* 异步断言：页面内 promise 直接 await（降采样那条必走真 Image onload） */
async function evA(expr) {
  const m = await cmd('Runtime.evaluate', { expression: '(async function(){' + expr + '})()', returnByValue: true, awaitPromise: true });
  if (m.error) return { __err: JSON.stringify(m.error).slice(0, 300) };
  return m.result && m.result.result ? m.result.result.value : { __err: 'no result' };
}
async function shot(name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64'));
}

/* 页面内探针：全部期望值现算 */
const PRELUDE = String.raw`
window.__big=function(w,h){var c=document.createElement('canvas');c.width=w;c.height=h;var g=c.getContext('2d');
  g.fillStyle='#c0392b';g.fillRect(0,0,w,h);g.fillStyle='#f1c40f';g.fillRect(w*0.2,h*0.2,w*0.6,h*0.6);return c.toDataURL('image/png')};
window.__card=function(id){return [].slice.call(document.querySelectorAll('#mShelfBody .mds-item')).filter(function(el){
  return (el.getAttribute('onclick')||'').indexOf("'"+id+"'")>=0})[0]};
window.__cov=function(id){var el=__card(id);return el?el.querySelector('.cover'):null};
window.__txt=function(el){return el?(el.textContent||'').replace(/\s+/g,''):''};
window.__delHidden=function(){var d=document.getElementById('mdsAddCoverDel');return d?d.classList.contains('hidden'):null};
window.__mono=function(){var e=document.querySelector('#mdsAddCover .covmono');return e?__txt(e):null};
window.__shot=function(){var e=document.querySelector('#mdsAddCover .covimg');return e?{bg:e.style.backgroundImage.slice(0,24),len:mAddCoverImg?mAddCoverImg.length:0}:null};
`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.media6-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,1000', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => {
    const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 300));
  });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF });
  // 专版头部挂着 `<script src="https://cdn.tailwindcss.com">`，它会阻塞解析；本机首次取 CDN 可能几秒到几十秒，
  // 定长 wait 会让整轮断言跑在空文档上（表现为一片 ReferenceError＝工装坑不是原型坑）。故按 readyState 轮询。
  for (let i = 0; i < 40; i++) { const t = await ev('return typeof MDEMO'); if (t && t !== 'undefined') break; await wait(1000) }
  await wait(600);
  await ev(PRELUDE + 'return 1;');

  /* A0 架面不回归：初始无用户封面，卡数照旧，色板回落仍在 */
  const a0 = await ev(`navTo('m-shelf');mRenderShelf();
    return {p:curPage,c:document.querySelectorAll('#mShelfBody .mds-item').length,
      img:document.querySelectorAll('#mShelfBody .covimg').length,
      grad:[].slice.call(document.querySelectorAll('#mShelfBody .cover')).filter(function(e){return /linear-gradient/.test(e.getAttribute('style')||'')||/--c1/.test(e.getAttribute('style')||'')}).length};`);
  (a0.p === 'm-shelf' && a0.c >= 8 && a0.img === 0 && a0.grad === a0.c)
    ? ok('A0 架面照旧 ' + a0.c + ' 张，初始全走色板回落', '封面图层 0') : bad('A0', JSON.stringify(a0));

  /* A1 表单封面行：缩略位＋拍照/相册/移除三枚，无说明文案，未选图时出首字回落 */
  const a1 = await ev(`openSheet('m-sheet-add');
    var row=document.getElementById('mdsAddCoverRow');
    var btns=[].slice.call(row?row.querySelectorAll('button'):[]).map(function(b){return b.textContent});
    var slot=document.getElementById('mdsAddCover');
    return {ids:['mdsAddCoverRow','mdsAddCover','mdsAddCoverCam','mdsAddCoverLib','mdsAddCoverDel','mdsAddCoverFile'].filter(function(i){return document.getElementById(i)}).length,
      btns:btns.join('/'),del:__delHidden(),mono:__mono(),slotTx:__txt(slot).length,
      fileAccept:(document.getElementById('mdsAddCoverFile')||{}).accept,
      ar:(function(){var e=document.getElementById('mdsAddCover');return e?+(e.offsetHeight/e.offsetWidth).toFixed(2):0})()};`);
  (a1.ids === 6 && a1.btns === '拍照/相册/移除' && a1.del === true && a1.mono !== null && a1.slotTx === 0 && a1.fileAccept === 'image/*' && a1.ar === 1.33)
    ? ok('A1 封面行到位：三枚按钮＋隐藏取图口，缩略位 3:4 竖版，行内除按钮无文案', '按钮=' + a1.btns + ' · 高宽比 ' + a1.ar) : bad('A1', JSON.stringify(a1));

  /* A2 首字预览随标题现算（不是写死） */
  const a2 = await ev(`document.getElementById('mdsAddTitle').value='  沙丘 2  ';mRenderAddCover();
    return {mono:__mono(),exp:document.getElementById('mdsAddTitle').value.trim()[0],slotTx:__txt(document.getElementById('mdsAddCover')).length};`);
  (a2.mono && a2.mono === a2.exp && a2.slotTx === 1)
    ? ok('A2 未选图＝色板＋标题首字回落', '首字「' + a2.mono + '」') : bad('A2', JSON.stringify(a2));

  /* A3 降采样口径：1200×1600 注入 → 长边 ≤480、比例守住、缩略位出图层、移除钮现身 */
  const a3 = await evA(`var u=window.__big(1200,1600);var r=await mCoverApply(u);
    return {r:r&&{w:r.w,h:r.h,sw:r.sw,sh:r.sh},ratio:r?+(r.w/r.h).toFixed(3):null,img:!!__shot(),
      del:__delHidden(),storedLen:r?r.url.length:0,isJpeg:/^data:image\\/jpeg/.test(r?r.url:'')};`);
  (a3.r && a3.r.sw === 1200 && Math.max(a3.r.w, a3.r.h) <= 480 && a3.ratio === 0.75 && a3.img && a3.del === false && a3.isJpeg && a3.storedLen > 1000)
    ? ok('A3 走 canvas 降采样：1200×1600 → ' + a3.r.w + '×' + a3.r.h + '（长边钉 480·出 JPEG）') : bad('A3', JSON.stringify(a3));

  await shot('A3-表单已选图');
  /* A4 移除＝回落到色板首字，状态清零 */
  const a4 = await ev(`mCoverClear();return {img:!!__shot(),mono:__mono(),del:__delHidden(),v:mAddCoverImg};`);
  (a4.img === false && a4.mono === '沙' && a4.del === true && a4.v === null)
    ? ok('A4 移除后回色板首字，mAddCoverImg 归 null') : bad('A4', JSON.stringify(a4));

  /* A5 新建保存：封面写进条目（期望值＝保存前现算的 dataURL），架面首张卡立即吃到图层 */
  const a5 = await evA(`var u=window.__big(900,900);await mCoverApply(u);var want=mAddCoverImg;
    var n0=MDEMO.length;mAddSave();
    var x=MDEMO[0];
    return {added:MDEMO.length-n0,title:x.title,eq:x.coverImg===want,imgCard:!!__cov(x.id).querySelector('.covimg'),
      shelfImg:document.querySelectorAll('#mShelfBody .covimg').length,v:mAddCoverImg};`);
  (a5.added === 1 && a5.title === '沙丘 2' && a5.eq && a5.imgCard && a5.shelfImg === 1 && a5.v === null)
    ? ok('A5 新建即带封面：条目 coverImg＝刚降采样那张，架面同帧出图层') : bad('A5', JSON.stringify(a5));

  await shot('A5-架面吃到封面');
  /* A6 图层不破形：封面图压在最底（0），装饰件抬到 1，遮罩 ::after 仍在 2 */
  const a6 = await ev(`var cv=__cov(MDEMO[0].id),img=cv.querySelector('.covimg'),ttl=cv.querySelector('.ttl');
    return {imgZ:getComputedStyle(img).zIndex,ttlZ:getComputedStyle(ttl).zIndex,
      aft:getComputedStyle(cv,'::after').zIndex,aftBg:getComputedStyle(cv,'::after').backgroundImage.slice(0,30),
      pos:getComputedStyle(ttl).position,size:getComputedStyle(img).position};`);
  (a6.imgZ === '0' && a6.ttlZ === '1' && a6.aft === '2' && /gradient/.test(a6.aftBg) && a6.pos === 'relative' && a6.size === 'absolute')
    ? ok('A6 层级＝图 0 < 装饰 1 < 遮罩 2，形态件与暗角都没被盖掉') : bad('A6', JSON.stringify(a6));

  /* A7 编辑态：走「条目操作 · 编辑信息」，不新建重复条目，标题与封面一并回写 */
  const a7 = await evA(`var t=MDEMO[0];navTo('m-detail');mCurDetail=t;
    var n0=MDEMO.length;openSheet('m-sheet-ops');
    var row=[].slice.call(document.querySelectorAll('#mOpsList>div')).filter(function(d){return d.textContent==='编辑信息'})[0];
    row.click();
    var btn=document.getElementById('mdsAddSaveBtn'),editTx=btn.textContent;
    document.getElementById('mdsAddTitle').value='沙丘 2（重剪版）';
    await mCoverApply(window.__big(700,300));var want=mAddCoverImg;
    mAddSave();
    return {same:MDEMO.length===n0,editTx:editTx,backTx:document.getElementById('mdsAddSaveBtn').textContent,
      title:t.title,eq:t.coverImg===want,detail:__txt(document.getElementById('mdsDetailTitle'))===t.title.replace(/\\s+/g,''),
      opsDemo:/演示/.test(document.getElementById('mOpsList').textContent)};`);
  (a7.same && a7.editTx === '保存改动' && a7.backTx === '保存 · 进入影音架' && a7.title === '沙丘 2（重剪版）' && a7.eq && a7.detail && !a7.opsDemo)
    ? ok('A7 编辑态改封面＝原条目回写，不新建重复条目；「编辑信息」不再是演示') : bad('A7', JSON.stringify(a7));

  /* A10 详情面同吃封面（拍板③）：详情体走同一张卡，头图与卡片同源不另造一套 */
  const a10 = await ev(`mOpen(MDEMO[0].id);
    var body=document.getElementById('mdsDetailBody');
    return {hero:!!body.querySelector('.covimg'),mono:!!body.querySelector('.covmono'),
      ttl:!!body.querySelector('.mds-item .ttl'),title:__txt(document.getElementById('mdsDetailTitle'))===MDEMO[0].title.replace(/\\s+/g,'')};`);
  (a10.hero && a10.ttl && a10.title)
    ? ok('A10 详情头图吃用户封面（与架面同一张卡，形态件仍在）') : bad('A10', JSON.stringify(a10));

  /* A8 其余条目仍走色板回落（四类形态件一个不丢） */
  const a8 = await ev(`navTo('m-shelf');mRenderShelf();
    var cards=[].slice.call(document.querySelectorAll('#mShelfBody .mds-item'));
    var withImg=cards.filter(function(e){return e.querySelector('.covimg')}).length;
    var vinyl=document.querySelectorAll('#mShelfBody .mds-item.vinyl .disc').length;
    var gcart=document.querySelectorAll('#mShelfBody .mds-item.gmcard .gcart').length;
    var ttl=cards.filter(function(e){return !e.querySelector('.ttl')}).length;
    return {cards:cards.length,withImg:withImg,vinyl:vinyl,gcart:gcart,noTtl:ttl};`);
  (a8.cards >= 8 && a8.withImg === 1 && a8.vinyl >= 1 && a8.gcart >= 1 && a8.noTtl === 0)
    ? ok('A8 只有一条吃到图，黑胶/游戏卡形态与片名一根没少', a8.cards + ' 张 · 有图 ' + a8.withImg) : bad('A8', JSON.stringify(a8));

  /* A9 取图口：camera 档带 capture，gallery 档不带（两格语义真分开） */
  const a9 = await ev(`mCoverPick('camera');var c=document.getElementById('mdsAddCoverFile').getAttribute('capture');
    mCoverPick('gallery');var g=document.getElementById('mdsAddCoverFile').getAttribute('capture');
    closeSheet('m-sheet-add');return {c:c,g:g};`);
  (a9.c === 'environment' && a9.g === null)
    ? ok('A9 拍照档挂 capture=environment，相册档不挂') : bad('A9', JSON.stringify(a9));

  await shot('A-final-shelf');
  const pe = errs.filter(e => !/lh-gov|init skip/.test(e));
  (pe.length === 0 ? ok : bad)('Z0 PAGE ERRORS', pe.length ? pe.join(' || ') : '0');

  finish();
})().catch(e => { bad('工装异常 ' + e.message); finish() });

function finish() { try { if (ws) ws.close() } catch (e) { } try { chrome && chrome.kill() } catch (e) { }
  log('---- media_b6check: ' + pass + '/' + (pass + fail) + ' 绿 ----');
  process.exit(fail ? 1 : 0);
}
