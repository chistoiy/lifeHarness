/* media_b7check.js · 影音游批7 原型先行两面的无头回归（m-stat 全站统计 · m-sheet-track 单条目轨迹）
 * 口径依据＝docs/handoff/交棒话术-20261009-影音游批7统计屏与条目轨迹原型.md §0 四项拍板
 *   （屏内真实/折算切换＝media.speedFold 可见表达 · 热力＝色块＋四档强度点格出读数 ·
 *    年×月×度量×构成＝屏内四行筛选条 · 轨迹＝半屏只读）
 * 标记类（供确定性取值）：.mstat-chip 筛选钮 · .mheatcell 热力格 · .mdayread 当日读数 · .mtrendbar 趋势柱 ·
 *   .mkindrow 构成行 · .mhourbar 时段行 · .mtotalchip 总时长章 · .mtrackcol 逐次柱 · .mmile 里程碑 · .mempty 空态
 * 期望值一律在页内按原始数据现算（不写死读数），且不借渲染函数同源。
 * 用法：node --experimental-websocket tools/media_b7check.js      （截图：MB7_SHOTS=1，落仓库外 tempWork） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index-media.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.MB7_PORT || 9617);
const SHOTS = process.env.MB7_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/media-b7-shots';
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
  await wait(450);   /* .page.active 有 .22s slideIn（含透明度），不等就是拍在退场动画上 */
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }
const STXT = "document.getElementById('m-stat').textContent.replace(/\\s+/g,'')";
/* 页内独立算子：与渲染层不同源，直接吃 MSESS/MHIST 原始列 */
const RAW = `var S=mAllSess(),K=function(s){return s.kind||(MDEMO.find(function(x){return x.id===s.itemId})||{}).kind||''},
  HM=function(m){m=Math.max(0,Math.round(m)||0);var h=Math.floor(m/60),r=m%60;return h?(r?h+'h '+r+'m':h+'h'):r+'m'},
  FOLD=function(s){return Math.round((+s.min||0)*((+s.speed||1)>1?+s.speed:1))},
  REAL=function(s){return +s.min||0},
  YMD=function(s){var p=String(s.dt).split('-');return{y:+(s.yr||2026),m:+p[0],d:+p[1]}};`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.media7-profile'), '--disable-extensions', '--no-default-browser-check',
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
  /* 内联脚本排在 Tailwind CDN 之后，CDN 未回（本机断网）前整段 DOM 都没解析：轮询到全局函数在场再用，勿改成固定 sleep */
  for (let i = 0; i < 30; i++) { const r = await ev(`return typeof navTo`); if (r === 'function') break; await wait(700) }

  /* A0 架面与明细不回归（本批动过详情动作条与操作弹层） */
  const a0 = await ev(`navTab('m-shelf');mSetView('desk');
    return {cards:document.querySelectorAll('#mShelfBody .mds-item').length,sess:mSessOf('mv1').length};`);
  (a0.cards >= 8 && a0.sess >= 2) ? ok('A0 影音架与计时流水照旧（' + a0.cards + ' 张实物卡 · mv1 ' + a0.sess + ' 条）') : bad('A0', JSON.stringify(a0));

  /* A1 统计屏八块齐 */
  const a1 = await ev(`navTo('m-stat');var ids=['mStatFoldChips','mStatDrill','mHeat','mStatTrend','mKindPie','mStatHours','mStatRating','mStatGoal','mTotals'];
    return {p:curPage,full:ids.filter(function(i){var e=document.getElementById(i);return e&&e.innerHTML.replace(/\\s+/g,'').length>0}).length,
      lbl:['年','月','度量','构成'].filter(function(k){return [].some.call(document.querySelectorAll('.mstat-lbl'),function(s){return s.textContent===k})}).length};`);
  (a1.p === 'm-stat' && a1.full === 9 && a1.lbl === 4) ? ok('A1 统计屏＝口径 chip＋四行钻取＋八块读数全在场') : bad('A1', JSON.stringify(a1));
  await shot('mb7-01-stat-default');
  await ev(`document.getElementById('m-stat').scrollTop=9999;return 1;`); await shot('mb7-11-stat-bottom');
  await ev(`document.getElementById('m-stat').scrollTop=0;return 1;`);

  /* A2 确定性：同态两次渲染逐字节等（演示数据无 Math.random） */
  const a2 = await ev(`mStatReset();var a=document.getElementById('mHeat').innerHTML;mRenderStatHeat();
    return {same:a===document.getElementById('mHeat').innerHTML,n:document.querySelectorAll('#mHeat .mheatcell').length};`);
  (a2.same && a2.n === 30) ? ok('A2 近 30 天＝30 格且同态重渲染逐字节等（无随机）') : bad('A2', JSON.stringify(a2));

  /* A3 每格读数＝按原始数据现算（30 格逐格比） */
  const a3 = await ev(RAW + `var bad=0;[].forEach.call(document.querySelectorAll('#mHeat .mheatcell'),function(c){
    var k=c.dataset.d,y=+k.slice(0,4),md=k.slice(5).split('-'),dt=md[0]+'-'+md[1];
    var rows=S.filter(function(s){return s.dt===dt&&YMD(s).y===y});
    var v=rows.reduce(function(t,s){return t+REAL(s)},0);
    if(Math.abs((+c.dataset.v)-v)>0.51)bad++;});
    return {bad:bad,cells:document.querySelectorAll('#mHeat .mheatcell').length};`);
  a3.bad === 0 ? ok('A3 热力格 data-v＝逐日时长现算（30 格 0 处对不上）') : bad('A3', JSON.stringify(a3));

  /* A4 空档日＝虚线空格；有记录日按主导 kind 上色 */
  const a4 = await ev(`var cs=[].slice.call(document.querySelectorAll('#mHeat .mheatcell'));
    return {none:cs.filter(function(c){return c.classList.contains('k-none')}).length,
      kinded:cs.filter(function(c){return /k-(movie|series|music|game)/.test(c.className)}).length,
      plain:cs.filter(function(c){return +c.dataset.v>0&&!/k-(movie|series|music|game)/.test(c.className)}).length};`);
  (a4.none > 0 && a4.kinded > 0 && a4.plain === 0) ? ok('A4 空档日出虚线格 · 有记录日必带主导 kind 色（空格 ' + a4.none + ' / 实格 ' + a4.kinded + '）') : bad('A4', JSON.stringify(a4));

  /* A5 强度分档单调：d3 的最小值 ≥ d1 的最大值 */
  const a5 = await ev(`var cs=[].slice.call(document.querySelectorAll('#mHeat .mheatcell'));
    function mx(d){var v=cs.filter(function(c){return c.classList.contains('d'+d)}).map(function(c){return +c.dataset.v});return{min:Math.min.apply(null,v.concat([1e15])),max:Math.max.apply(null,v.concat([-1]))}}
    return {lv:[1,2,3].filter(function(d){return cs.some(function(c){return c.classList.contains('d'+d)})}).length,d1:mx(1),d2:mx(2),d3:mx(3)};`);
  (a5.lv === 3 && a5.d3.min >= a5.d1.max && a5.d2.min >= a5.d1.max) ? ok('A5 强度三档在场且分档单调（d1 顶 ' + a5.d1.max + ' ≤ d2 底 ' + a5.d2.min + ' ≤ d3 底 ' + a5.d3.min + '）') : bad('A5', JSON.stringify(a5));

  /* A6 点格＝当日读数行；空格出「没记录」；再点收起 */
  const a6 = await ev(`var cs=[].slice.call(document.querySelectorAll('#mHeat .mheatcell'));
    var hit=cs.filter(function(c){return +c.dataset.v>0})[1];hit.click();
    var rd=document.querySelector('#mStatDay .mdayread'),t1=rd?rd.textContent:'';
    var gap=cs.filter(function(c){return c.classList.contains('k-none')})[0];gap.click();
    var em=document.querySelector('#mStatDay .mempty'),t2=em?em.textContent:'';
    em&&0;var before=document.querySelectorAll('#mStatDay .mempty').length;gap.click();
    return {t1:t1,t2:t2,left:document.querySelectorAll('#mStatDay .mempty').length,sel:document.querySelectorAll('#mHeat .sel').length};`);
  (/[0-9]{2}-[0-9]{2}/.test(a6.t1) && /没记录/.test(a6.t2) && a6.left === 0 && a6.sel === 0) ? ok('A6 点格出当日读数·点空格出「没记录」·再点收起', (a6.t1 || '').replace(/\s+/g, '').slice(0, 40)) : bad('A6', JSON.stringify(a6));
  await ev(`var c=[].slice.call(document.querySelectorAll('#mHeat .mheatcell')).filter(function(x){return +x.dataset.v>0})[1];c.click();return 1;`); await shot('mb7-02-stat-dayread');

  /* A7 口径切换＝折算整体变大且等于逐条 speed 现算 */
  const a7 = await ev(RAW + `var tot=function(f){return S.reduce(function(t,s){return t+(f?FOLD(s):REAL(s))},0)};
    var real=document.querySelector('#mTotals .mds-chip[data-k="total"]').textContent;
    document.querySelector('#mStatFoldChips [data-v="fold"]').click();
    var fold=document.querySelector('#mTotals .mds-chip[data-k="total"]').textContent;
    var heatT=document.getElementById('mStatHeatTitle').textContent;
    return {real:real,fold:fold,expect:HM(tot(false))+'/'+HM(tot(true)),bigger:tot(true)>tot(false),heatT:heatT};`);
  (a7.expect.split('/')[0] === a7.real.replace(/^\S+ /, '') && a7.expect.split('/')[1] === a7.fold.replace(/^\S+ /, '') && a7.bigger && /折算/.test(a7.heatT))
    ? ok('A7 切「折算时长」＝逐条按倍速现算并整体变大（' + a7.real + ' → ' + a7.fold + '）') : bad('A7', JSON.stringify(a7));
  await shot('mb7-03-stat-fold');

  /* A8 构成筛选＝只剩该 kind（热力·构成·总时长三处同帧） */
  const a8 = await ev(`document.querySelector('#mStatFoldChips [data-v="real"]').click();
    document.querySelector('#mStatKindChips [data-v="movie"]').click();
    var cs=[].slice.call(document.querySelectorAll('#mHeat .mheatcell'));
    return {kinds:document.querySelectorAll('#mKindPie .mkindrow').length,kind1:(document.querySelector('#mKindPie .mkindrow')||{}).dataset,
      tot:document.querySelectorAll('#mTotals .mtotalchip').length,
      otherKind:cs.filter(function(c){return /k-(series|music|game)/.test(c.className)}).length,
      pieTxt:(document.querySelector('#mKindPie .mkindrow-v')||{}).textContent};`);
  (a8.kinds === 1 && a8.kind1 && a8.kind1.k === 'movie' && a8.tot === 2 && a8.otherKind === 0)
    ? ok('A8 构成选「电影」＝构成只剩一行 · 总时长只剩观影＋总计 · 热力不再出现他类色') : bad('A8', JSON.stringify(a8));
  await shot('mb7-06-stat-kind-movie');

  /* A9 度量三档各换纵轴语义 */
  const a9 = await ev(`document.querySelector('#mStatKindChips [data-v="all"]').click();
    var o={};document.querySelector('#mStatMetricChips [data-v="cnt"]').click();
    o.cnt=[].slice.call(document.querySelectorAll('#mTotals,#mKindPie')).length&&document.querySelector('#mKindPie .mkindrow-v').textContent;
    document.querySelector('#mStatMetricChips [data-v="rate"]').click();
    o.rate=document.querySelector('#mKindPie .mkindrow-v').textContent;
    document.querySelector('#mStatMetricChips [data-v="min"]').click();
    o.min=document.querySelector('#mKindPie .mkindrow-v').textContent;return o;`);
  (/次 · \d+%/.test(a9.cnt) && /^[0-9]+\.[0-9] · /.test(a9.rate) && /(h|m) · \d+%/.test(a9.min)) ? ok('A9 度量三档＝时长/次数/平均评分各自口径（' + a9.cnt + ' · ' + a9.rate + '）') : bad('A9', JSON.stringify(a9));
  await ev(`document.querySelector('#mStatMetricChips [data-v="rate"]').click();return 1;`); await shot('mb7-07-stat-metric-rate');
  await ev(`document.querySelector('#mStatMetricChips [data-v="min"]').click();return 1;`);

  /* A10 年×月钻取＝读数随窗口重算；无记录月走空态、该月柱不出读数 */
  const a10 = await ev(RAW + `document.querySelector('#mStatYearChips [data-v="2026"]').click();
    var anyM=[].slice.call(document.querySelectorAll('#mStatMonthChips .mstat-chip')).filter(function(b){return +b.dataset.v>0})
      .map(function(b){return +b.dataset.v}).filter(function(m){return S.some(function(s){var y=YMD(s);return y.y===2026&&y.m===m})})[3];
    document.querySelector('#mStatMonthChips [data-v="'+anyM+'"]').click();
    var exp=S.filter(function(s){var y=YMD(s);return y.y===2026&&y.m===anyM}).reduce(function(t,s){return t+REAL(s)},0);
    var got=document.querySelector('#mTotals .mtotalchip[data-k="total"]').textContent;
    var trendBars=document.querySelectorAll('#mStatTrend .mtrendbar').length;
    document.querySelector('#mStatYearChips [data-v="2025"]').click();
    var m5=[].slice.call(document.querySelectorAll('#mStatMonthChips .mstat-chip')).filter(function(b){return +b.dataset.v===5})[0];m5.click();
    var emptyPie=!!document.querySelector('#mKindPie .mempty');
    var bar5=document.querySelector('#mStatTrend .mtrendbar[data-m="05"]');
    var monthsWithData2025=new Set(S.filter(function(s){return YMD(s).y===2025}).map(function(s){return YMD(s).m})).size;
    var zeroCount=document.querySelectorAll('#mStatTrend .mtrend-zero').length;
    document.querySelector('#mStatYearChips [data-v="all"]').click();document.querySelector('#mStatMonthChips [data-v="0"]').click();
    return {month:anyM,exp:HM(exp),got:got,trendBars:trendBars,emptyPie:emptyPie,bar5zero:bar5&&bar5.classList.contains('mtrend-zero'),
      zeroCount:zeroCount,expectZero:12-monthsWithData2025};`);
  (a10.got.indexOf(a10.exp) >= 0 && a10.trendBars === 12 && a10.emptyPie && a10.bar5zero && a10.zeroCount === a10.expectZero)
    ? ok('A10 年×月窗口＝总时长与现算等 · 趋势恒 12 根 · 无记录月出空态与该月零柱（不编数）') : bad('A10', JSON.stringify(a10));

  /* A11 趋势零值柱不带读数（有记录月才出数值） */
  const a11 = await ev(`document.querySelector('#mStatYearChips [data-v="2026"]').click();
    var z=[].slice.call(document.querySelectorAll('#mStatTrend .mtrend-zero'));
    var v=[].slice.call(document.querySelectorAll('#mStatTrend .mtrendbar[data-v]'));
    var mono=v.map(function(b){return +b.dataset.v}).sort(function(a,b){return a-b});
    document.querySelector('#mStatYearChips [data-v="all"]').click();
    return {zero:z.length,withVal:v.length,allPos:mono.every(function(x){return x>0})};`);
  (a11.withVal > 0 && a11.allPos && a11.zero + a11.withVal === 12) ? ok('A11 趋势＝有记录月出数值、无记录月只出虚线底（' + a11.withVal + ' 根有读数）') : bad('A11', JSON.stringify(a11));

  /* A12 时段分布五档齐·无记录档出「—」 */
  const a12 = await ev(RAW + `var rows=[].slice.call(document.querySelectorAll('#mStatHours .mhourbar'));
    var labels=rows.map(function(r){return r.dataset.h});
    var em=rows.filter(function(r){return /—/.test(r.querySelector('.mhour-v').textContent)}).length;
    var sum=S.filter(function(s){var h=parseInt(String(s.from||'').split(':')[0],10);return isNaN(h)||h>=21}).length;
    return {n:rows.length,labels:labels.join(','),em:em};`);
  (a12.n === 5 && a12.labels === 'dawn,am,pm,eve,night') ? ok('A12 时段五档齐（凌晨/上午/午后/傍晚/深夜），空档出「—」') : bad('A12', JSON.stringify(a12));

  /* A13 目标达成＝未设目标虚线＋入口，块内不出现百分比 */
  const a13 = await ev(`var t=document.getElementById('mStatGoal').textContent;
    return {empty:!!document.querySelector('#mStatGoal .mempty'),pct:/%.|％/.test(t),entry:!!document.querySelector('#mStatGoal .mentry'),txt:t.replace(/\\s+/g,'')};`);
  (a13.empty && !a13.pct && a13.entry) ? ok('A13 目标块＝「未设目标」虚线＋跳目标屏入口，无任何百分比') : bad('A13', JSON.stringify(a13));

  /* A14 均评卡＝窗口内有记录条目的 myRate 均值（现算比对） */
  const a14 = await ev(`var ids=Array.from(new Set(mAllSess().map(function(s){return s.itemId})));
    var rs=ids.map(function(i){return (MDEMO.find(function(x){return x.id===i})||{}).myRate}).filter(function(v){return typeof v==='number'&&v>0});
    var exp=(rs.reduce(function(a,b){return a+b},0)/rs.length).toFixed(1);
    return {exp:exp,got:document.getElementById('mStatRatingAvg').textContent,n:rs.length};`);
  a14.got === a14.exp ? ok('A14 均评卡＝' + a14.got + ' 分（' + a14.n + ' 部已评分条目均值，现算等值）') : bad('A14', JSON.stringify(a14));

  /* A15 重置钮＝四行筛选与口径回默认态 */
  const a15 = await ev(`document.querySelector('#mStatFoldChips [data-v="fold"]').click();document.querySelector('#mStatKindChips [data-v="game"]').click();
    document.querySelector('#mStatMetricChips [data-v="cnt"]').click();document.querySelector('#mStatYearChips [data-v="2026"]').click();
    document.getElementById('mStatResetBtn').click();
    var on=function(sel){var b=document.querySelector(sel+' .mstat-chip.on');return b?b.dataset.v:''};
    return {fold:on('#mStatFoldChips'),kind:on('#mStatKindChips'),metric:on('#mStatMetricChips'),year:on('#mStatYearChips'),month:on('#mStatMonthChips'),heatT:document.getElementById('mStatHeatTitle').textContent};`);
  (a15.fold === 'real' && a15.kind === 'all' && a15.metric === 'min' && a15.year === 'all' && a15.month === '0' && /时长热力 · 真实/.test(a15.heatT))
    ? ok('A15 右上重置＝口径/度量/构成/年月一次回默认态') : bad('A15', JSON.stringify(a15));

  /* A16 轨迹＝半屏弹层·逐次柱数与倍速角标随会话现算 */
  const a16 = await ev(`mOpen('mv1');var btn=document.getElementById('mdsTrackBtn');btn.click();
    var cols=[].slice.call(document.querySelectorAll('#mTrackBody .mtrackcol'));
    var spd=cols.filter(function(c){return c.querySelector('.mtrack-spd')}).length;
    var exp=mAllSess().filter(function(s){return s.itemId==='mv1'});
    var expSpd=exp.filter(function(s){return (+s.speed||1)>1}).length;
    return {sheetOpen:document.querySelectorAll('.sheet:not(.hidden)').length,id:document.querySelector('.sheet:not(.hidden)').id,
      cols:cols.length,expCols:Math.min(exp.length,14),spd:spd,expSpd:Math.min(expSpd,exp.length===exp.slice(-14).length?expSpd:0),
      asc:cols.map(function(c){return c.dataset.i}).join(','),title:document.getElementById('mTrackTitle').textContent};`);
  (a16.id === 'm-sheet-track' && a16.cols === a16.expCols && a16.spd > 0) ? ok('A16 轨迹＝半屏弹层 · 逐次柱 ' + a16.cols + ' 根（≤14） · 倍速 >1 才出角标') : bad('A16', JSON.stringify(a16));
  await shot('mb7-04-track-movie');

  /* A17 里程碑只列已达成·按 kind 换词 */
  const a17 = await ev(`var out={};['mv2','tv1','mu1','gm1'].forEach(function(id){
      mCurDetail=MDEMO.find(function(x){return x.id===id});mRenderTrackSheet();
      out[id]=[].map.call(document.querySelectorAll('#mTrackBody .mmile'),function(m){return m.dataset.l}).join('|')});
    closeSheet('m-sheet-track');return out;`);
  (/开始/.test(a17.mv2) && /看过一半/.test(a17.mv2) && /看完/.test(a17.mv2)
    && /看到一半/.test(a17.tv1) && /追完/.test(a17.tv1)
    && /循环 100 次/.test(a17.mu1) === false && /通关/.test(a17.mu1) === false
    && /主线半程/.test(a17.gm1) && /通关/.test(a17.gm1) === false)
    ? ok('A17 里程碑四类各一套 · 未达成的整行不出现', 'mv2=' + a17.mv2 + ' | gm1=' + a17.gm1) : bad('A17', JSON.stringify(a17));
  for (const id of ['mv2', 'tv1', 'mu1', 'gm1']) {
    await ev(`closeSheet('m-sheet-track');mCurDetail=MDEMO.find(function(k){return k.id==='${id}'});openSheet('m-sheet-track');mRenderTrackSheet();return 1;`);
    await shot('mb7-08-track-' + id);
  }
  await ev(`closeSheet('m-sheet-track');return 1;`);

  /* A18 轨迹空态＝无会话条目出虚线，不造演示数据 */
  const a18 = await ev(`mCurDetail=MDEMO.find(function(k){return k.id==='mv3'});openSheet('m-sheet-track');
    return {cols:document.querySelectorAll('#mTrackBody .mtrackcol').length,
      empty:!!document.querySelector('#mTrackBody .mempty'),txt:(document.querySelector('#mTrackBody .mempty')||{}).textContent,
      entry:!!document.querySelector('#mTrackBody .mentry')};`);
  (a18.cols === 0 && a18.empty && /还没有计时记录/.test(a18.txt) && !a18.entry) ? ok('A18 无计时记录条目＝虚线空态，明细入口行也不铺') : bad('A18', JSON.stringify(a18));
  await shot('mb7-05-track-empty');

  /* A19 操作弹层「影音轨迹」＝真开本弹层（原演示 toast 下架） */
  const a19 = await ev(`closeSheet('m-sheet-track');mOpen('tv2');openSheet('m-sheet-ops');
    var rows=[].slice.call(document.querySelectorAll('#mOpsList div'));
    var tr=rows.filter(function(d){return d.textContent.trim()==='影音轨迹'})[0];tr.click();
    var open=document.querySelector('.sheet:not(.hidden)');
    return {opened:open?open.id:'',rows:rows.map(function(d){return d.textContent.trim()}).join('|')};`);
  a19.opened === 'm-sheet-track' ? ok('A19 操作弹层「影音轨迹」改真开弹层（入口两处：详情动作条＋操作面）', a19.rows) : bad('A19', JSON.stringify(a19));

  /* A20 明细入口行跳计时明细整屏（批4 拍板①不推翻） */
  const a20 = await ev(`mRenderTrackSheet();var e=document.querySelector('#mTrackBody .mentry');e.click();
    return {p:curPage,open:document.querySelectorAll('.sheet:not(.hidden)').length};`);
  (a20.p === 'm-sesslog' && a20.open === 0) ? ok('A20 轨迹顶栏下方明细行＝收起弹层并进计时明细整屏') : bad('A20', JSON.stringify(a20));

  /* A21 两屏段内零 emoji（AGENTS 禁令） */
  const a21 = await ev(`var h=document.getElementById('m-stat').outerHTML+document.getElementById('m-sheet-track').outerHTML;
    var re=[/[\\u{1F300}-\\u{1FAFF}]/u,/[\\u{2600}-\\u{27BF}]/u,/[\\u{2B00}-\\u{2B5F}]/u,/\\u{FE0F}/u];
    return {hit:re.filter(function(r){return r.test(h)}).length};`);
  a21.hit === 0 ? ok('A21 统计屏与轨迹弹层段内 emoji 扫描 0 命中') : bad('A21', JSON.stringify(a21));

  /* A22 「演示」字样扫描（占位 toast 不许留在本批两面上） */
  const a22 = await ev(`var s=document.getElementById('m-stat').outerHTML+document.getElementById('m-sheet-track').outerHTML+${STXT};
    return {demo:(s.match(/演示/g)||[]).length};`);
  a22.demo === 0 ? ok('A22 两面零「演示」字样') : bad('A22', JSON.stringify(a22));

  log('PAGE ERRORS ' + errs.length + (errs.length ? ' :: ' + errs.join(' || ') : ''));
  finish();
})().catch(e => { bad('runner', String(e && e.message || e)); if (errs.length) log('PAGE ERRORS ' + errs.length + ' :: ' + errs.join(' || ')); finish() });

function finish() { try { ws && ws.close() } catch (e) { } try { chrome && chrome.kill() } catch (e) { }
  log('RESULT ' + pass + '/' + (pass + fail) + ' 绿 · fail=' + fail + ' · PAGE ERRORS ' + errs.length);
  process.exit(fail || errs.length ? 1 : 0) }
