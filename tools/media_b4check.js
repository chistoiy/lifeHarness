/* media_b4check.js · 影音游批4 原型先行两屏的无头回归（m-info 条目资料 · m-sesslog 计时明细）
 * 口径依据＝docs/handoff/交棒话术-20261007-影音游批4资料页与计时明细.md（三项拍板：整屏明细／独立资料屏／两列对照·账本吃真实）
 * 标记类（供确定性断言，不靠 Tailwind 选择器）：.mrow 明细行 · .mform 行内展开 · .ms4 数据卡格 · .mentry 明细入口行 · .mempty 空态
 * 用法：node --experimental-websocket tools/media_b4check.js            （截图：MB4_SHOTS=1，落仓库外 tempWork） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index-media.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.MB4_PORT || 9612);
const SHOTS = process.env.MB4_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/media-b4-shots';
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
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64')) }
const ROWS = "[].slice.call(document.querySelectorAll('#mdsSessBody .mrow'))";
const TXT = "document.getElementById('mdsSessBody').textContent.replace(/\\s+/g,'')";
const ITXT = "document.getElementById('mdsInfoBody').textContent.replace(/\\s+/g,'')";

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.media4-profile'), '--disable-extensions', '--no-default-browser-check',
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
  await cmd('Page.navigate', { url: URLF }); await wait(2800);

  /* A0 架面不回归：桌面视图出卡 */
  const a0 = await ev(`navTab('m-shelf');mSetView('desk');
    return {p:curPage,cards:document.querySelectorAll('#mShelfBody .mds-item').length};`);
  (a0.p === 'm-shelf' && a0.cards >= 8) ? ok('A0 影音架桌面视图照旧（' + a0.cards + ' 张实物卡）') : bad('A0', JSON.stringify(a0));

  /* A1 详情动作条补「条目资料」入口 */
  const a1 = await ev(`mOpen('mv1');return {p:curPage,txt:document.getElementById('mdsDetailBody').textContent};`);
  (a1.p === 'm-detail' && /条目资料/.test(a1.txt)) ? ok('A1 条目详情动作条有「条目资料」入口') : bad('A1', JSON.stringify(a1));

  /* A2 资料屏六段齐＋档案字段全（含各家外部 ID） */
  const a2 = await ev(`mInfoOpen();var t=${ITXT};
    return {p:curPage,segs:['观影时长','计时次数','日均','片长','进度','档案','简介','一页总结','计时明细'].filter(function(k){return t.indexOf(k)>=0}).length,
      arch:['来源','分组','主创','发行','发行年','加入时间','开始计时','最近一次','备注','豆瓣ID','IMDbID','TMDBID'].filter(function(k){return t.indexOf(k)>=0}).length};`);
  (a2.p === 'm-info' && a2.segs === 9 && a2.arch >= 11) ? ok('A2 资料屏＝数据卡＋进度＋档案（各家 ID 在内）＋简介＋总结＋明细入口', 'arch=' + a2.arch) : bad('A2', JSON.stringify(a2));
  await shot('mb4-01-info-movie');

  /* A3 数据卡第四格按 kind 换词 */
  const a3 = await ev(`var o={};[['mv1','片长'],['tv2','总集数'],['mu1','曲目数'],['gm1','周目']].forEach(function(p){mCurDetail=MDEMO.find(function(k){return k.id===p[0]});mRenderInfo();o[p[0]]=${ITXT}.indexOf(p[1])>=0});return o;`);
  (a3.mv1 && a3.tv2 && a3.mu1 && a3.gm1) ? ok('A3 第四格按 kind 各出各的词（片长/总集数/曲目数/周目）') : bad('A3', JSON.stringify(a3));

  /* A3b 四类资料屏各留一张样张（过门用） */
  await ev(`mCurDetail=MDEMO.find(function(k){return k.id==='mu1'});mRenderInfo();return 1;`); await shot('mb4-06-info-music');
  await ev(`mCurDetail=MDEMO.find(function(k){return k.id==='gm1'});mRenderInfo();return 1;`); await shot('mb4-07-info-game');
  await ev(`mSessOpen('gm2');return 1;`); await shot('mb4-08-sesslog-game');

  /* A4 预计完成日只在算得出时出现 */
  const a4 = await ev(`var o={};['mv1','mu1','gm5'].forEach(function(id){mCurDetail=MDEMO.find(function(k){return k.id===id});mRenderInfo();o[id]=/前后看完/.test(${ITXT})});return o;`);
  (a4.mv1 === true && a4.mu1 === false && a4.gm5 === false) ? ok('A4 预计完成日只在真算得出时出现（音乐与无总时长网游整行隐藏）', JSON.stringify(a4)) : bad('A4', JSON.stringify(a4));

  /* A5 无计时记录的条目：读数出 0 与 —，不编数 */
  const a5 = await ev(`mCurDetail=MDEMO.find(function(k){return k.id==='mv3'});mRenderInfo();
    return {cells:[].map.call(document.querySelectorAll('#mdsInfoBody .ms4 > div'),function(d){return d.textContent.replace(/\\s+/g,'')}),
      entry:(document.querySelector('#mdsInfoBody .mentry')||{}).textContent};`);
  (a5.cells[0] === '0m观影时长' && a5.cells[1] === '0计时次数' && a5.cells[2] === '—日均' && /0 条/.test(a5.entry || ''))
    ? ok('A5 无会话条目＝时长/次数/日均按真实读数出 0 与 —', (a5.cells || []).join('|')) : bad('A5', JSON.stringify(a5));

  /* A6 明细整屏：逐条一行·汇总出真实与折算两列 */
  const a6 = await ev(`mSessOpen('mv1');return {p:curPage,rows:${ROWS}.length,txt:${TXT}};`);
  (a6.p === 'm-sesslog' && a6.rows === 2 && /2h32m/.test(a6.txt) && /3h折算时长/.test(a6.txt))
    ? ok('A6 明细＝整屏 · 两行 · 汇总两列（真实 2h32m / 折算 3h）') : bad('A6', JSON.stringify(a6));
  await shot('mb4-02-sesslog');

  /* A7 行上折算列只在倍速>1 时出现（正常速度不重复同一个数） */
  const a7 = await ev(`var rs=${ROWS};return {fold:rs.filter(function(r){return /折算/.test(r.textContent)}).length,spd:rs.filter(function(r){return /1\\.5x/.test(r.textContent)}).length};`);
  (a7.fold === 1 && a7.spd === 1) ? ok('A7 倍速行出「1.5x」与折算读数，正常速度行不重复') : bad('A7', JSON.stringify(a7));

  /* A8 范围三档：本月把九月那组过滤掉并走空态文案 */
  const a8 = await ev(`mSessOpen('tv1');var all=${ROWS}.length;mSessScopePick('m');
    return {all:all,m:${ROWS}.length,empty:!!document.querySelector('#mdsSessBody .mempty'),txt:document.querySelector('#mdsSessBody .mempty')?document.querySelector('#mdsSessBody .mempty').textContent:'',
      chips:document.querySelectorAll('#mdsSessBody .mds-chip').length};`);
  (a8.all === 1 && a8.m === 0 && a8.empty && /当前范围没有记录/.test(a8.txt))
    ? ok('A8 范围 chips 三档·本月过滤后走「当前范围没有记录」') : bad('A8', JSON.stringify(a8));

  /* A9 行内改＝就地六栏＋三钮，不起弹层 */
  const a9 = await ev(`mSessOpen('mv1');mSessToggle(0);
    return {f:['msDt0','msMin0','msF0','msT0','msPa0','msPb0','msSpd0'].filter(function(i){return !!document.getElementById(i)}).length,
      btns:[].map.call(document.querySelectorAll('#mdsSessBody .mform button'),function(b){return b.textContent}).filter(function(t){return /删除这次|取消|保存/.test(t)}).length,
      openSheets:document.querySelectorAll('.sheet:not(.hidden)').length};`);
  (a9.f === 7 && a9.btns === 3 && a9.openSheets === 0) ? ok('A9 展开行内就地改：日期/时长/起讫/进度＋倍速钮·三钮齐·没起弹层') : bad('A9', JSON.stringify(a9));
  await shot('mb4-03-row-edit');

  /* A10 倍速钮当场重算折算预览（列表不重排、输入不丢） */
  const a10 = await ev(`var m=document.getElementById('msMin0');m.value='120';mSessSpeed(0,2);
    return {fold:document.getElementById('msFold0').textContent,val:document.getElementById('msMin0').value,
      on:[].filter.call(document.querySelectorAll('#msSpd0 .mds-chip'),function(b){return b.classList.contains('on')}).map(function(b){return b.dataset.v}).join('')};`);
  (/4h/.test(a10.fold) && a10.val === '120' && a10.on === '2') ? ok('A10 倍速钮把折算预览当场重算（120×2＝4h）且不丢输入', a10.fold) : bad('A10', JSON.stringify(a10));

  /* A11 保存＝写回这条·累计按真实耗时重算（120+56＝176＝2h56m） */
  const a11 = await ev(`mSessSave(0);return {txt:${TXT},rows:${ROWS}.length,edit:mSessEdit};`);
  (a11.rows === 2 && a11.edit === -1 && /2h56m/.test(a11.txt)) ? ok('A11 保存后行收起·累计随真实耗时重算（2h56m）') : bad('A11', JSON.stringify(a11));

  /* A12 补记＝顶栏 ＋ 起就地草稿，保存后第三条·来源标补记 */
  const a12 = await ev(`mSessAddNew();var has=!!document.getElementById('msDt-1');
    document.getElementById('msMin-1').value='30';document.getElementById('msDt-1').value='2026-10-07';
    document.getElementById('msPa-1').value='1:36:00';document.getElementById('msPb-1').value='1:50:00';mSessSave(-1);
    return {draft:has,rows:${ROWS}.length,src:/补记/.test(${TXT}),draftLeft:!!document.getElementById('msDt-1')};`);
  (a12.draft && a12.rows === 3 && a12.src && !a12.draftLeft) ? ok('A12 补记＝就地草稿·保存后第三条·来源标「补记」') : bad('A12', JSON.stringify(a12));

  /* A13 删除一条＝列表与库同步 */
  const a13 = await ev(`var n0=mSessOf('mv1').length;mSessToggle(0);mSessDel(0);
    return {before:n0,after:mSessOf('mv1').length,rows:${ROWS}.length};`);
  (a13.before === 3 && a13.after === 2 && a13.rows === 2) ? ok('A13 删除这次＝当场出列，列表与库同步') : bad('A13', JSON.stringify(a13));

  /* A14 资料页统计格与操作弹层都落到明细屏 */
  const a14 = await ev(`mOpen('tv2');mInfoOpen();var lbl=/追剧时长/.test(${ITXT});
    document.querySelector('#mdsInfoBody .ms4 > div').click();var p1=curPage;
    mOpen('tv2');openSheet('m-sheet-ops');var ops=[].map.call(document.querySelectorAll('#mOpsList div'),function(d){return d.textContent}).join('|');closeSheet('m-sheet-ops');
    return {p1:p1,lbl:lbl,ops:ops};`);
  (a14.p1 === 'm-sesslog' && a14.lbl && /计时明细/.test(a14.ops) && /条目资料/.test(a14.ops))
    ? ok('A14 统计格点开明细·操作弹层两项入口到位', a14.ops) : bad('A14', JSON.stringify(a14));

  /* A15 空态：无会话条目开明细＝虚线行，不造演示数据 */
  const a15 = await ev(`mSessOpen('mv3');return {rows:${ROWS}.length,empty:!!document.querySelector('#mdsSessBody .mempty'),txt:(document.querySelector('#mdsSessBody .mempty')||{}).textContent};`);
  (a15.rows === 0 && a15.empty && /还没有计时记录/.test(a15.txt)) ? ok('A15 空态＝虚线行＋补记指路') : bad('A15', JSON.stringify(a15));
  await shot('mb4-04-sesslog-empty');

  /* A16 一页总结：三行按 kind 措辞＋编辑态；未填走虚线不编数 */
  const a16 = await ev(`mCurDetail=MDEMO.find(function(k){return k.id==='tv2'});mRenderInfo();var t=${ITXT};
    var read=[/一句话短评/.test(t),/追下去的理由/.test(t),/会不会推荐给朋友/.test(t),/未填/.test(t)];
    mInfoSum=true;mRenderInfo();
    return {read:read,areas:document.querySelectorAll('#mdsInfoBody textarea').length,btns:[].map.call(document.querySelectorAll('#mdsInfoBody .mds-chip'),function(b){return b.textContent}).join('|')};`);
  (a16.read[0] && a16.read[1] && a16.read[2] && a16.read[3] && a16.areas === 3 && /保存/.test(a16.btns) && /恢复自动生成/.test(a16.btns))
    ? ok('A16 一页总结三行按 kind 措辞·编辑态三段·未填出虚线不编数') : bad('A16', JSON.stringify(a16));
  await shot('mb4-05-info-summary');

  /* A17 两屏段内零 emoji（AGENTS 禁令；箭头 → 属既有文案符号不在扫描范围） */
  const a17 = await ev(`var h=document.getElementById('m-info').outerHTML+document.getElementById('m-sesslog').outerHTML;
    var re=[/[\\u{1F300}-\\u{1FAFF}]/u,/[\\u{2600}-\\u{27BF}]/u,/[\\u{2B00}-\\u{2B5F}]/u,/\\u{FE0F}/u];
    return {hit:re.filter(function(r){return r.test(h)}).length};`);
  a17.hit === 0 ? ok('A17 两屏段内 emoji 扫描 0 命中') : bad('A17', JSON.stringify(a17));

  /* A18 脊视图仍把电影自动缺席（本批动过架面入口，钉住不回归） */
  const a18 = await ev(`navTab('m-shelf');mPickKind('movie');mSetView('spine');var n1=document.querySelectorAll('#mShelfBody .mds-spine').length;
    mPickKind('all');var n2=document.querySelectorAll('#mShelfBody .mds-spine').length;
    mPickKind('all');mSetView('desk');return {movieSpine:n1,allSpine:n2};`);
  (a18.movieSpine === 0 && a18.allSpine >= 3) ? ok('A18 脊视图电影照旧缺席（全部态 ' + a18.allSpine + ' 支侧脊）') : bad('A18', JSON.stringify(a18));

  finish();
})().catch(e => { bad('harness 崩溃 ' + String(e).slice(0, 200)); finish() });
function finish() { log((fail ? 'RESULT FAIL ' : 'RESULT PASS ') + pass + '/' + (pass + fail));
  if (errs.length) { log('PAGE ERRORS ' + errs.length + ': ' + errs.join(' || ')); fail++ }
  else log('PAGE ERRORS 0');
  try { if (chrome) chrome.kill() } catch (e) { }
  process.exit(fail ? 1 : 0) }
