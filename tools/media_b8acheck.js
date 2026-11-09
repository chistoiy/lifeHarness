/* media_b8acheck.js · 影音游批8a 原型先行两面的无头回归（m-goal 目标屏 · m-set 设置屏＋生效连线＋计时状态机）
 * 口径依据＝docs/handoff/交棒话术-20261009-影音游批8a目标屏与设置生效面原型.md §0 五项拍板
 *   （六行目标＝L7 六路 · 就地单列滚轮 · 读数恒吃真实时长 · 更新提醒三行灰态 · 设置逐行当场生效 · speedFold 双向同源）
 * 标记类：.mgrow[data-mg] · [data-mgread] · .mgtarget[data-mgt] · [data-mgunset] · [data-mgbar] · .mgwheel[data-mgwheel] ·
 *   .mgoalrow[data-mgoal]+[data-mgfill] · .mset-tab[data-t] · .mset-row[data-k] · .mset-seg[data-v] · .mset-off · .mset-tgl
 * 期望值一律页内按原始字段现算（目标读数走独立算子，不走 mGoalRead；渲染层只给 data 属性供比）。
 * 用法：node --experimental-websocket tools/media_b8acheck.js    （截图：MB8A_SHOTS=1，落仓库外 tempWork） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index-media.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.MB8A_PORT || 9618);
const SHOTS = process.env.MB8A_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/media-b8a-shots';
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
  const r = m.result && m.result.result; try { return JSON.parse(r.value) } catch (e) { return { __err: (r && r.value) || JSON.stringify(m).slice(0, 260) } }
}
async function shot(name) { if (!SHOTS) return; fs.mkdirSync(SHOTDIR, { recursive: true });
  await wait(450);
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }
/* 页内独立算子：目标六行读数按原始列现算（与 mGoalRead 不同源；时间口径恒吃真实 min） */
const RAW = `var T=new Date(2026,9,9),S=mAllSess(),WSx=(function(){var d=new Date(T.getFullYear(),T.getMonth(),T.getDate()),wd=(d.getDay()+6)%7;d.setDate(d.getDate()-wd);return d})();
  function dOf(s){var p=String(s.dt).split('-');return new Date(+(s.yr||2026),+p[0]-1,+p[1])}
  function kindOf(s){return s.kind||(MDEMO.find(function(x){return x.id===s.itemId})||{}).kind||''}
  function dayEq(a,b){return a.getFullYear()===b.getFullYear()&&a.getMonth()===b.getMonth()&&a.getDate()===b.getDate()}
  var EXP={
    movieMin:S.filter(function(s){return ['movie','series'].indexOf(kindOf(s))>=0&&dayEq(dOf(s),T)}).reduce(function(t,s){return t+(+s.min||0)},0),
    musicH:S.filter(function(s){return kindOf(s)==='music'&&dOf(s)>=WSx}).reduce(function(t,s){return t+(+s.min||0)},0)/60,
    gameH:S.filter(function(s){return kindOf(s)==='game'&&dOf(s).getFullYear()===T.getFullYear()&&dOf(s).getMonth()===T.getMonth()}).reduce(function(t,s){return t+(+s.min||0)},0)/60,
    doneN:MDEMO.filter(function(x){return ['看完','追完','通关'].indexOf(x.state)>=0&&String(x.endedAt||'').slice(0,4)==='2026'}).length,
    dayN:Array.from(new Set(S.filter(function(s){return dOf(s)>=WSx}).map(function(s){return s.dt+'|'+(s.yr||2026)}))).length,
    sceneN:MNOTES.filter(function(n){return n.type==='scene'&&!n.gone&&new Date(n.created).getFullYear()===2026&&new Date(n.created).getMonth()===9}).length};`;
const GT = k => `document.querySelector('[data-mgread="' + k + '"]').textContent`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.media8a-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => { const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 260)) });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF });
  /* 内联脚本排在 Tailwind CDN 之后：轮询到本批全局在场再用，勿改固定 sleep（批7 实锤坑） */
  for (let i = 0; i < 30; i++) { const r = await ev(`return (typeof navTo==='function')&&(typeof mRenderGoal==='function')&&(typeof MSET!=='undefined')&&(typeof MGOALS!=='undefined')`); if (r === true) break; await wait(700) }

  /* A0 不回归：架面与统计照旧 */
  const a0 = await ev(`navTab('m-shelf');mSetView('desk');
    return {cards:document.querySelectorAll('#mShelfBody .mds-item').length,heat:document.querySelectorAll('#mHeat .mheatcell').length};`);
  const a0b = await ev(`navTo('m-stat');return document.querySelectorAll('#mHeat .mheatcell').length;`);
  (a0.cards >= 8 && a0b === 30) ? ok('A0 架面实物卡与统计热力不回归（' + a0.cards + ' 张 · 30 格）') : bad('A0', JSON.stringify(a0) + '/' + a0b);

  /* A1 目标屏＝固定六行且行序照拍板 */
  const a1 = await ev(`navTab('m-goal');
    return [].map.call(document.querySelectorAll('#mGoalBody .mgrow'),function(r){return r.dataset.mg}).join(',');`);
  (a1 === 'movieMin,musicH,gameH,doneN,dayN,sceneN') ? ok('A1 六行行序＝每日观影·每周听歌·每月游玩·每年看完·每周影音天数·每月名场面') : bad('A1', JSON.stringify(a1));

  /* A2 未设态＝六枚虚线入口、屏内零百分比、无旧「待批实现」自注 */
  const a2 = await ev(`var b=document.getElementById('mGoalBody');
    return {unset:document.querySelectorAll('#mGoalBody [data-mgunset]').length,pct:(b.textContent.match(/%/g)||[]).length,old:/待批实现/.test(b.textContent)};`);
  (a2.unset === 6 && a2.pct === 0 && !a2.old) ? ok('A2 未设目标＝虚线入口六枚齐、屏内零百分比、占位自注已摘') : bad('A2', JSON.stringify(a2));
  await shot('mb8a-01-goal-unset');

  /* A3 时长三路读数＝原始列现算（真实时长口径，独立算子） */
  const a3 = await ev(RAW + `var get=function(k){return document.querySelector('[data-mgread="'+k+'"]').textContent.replace(/[^0-9.]/g,'')};
    return {mv:+get('movieMin')===EXP.movieMin||Math.abs(+get('movieMin')-EXP.movieMin)<0.01,
      mu:Math.abs(+get('musicH')-(Math.round(EXP.musicH*10)/10))<0.051,
      gm:Math.abs(+get('gameH')-(Math.round(EXP.gameH*10)/10))<0.051,raw:EXP};`);
  (a3.mv && a3.mu && a3.gm) ? ok('A3 观影分钟/听歌小时/游玩小时＝按日·周一起·月三窗现算对上（' + a3.raw.movieMin + 'min/' + a3.raw.musicH.toFixed(1) + 'h/' + a3.raw.gameH.toFixed(1) + 'h）') : bad('A3', JSON.stringify(a3));

  /* A4 计数三路读数＝完结档本年·本周去重日·本月名场面 */
  const a4 = await ev(RAW + `var get=function(k){return +document.querySelector('[data-mgread="'+k+'"]').textContent.replace(/[^0-9.]/g,'')};
    return {done:get('doneN'),day:get('dayN'),scene:get('sceneN'),exp:[EXP.doneN,EXP.dayN,EXP.sceneN]};`);
  (a4.done === a4.exp[0] && a4.day === a4.exp[1] && a4.scene === a4.exp[2]) ? ok('A4 看完数/影音天数/名场面条数＝三计数口径现算对上（' + a4.exp.join('/') + '）') : bad('A4', JSON.stringify(a4));

  /* A5 点行＝就地展开单列滚轮（无二次弹层） */
  const a5 = await ev(`document.querySelector('[data-mg="movieMin"]').click();
    var w=document.querySelector('[data-mgwheel="movieMin"]');
    return {wheel:!!w,box:w?w.querySelectorAll('.wheelbox').length:0,clearBtn:w?w.textContent.indexOf('不设目标')>=0:false,sheets:document.querySelectorAll('.sheet:not(.hidden)').length};`);
  (a5.wheel && a5.box === 1 && a5.clearBtn && a5.sheets === 0) ? ok('A5 点行就地出单列滚轮＋「不设目标」钮，零弹层') : bad('A5', JSON.stringify(a5));
  await shot('mb8a-02-goal-wheel');

  /* A6 滚轮吸中即落目标：data-mgt＝所选值、百分比当场出现 */
  const a6 = await ev(`var w=WHEELS['mgW_movieMin'];
    w._bx.scrollTop=(Math.floor(w._rep/2)*w.items.length+7)*32;commitW('mgW_movieMin');
    var t=document.querySelector('[data-mgt="movieMin"]');
    return {txt:t?t.textContent:'',expect:w.items[7]};`);
  (a6.txt === a6.expect + ' min') ? ok('A6 滚轮选定＝目标落行（' + a6.txt + '）') : bad('A6', JSON.stringify(a6));

  /* A7 进度条宽度＝pct（读数/目标现算，封顶 100） */
  const a7 = await ev(RAW + `var rd=EXP.movieMin,tg=+MGOALS.find(function(g){return g.k==='movieMin'}).target;
    var pct=Math.min(100,Math.round(rd/tg*100));
    var bar=document.querySelector('[data-mgbar="movieMin"] div');
    var lab=document.querySelector('[data-mgpct="movieMin"]').textContent;
    return {w:bar?bar.style.width:'',lab:lab,pct:pct};`);
  (a7.w === a7.pct + '%' && a7.lab.indexOf(a7.pct + '%') >= 0) ? ok('A7 进度条宽与行内百分比＝同一现算值（' + a7.pct + '%）') : bad('A7', JSON.stringify(a7));
  await shot('mb8a-03-goal-set');

  /* A8 再点行收起滚轮；重开点「不设目标」＝回未设（屏内百分比归零） */
  const a8 = await ev(`document.querySelector('[data-mg="movieMin"]').click();
    var closed=!document.querySelector('[data-mgwheel="movieMin"]');
    document.querySelector('[data-mg="movieMin"]').click();
    document.querySelector('[data-mgwheel="movieMin"] button').click();
    var b=document.getElementById('mGoalBody');
    return {closed:closed,unset:document.querySelectorAll('[data-mgunset="movieMin"]').length,pct:(b.textContent.match(/%/g)||[]).length};`);
  (a8.closed && a8.unset === 1 && a8.pct === 0) ? ok('A8 再点收起·「不设目标」清档＝回虚线态') : bad('A8', JSON.stringify(a8));

  /* A9 与统计屏目标块同源联动：设一条→统计出该块行；清档→回虚线空态 */
  const a9 = await ev(RAW + `mGoalPick('movieMin',60);navTo('m-stat');
    var row=document.querySelector('[data-mgoal="movieMin"]');
    var txt=row?row.textContent:'';var exp=Math.min(100,Math.round(EXP.movieMin/60*100));
    var hasExp=txt.indexOf(exp+'%')>=0;
    mGoalPick('movieMin',0);mRenderStat();
    var back=document.querySelector('#mStatGoal .mempty')?document.querySelector('#mStatGoal .mempty').textContent:'';
    return {hasRow:!!row&&hasExp,empty:/未设目标/.test(back),entry:!!document.querySelector('#mStatGoal .mentry')};`);
  (a9.hasRow && a9.empty && a9.entry) ? ok('A9 目标与统计屏目标块同源：设了同帧出百分比、清了回虚线（入口行恒在）') : bad('A9', JSON.stringify(a9));
  await ev(`mGoalPick('movieMin',60);mGoalPick('gameH',20);mRenderStat();navTo('m-stat');var el=document.getElementById('m-stat');el.scrollTop=el.scrollHeight;return 1;`); await shot('mb8a-06-stat-goalrows');
  await ev(`var el=document.getElementById('m-stat');el.scrollTop=0;return 1;`);
  await ev(`mGoalPick('movieMin',0);mGoalPick('gameH',0);return 1;`);

  /* A10 目标读数恒吃真实：统计屏切「折算时长」后目标块文本不动 */
  const a10 = await ev(RAW + `mGoalPick('movieMin',60);mRenderStat();
    var t1=document.querySelector('[data-mgoal="movieMin"]').textContent;
    document.querySelector('#mStatFoldChips [data-v="fold"]').click();
    var t2=document.querySelector('[data-mgoal="movieMin"]').textContent;
    document.querySelector('#mStatFoldChips [data-v="real"]').click();
    mGoalPick('movieMin',0);
    return {same:t1===t2,real:t1};`);
  a10.same ? ok('A10 折算开关不改变目标读数（账本口径＝真实，两态同文）') : bad('A10', JSON.stringify(a10));

  /* A11 设置屏六组 tab 与架面组行结构 */
  const a11 = await ev(`navTo('m-set');
    var tabs=[].map.call(document.querySelectorAll('.mset-tab'),function(t){return t.dataset.t}).join(',');
    var r=document.querySelectorAll('#mSetBody .mset-row').length;
    var dv=document.querySelectorAll('[data-k="defaultView"] .mset-seg').length;
    var wc=document.querySelectorAll('[data-k="wallCols"] .mset-seg').length;
    return {tabs:tabs,rows:r,dv:dv,wc:wc};`);
  (a11.tabs === 'shelf,sort,note,timer,notify,data' && a11.rows === 2 && a11.dv === 3 && a11.wc === 2) ? ok('A11 设置屏＝六组 tab 序对，架面组＝默认视图三档＋列数两档') : bad('A11', JSON.stringify(a11));
  await shot('mb8a-04-set-shelf');

  /* A12 更新提醒三行灰态：点行点钮都不落值（假开关不铺） */
  const a12 = await ev(`document.querySelector('.mset-tab[data-t="notify"]').click();
    var rows=[].slice.call(document.querySelectorAll('#mSetBody .mset-row'));
    var n1=rows.filter(function(r){return r.classList.contains('mset-off')}).length;
    rows[0].click();rows[0].querySelector('.toggle').click();
    return {off:n1,keys:['notifyNewEpisode','notifyNewAlbum','notifySequel'].map(function(k){return typeof MSET[k]}).join(','),
      onCls:rows[0].querySelector('.toggle').classList.contains('on')};`);
  (a12.off === 3 && a12.keys === 'undefined,undefined,undefined' && !a12.onCls) ? ok('A12 三行灰态齐·点动零写入（无假开关）') : bad('A12', JSON.stringify(a12));
  await shot('mb8a-07-set-notify-gray');

  /* A13 笔记组：识图整行灰（能力未装），两枚真开关可拨 */
  const a13 = await ev(`document.querySelector('.mset-tab[data-t="note"]').click();
    var o=document.querySelector('[data-k="ocr"]');var ap=document.querySelector('[data-k="autoPos"]');
    o.click();
    var before=MSET.autoPos;ap.querySelector('.toggle').click();
    return {ocrOff:o.classList.contains('mset-off'),ocrState:MSET.ocr,flipped:(before!==MSET.autoPos)};`);
  (a13.ocrOff && a13.ocrState === true && a13.flipped) ? ok('A13 识图灰态照旧（点不动）·默认带时间点可拨') : bad('A13', JSON.stringify(a13));
  await ev(`document.querySelector('[data-k="autoPos"] .toggle').click();return 1;`);

  /* A14 speedFold 双向同源：设置拨→统计 chip 折算亮；统计拨回→设置行灭 */
  const a14 = await ev(`document.querySelector('.mset-tab[data-t="timer"]').click();
    var tg=document.querySelector('[data-k="speedFold"] .toggle');tg.click();
    navTo('m-stat');
    var chipFold=document.querySelector('#mStatFoldChips [data-v="fold"]').classList.contains('on');
    document.querySelector('#mStatFoldChips [data-v="real"]').click();
    navTo('m-set');document.querySelector('.mset-tab[data-t="timer"]').click();
    var off=!document.querySelector('[data-k="speedFold"] .toggle').classList.contains('on');
    return {chipFold:chipFold,off:off,fold:MSET.speedFold};`);
  (a14.chipFold && a14.off && a14.fold === false) ? ok('A14 倍速折算＝一处拨两屏同档（双向同源，默认「真实」）') : bad('A14', JSON.stringify(a14));

  /* A15 桌面列数当场生效：架面网格内联轨道数跟着变 */
  const a15 = await ev(`navTo('m-set');document.querySelector('.mset-tab[data-t="shelf"]').click();
    document.querySelector('[data-k="wallCols"] [data-v="3"]').click();
    var st=(document.querySelector('#mShelfBody .mds-grid')||{style:{}}).style.gridTemplateColumns||'';
    var three=/repeat\\(3/.test(st);
    document.querySelector('[data-k="wallCols"] [data-v="2"]').click();
    var st2=(document.querySelector('#mShelfBody .mds-grid')||{style:{}}).style.gridTemplateColumns||'';
    return {three:three,two:/repeat\\(2/.test(st2)};`);
  (a15.three && a15.two) ? ok('A15 桌面列数切 3 当场重排、切回 2（内联轨道实读）') : bad('A15', JSON.stringify(a15));

  /* A16 默认视图：设「列表」→进架即列表；设回桌面 */
  const a16 = await ev(`document.querySelector('[data-k="defaultView"] [data-v="list"]').click();
    mOpenShelf();var v1=mCurView;
    navTo('m-set');document.querySelector('[data-k="defaultView"] [data-v="desk"]').click();
    mOpenShelf();return {list:v1,desk:mCurView,key:MSET.defaultView};`);
  (a16.list === 'list' && a16.desk === 'desk') ? ok('A16 默认视图设置＝进架落地档（list→desk 两态都对）') : bad('A16', JSON.stringify(a16));

  /* A17 默认排序＝评分：进架后在册卡按评分降序 */
  const a17 = await ev(`navTo('m-set');document.querySelector('.mset-tab[data-t="sort"]').click();
    document.querySelector('[data-k="sortDefault"] [data-v="rating"]').click();
    mOpenShelf();
    var ids=[].map.call(document.querySelectorAll('#mShelfBody .mds-item'),function(c){var m=(c.getAttribute('onclick')||'').match(/mOpen\\('([^']+)'\\)/);return m?m[1]:''}).filter(Boolean);
    var rs=ids.map(function(i){return (MDEMO.find(function(x){return x.id===i})||{}).rating||0});
    var badN=0;for(var k=1;k<rs.length;k++)if(rs[k]>rs[k-1]+1e-9)badN++;
    document.querySelector('#mSetTabs')&&0;navTo('m-set');document.querySelector('.mset-tab[data-t="sort"]').click();
    document.querySelector('[data-k="sortDefault"] [data-v="recent"]').click();
    return {n:rs.length,bad:badN};`);
  (a17.n >= 8 && a17.bad === 0) ? ok('A17 默认排序「评分」＝架面卡序按 myRate 降序（' + a17.n + ' 张零逆序）') : bad('A17', JSON.stringify(a17));

  /* A18 计时形态「全屏」：详情计时钮直达 m-timer */
  const a18 = await ev(`navTo('m-set');document.querySelector('.mset-tab[data-t="timer"]').click();
    document.querySelector('[data-k="timerUI"] [data-v="full"]').click();
    mOpen('mv1');document.querySelector('#mdsDetailTimerBtn').click();
    return {p:curPage,on:mTimerOn?mTimerOn.id:''};`);
  (a18.p === 'm-timer' && a18.on === 'mv1') ? ok('A18 全屏档＝计时钮直达沉浸计时页并起会话') : bad('A18', JSON.stringify(a18));

  /* A19 胶囊档＋悬浮条：起计时出 mds 悬浮条（文案按 kind），floatBar 关＝藏、开＝复显 */
  const a19 = await ev(`mTimerEnd();closeSheet('m-sheet-progress');
    navTo('m-set');document.querySelector('.mset-tab[data-t="timer"]').click();
    document.querySelector('[data-k="timerUI"] [data-v="capsule"]').click();
    navTo('m-detail');mRenderDetail();
    document.querySelector('#mdsDetailTimerBtn').click();
    var bar=document.getElementById('mdsTimerBar');
    var shown=!bar.classList.contains('hidden')&&bar.classList.contains('flex');
    document.querySelector('[data-k="floatBar"] .toggle').click();
    var hid=bar.classList.contains('hidden');
    document.querySelector('[data-k="floatBar"] .toggle').click();
    var back=!bar.classList.contains('hidden');
    return {shown:shown,txt:bar.textContent,hid:hid,back:back};`);
  (a19.shown && /观影中/.test(a19.txt) && /沙丘/.test(a19.txt) && a19.hid && a19.back) ? ok('A19 胶囊档＝悬浮条出「观影中·沙丘 2」；悬浮条开关藏/复显即时') : bad('A19', JSON.stringify(a19));
  await shot('mb8a-05-timerbar');

  /* A20 autoAsk：结束计时弹记进度（开）／不弹（关）；点悬浮条即结束 */
  const a20 = await ev(`document.getElementById('mdsTimerBar').click();
    var opened=document.getElementById('m-sheet-progress')&&!document.getElementById('m-sheet-progress').classList.contains('hidden');
    closeSheet('m-sheet-progress');
    navTo('m-set');document.querySelector('.mset-tab[data-t="timer"]').click();
    document.querySelector('[data-k="autoAsk"] .toggle').click();
    navTo('m-detail');mRenderDetail();document.querySelector('#mdsDetailTimerBtn').click();
    mTimerEnd();
    var quiet=document.getElementById('m-sheet-progress').classList.contains('hidden');
    navTo('m-set');document.querySelector('[data-k="autoAsk"] .toggle').click();
    return {opened:opened,quiet:quiet};`);
  (a20.opened && a20.quiet) ? ok('A20 结束即弹记进度随开关两态正确（关＝只收条不弹层）') : bad('A20', JSON.stringify(a20));

  /* A21 笔记弹层：clipAuto 控粘贴钮显隐；autoPos 预填该条最近计时终点（现算比对） */
  const a21 = await ev(`var ls=MSESS.filter(function(s){return s.itemId==='mv2'}).slice().sort(function(p,q){return String(q.dt).localeCompare(String(p.dt))||String(q.id).localeCompare(String(p.id))});
    var want=(ls.length&&ls[ls.length-1].p1)||'';
    var atEl=document.getElementById('mdNoteAt');if(atEl)atEl.value='';
    mOpenNoteEdit('mv2');
    var at=document.getElementById('mdNoteAt').value;
    navTo('m-set');document.querySelector('.mset-tab[data-t="note"]').click();
    document.querySelector('[data-k="clipAuto"] .toggle').click();
    mOpenNoteEdit('mv2');
    var hid=document.getElementById('mdNotePasteBtn').classList.contains('hidden');
    document.querySelector('[data-k="clipAuto"] .toggle').click();
    mOpenNoteEdit('mv2');var shownBack=!document.getElementById('mdNotePasteBtn').classList.contains('hidden');
    closeSheet('m-sheet-note-edit');
    return {at:at,want:want,hid:hid,shownBack:shownBack};`);
  (a21.at === a21.want && a21.want && a21.hid && a21.shownBack) ? ok('A21 时间点预填＝mv2 最近流水终点（' + a21.want + '）；剪贴板识别关＝粘贴钮藏、开复现') : bad('A21', JSON.stringify(a21));

  /* A22 新增插入位：置顶（默认）→新建在首；置底→新建在尾（用后即删演示条目） */
  const a22 = await ev(`openSheet('m-sheet-add');document.getElementById('mdsAddTitle').value='闸验证甲';mAddSave();
    var head=MDEMO[0].title==='闸验证甲';
    navTo('m-set');document.querySelector('.mset-tab[data-t="sort"]').click();
    document.querySelector('[data-k="newPos"] [data-v="tail"]').click();
    openSheet('m-sheet-add');document.getElementById('mdsAddTitle').value='闸验证乙';mAddSave();
    var tail=MDEMO[MDEMO.length-1].title==='闸验证乙';
    MDEMO=MDEMO.filter(function(x){return ['闸验证甲','闸验证乙'].indexOf(x.title)<0});
    document.querySelector('[data-k="newPos"] [data-v="head"]').click();
    navTo('m-set');return {head:head,tail:tail,n:MDEMO.length};`);
  (a22.head && a22.tail) ? ok('A22 新增插入位两档＝首/尾落位对，演示条目已清') : bad('A22', JSON.stringify(a22));

  /* A23 数据组：导入向导＝真直达；两枚导出灰态（随导出批再接） */
  const a23 = await ev(`navTo('m-set');document.querySelector('.mset-tab[data-t="data"]').click();
    var offs=[].slice.call(document.querySelectorAll('#mSetBody .mset-row')).filter(function(r){return r.classList.contains('mset-off')}).map(function(r){return r.dataset.k}).join(',');
    document.querySelector('[data-k="goImport"]').click();
    return {offs:offs,p:curPage};`);
  (a23.offs === 'expMd,expJson' && a23.p === 'm-import') ? ok('A23 数据组＝导出两枚灰态＋导入直达真跳') : bad('A23', JSON.stringify(a23));

  /* A24 两面段内零 emoji、零「演示」字样、零「待批实现」（AGENTS 禁令） */
  const a24 = await ev(`var h=document.getElementById('m-goal').outerHTML+document.getElementById('m-set').outerHTML+document.getElementById('mdsTimerBar').outerHTML;
    var re=[/[\\u{1F300}-\\u{1FAFF}]/u,/[\\u{2600}-\\u{27BF}]/u,/[\\u{2B00}-\\u{2B5F}]/u,/\\u{FE0F}/u];
    return {hit:re.filter(function(r){return r.test(h)}).length,demo:(h.match(/演示/g)||[]).length,old:/待批实现/.test(h)};`);
  (a24.hit === 0 && a24.demo === 0 && !a24.old) ? ok('A24 目标屏＋设置屏＋悬浮条段：emoji/演示/待批实现 全 0') : bad('A24', JSON.stringify(a24));

  /* A25 同态重渲染逐字节等（目标与设置两面确定性） */
  const a25 = await ev(`navTo('m-goal');mRenderGoal();var a=document.getElementById('mGoalBody').innerHTML;mRenderGoal();
    navTo('m-set');mRenderSet();var c=document.getElementById('mSetBody').innerHTML;mRenderSet();
    return {g:a===document.getElementById('mGoalBody').innerHTML,s:c===document.getElementById('mSetBody').innerHTML};`);
  (a25.g && a25.s) ? ok('A25 两面同态重渲染逐字节等（无随机）') : bad('A25', JSON.stringify(a25));

  log('PAGE ERRORS ' + errs.length + (errs.length ? ' :: ' + errs.join(' || ') : ''));
  finish();
})().catch(e => { bad('runner', String(e && e.message || e)); if (errs.length) log('PAGE ERRORS ' + errs.length + ' :: ' + errs.join(' || ')); finish() });

function finish() { try { ws && ws.close() } catch (e) { } try { chrome && chrome.kill() } catch (e) { }
  log('RESULT ' + pass + '/' + (pass + fail) + ' 绿 · fail=' + fail + ' · PAGE ERRORS ' + errs.length);
  process.exit(fail || errs.length ? 1 : 0) }
