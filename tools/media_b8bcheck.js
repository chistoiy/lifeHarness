/* media_b8bcheck.js · 影音游批8b 原型先行两面的无头回归（m-lists 影音单列表 · m-list 详情 · 三枚弹层）
 * 口径依据＝docs/影音游模块开发计划-20260922.md §四（m-lists/m-list 行）＋§五 批4 验收（成员/年度底稿/混合单同屏四类）
 *   ＋批8a 拍板①（分享形态照习惯模块定式＝半屏预览＋复制文字版·存图模拟，不做 canvas 桌面拼贴）
 * 标记类：.mlrow[data-ml] · .mltype[data-mlt] · [data-mlcnt] · .mlmem[data-mid] · #mlStatLine[data-mlsum] ·
 *   #ml-add-btn · #mlShareGrid · #mlShareText · [data-pickmark]
 * 期望值一律页内独立算子现算（年度底稿成员/合计分钟/文字版各自重算一遍，不复用渲染函数）。
 * 用法：node --experimental-websocket tools/media_b8bcheck.js            （截图：MB8B_SHOTS=1，落仓库外 tempWork）
 *       node --experimental-websocket tools/media_b8bcheck.js --mut 1|2|3 （变异刀：底稿不过滤本年 / 拖拽不重排 / 分享挂回 canvas） */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index-media.html');
const BAK = path.resolve('tmp/index-media.b8b.before.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.MB8B_PORT || 9628);
const SHOTS = process.env.MB8B_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/media-b8b-shots';
const MUT = process.argv.indexOf('--mut');
const mut = MUT >= 0 ? Number(process.argv[MUT + 1]) : 0;
const ORIG = fs.readFileSync(FILE, 'utf8');
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
async function shot(name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTDIR, { recursive: true });
  await wait(420);
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64'));
}
/* 变异刀：跑完由 finally 逐字节复原 */
const RAW = `var YR=String(M_STAT_TODAY[0]);
  function memOf(id){var L=MLS.find(function(x){return x.id===id});if(!L)return [];
    if(L.type==='year'){return MDEMO.filter(function(x){return ML_DONE.indexOf(x.state)>=0&&String(x.endedAt||'').slice(0,4)===YR})
      .map(function(x){return{x:x,k:String(x.endedAt||'')}}).sort(function(a,b){return b.k.localeCompare(a.k)||a.x.id.localeCompare(b.x.id)}).map(function(o){return o.x.id});}
    return (L.members||[]).filter(function(i){return !!MDEMO.find(function(x){return x.id===i})});}
  function sumOf(ids){return ids.map(function(i){return MDEMO.find(function(x){return x.id===i})}).filter(Boolean).reduce(function(a,x){return a+(x.dur||0)},0)}`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish(); }
  if (mut) {
    const inject = (n, a, b) => {
      if (ORIG.split(a).length - 1 !== 1) { bad('MUT' + n + ' 就地锚点命中数<>1（刀没处下＝红灯）'); return finish(); }
      fs.writeFileSync(FILE, ORIG.replace(a, b), 'utf8');
    };
    if (mut === 1) inject(1, "return ML_DONE.indexOf(x.state) >= 0 && String(x.endedAt || '').slice(0, 4) === ML_YEAR;", "return ML_DONE.indexOf(x.state) >= 0;");
    if (mut === 2) inject(2, 'const f = arr.indexOf(mlDragId), t = arr.indexOf(into);', 'const f = -1, t = -1;');
    if (mut === 3) inject(3, 'grid.innerHTML = ids.map(function (id) {', "grid.innerHTML = '<canvas></canvas>' + ids.map(function (id) {");
    if (mut === 4) inject(4, "if (v && v !== L.name) { L.name = v; toast('单名已改'); }", "if (v && v !== L.name) { toast('单名已改'); }");
    log('MUT=' + mut + ' 已就地注入（跑完按 ORIG 逐字节复原）');
  }
  chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.media8b-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
  let data = null;
  for (let i = 0; i < 60; i++) { const d = await get('http://127.0.0.1:' + PORT + '/json'); if (d) { try { data = JSON.parse(d); if (data.some(x => x.type === 'page')) break } catch (e) { } } await wait(300) }
  const pg = data.find(t => t.type === 'page');
  ws = new WebSocket(pg.webSocketDebuggerUrl);
  await new Promise(r => { ws.addEventListener('open', r); setTimeout(r, 3000) });
  ws.addEventListener('message', e2 => {
    const m = JSON.parse(e2.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') errs.push(((m.params.exceptionDetails.exception || {}).description || '').slice(0, 260));
  });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Page.navigate', { url: URLF });
  /* 内联脚本排在 Tailwind CDN 之后：轮询到本批全局在场再用，勿改固定 sleep（批7 实锤坑） */
  for (let i = 0; i < 30; i++) {
    const r = await ev(`return (typeof navTo==='function')&&(typeof mRenderLists==='function')&&(typeof mRenderList==='function')&&(typeof MLS!=='undefined')&&(typeof mlShareText==='function')`);
    if (r === true) break;
    await wait(700);
  }

  /* A1 列表页＝六枚齐（五种手动＋年度底稿）且类型徽标对名 */
  const a1 = await ev(`navTo('m-lists');
    var rows=[].slice.call(document.querySelectorAll('#mListsBody .mlrow'));
    return {n:rows.length,ids:rows.map(function(r){return r.dataset.ml}).join(','),
      types:rows.map(function(r){return r.querySelector('.mltype').textContent}).join(',')};`);
  (a1.n === 6 && a1.ids === 'auto,l1,l2,l3,l4,l5' && a1.types === '年度底稿,片单,歌单,游戏单,片单,混合单')
    ? ok('A1 列表六枚齐·徽标＝年度/片单/歌单/游戏单/片单/混合单') : bad('A1', JSON.stringify(a1));
  await shot('mb8b-01-lists');

  /* A2 年度底稿＝「本年度 · 底稿」前缀在场、无假计数（旧占位 32 条已摘） */
  const a2 = await ev(`navTo('m-lists');var r=document.querySelector('.mlrow[data-ml="auto"]');
    return {name:r.getAttribute('data-mlname'),txt:r.textContent,has32:/32 条/.test(r.textContent),dup:(r.textContent.match(/年度/g)||[]).length};`);
  (a2.name === '2026 影音' && a2.name.indexOf('年度') < 0 && a2.txt.indexOf('本年度') >= 0 && !a2.has32) ? ok('A2 底稿行＝现算成员数（' + a2.txt.replace(/\s+/g, ' ').slice(0, 46) + '）') : bad('A2', JSON.stringify(a2));

  /* A3 底稿成员＝完结档且本年（独立算子比对＋顺序＝达成日倒序） */
  const a3 = await ev(RAW + `var want=memOf('auto');
    mCurList='auto';mRenderList();
    var got=[].map.call(document.querySelectorAll('#mListBody .mlmem'),function(r){return r.dataset.mid}).join(',');
    return {got:got,want:want.join(','),n:want.length};`);
  (a3.got === a3.want) ? ok('A3 底稿成员与顺序＝完结档本年按达成日倒序现算对上（' + a3.n + ' 条）') : bad('A3', JSON.stringify(a3));
  if (mut === 1) { log('MUT1 期望＝本条独红'); }

  /* A4 底稿只读＝顶栏下方无「＋ 添加条目」、每行无「移出」、有「底稿只读」提示 */
  const a4 = await ev(RAW + `mCurList='auto';mRenderList();
    return {add:!!document.getElementById('ml-add-btn'),rm:document.querySelectorAll('#mListBody .mlmem button').length,
      exp:!!document.getElementById('ml-export-btn'),share:!!document.getElementById('ml-share-btn'),
      hint:document.getElementById('mListBody').textContent.indexOf('底稿只读')>=0};`);
  (a4.add === false && a4.rm === 0 && a4.exp === false && a4.share === true && a4.hint)
    ? ok('A4 底稿只读＝行内无移出·添加与导出整件不铺，仅分享在场') : bad('A4', JSON.stringify(a4));
  await ev("navTo('m-list');return 1");
  await shot('mb8b-02-detail-year');

  /* A5 手动单成员按存储序（不重排）＋合计读数＝原始 dur 现算 */
  const a5 = await ev(RAW + `var want=memOf('l1');var s=sumOf(want);
    mCurList='l1';mRenderList();
    var got=[].map.call(document.querySelectorAll('#mListBody .mlmem'),function(r){return r.dataset.mid}).join(',');
    var line=document.getElementById('mlStatLine').getAttribute('data-mlsum');
    return {got:got,want:want.join(','),line:line,s:s,n:want.length};`);
  (a5.got === a5.want && a5.line === String(a5.s))
    ? ok('A5 手动单序＝存储序（' + a5.got + '）·合计 ' + a5.s + ' 分＝原始 dur 现算') : bad('A5', JSON.stringify(a5));
  await ev("navTo('m-list');return 1");
  await shot('mb8b-03-detail-manual');

  /* A6 拖拽排序＝落库序当场变（成员序与列表页计数同步） */
  const a6 = await ev(RAW + `mCurList='l1';mRenderList();
    var before=MLS.find(function(x){return x.id==='l1'}).members.join(',');
    var rows=document.querySelectorAll('#mListBody .mlmem');
    var firstId=rows[0].dataset.mid;
    var fake={preventDefault:function(){},dataTransfer:{effectAllowed:''}};
    mlDrag(fake,before.split(',')[2]);mlDrop(fake,firstId);
    var after=MLS.find(function(x){return x.id==='l1'}).members.join(',');
    var dom=[].map.call(document.querySelectorAll('#mListBody .mlmem'),function(r){return r.dataset.mid}).join(',');
    var drag0=document.querySelector('#mListBody .mlmem').getAttribute('draggable');
    return {before:before,after:after,dom:dom,drag0:drag0,moved:before!==after};`);
  (a6.moved && a6.dom === a6.after && a6.drag0 === 'true')
    ? ok('A6 拖拽重排＝数据序与渲染序同帧（' + a6.before + ' → ' + a6.after + '）') : bad('A6', JSON.stringify(a6));
  if (mut === 2) log('MUT2 期望＝本条独红');
  /* 复原演示数据序，保持同态 */
  await ev(`MLS.find(function(x){return x.id==='l1'}).members=['mv1','tv2','mv4'];mRenderList();return 1;`);

  /* A7 混合单成员＝四类同屏（kind 集合覆盖三类以上） */
  const a7 = await ev(RAW + `mCurList='l5';mRenderList();
    var ks=[].map.call(document.querySelectorAll('#mListBody .mlmem'),function(r){
      var id=r.dataset.mid;return (MDEMO.find(function(x){return x.id===id})||{}).kind});
    return {kinds:Array.from(new Set(ks)).sort().join(','),n:ks.length};`);
  (a7.kinds.split(',').length >= 3) ? ok('A7 混合单四类同屏＝kind 集合 ' + a7.kinds + '（' + a7.n + ' 条）') : bad('A7', JSON.stringify(a7));

  /* A8 移出成员＝行消失、列表页计数同步 */
  const a8 = await ev(RAW + `mCurList='l4';mRenderList();
    var cnt0=+document.querySelector('[data-mlcnt="l4"]').textContent.replace(/[^0-9]/g,'');
    var first=document.querySelector('#mListBody .mlmem').dataset.mid;
    mlRemove(first);mRenderLists();
    var cnt1=+document.querySelector('[data-mlcnt="l4"]').textContent.replace(/[^0-9]/g,'');
    var still=document.querySelector('#mListBody .mlmem[data-mid="'+first+'"]');
    MLS.find(function(x){return x.id==='l4'}).members=['mv2','mv3','mv1'];mRenderLists();
    return {c0:cnt0,c1:cnt1,gone:!still};`);
  (a8.c1 === a8.c0 - 1 && a8.gone) ? ok('A8 移出＝行消失且列表页计数 ' + a8.c0 + '→' + a8.c1 + '（演示数据已复原）') : bad('A8', JSON.stringify(a8));

  /* A9 LH-S34「移入影音单」＝真开层（不再是演示 toast 死口） */
  const a9 = await ev(`mOpen('mv2');openSheet('m-sheet-ops');
    var rows=[].slice.call(document.querySelectorAll('#mOpsList > div'));
    var row=rows.filter(function(r){return r.textContent.indexOf('移入影音单')>=0})[0];
    row.click();
    var sheetOpen=!document.getElementById('m-sheet-mlist').classList.contains('hidden');
    var opsHidden=document.getElementById('m-sheet-ops').classList.contains('hidden');
    var picks=[].slice.call(document.querySelectorAll('#mListPickBody [data-pick]')).map(function(r){return r.getAttribute('data-pick')}).join(',');
    return {sheetOpen:sheetOpen,opsHidden:opsHidden,picks:picks,rows:rows.length};`);
  (a9.sheetOpen && a9.opsHidden && a9.picks.indexOf('auto') < 0 && a9.rows === 9)
    ? ok('A9 动作面改真接线＝开层＋操作面收起＋候选排除底稿（' + a9.picks + '）') : bad('A9', JSON.stringify(a9));

  /* A10 勾选加入/取消＝计数双向，「已在单内」可辨 */
  const a10 = await ev(`var L=MLS.find(function(x){return x.id==='l1'});var n0=L.members.length;
    mlToggleMember('l1');var n1=L.members.length;
    var mark=document.querySelector('[data-pickmark="l1"]').textContent;
    mlToggleMember('l1');var n2=L.members.length;
    closeSheet('m-sheet-mlist');
    return {n0:n0,n1:n1,n2:n2,mark:mark};`);
  (a10.n1 === a10.n0 + 1 && a10.n2 === a10.n0 && a10.mark.indexOf('已在单内') >= 0)
    ? ok('A10 加入→取消计数往返对上（' + a10.n0 + '→' + a10.n1 + '→' + a10.n2 + '）·选中态可辨') : bad('A10', JSON.stringify(a10));

  /* A11 新建影音单＝名＋五档类型→直达详情（空态虚线在场） */
  const a11 = await ev(`mCurDetail=MDEMO[0];openSheet('m-sheet-mlist-new');
    var chips=[].map.call(document.querySelectorAll('.mln-type'),function(e){return e.getAttribute('data-newtype')}).join(',');
    document.getElementById('mlNewName').value='闸验证单';
    document.querySelector('.mln-type[data-newtype="mix"]').click();
    var on=document.querySelectorAll('.mln-type.on').length;
    mlNewGo();
    var page=curPage,name=document.getElementById('mListTitle').textContent;
    var empty=/还是空的/.test(document.getElementById('mListBody').textContent);
    MLS.splice(MLS.findIndex(function(x){return x.name==='闸验证单'}),1);mRenderLists();
    return {chips:chips,on:on,page:page,name:name,empty:empty};`);
  (a11.chips === 'movie,series,music,game,mix' && a11.on === 1 && a11.page === 'm-list' && a11.name === '闸验证单' && a11.empty)
    ? ok('A11 新建＝五档类型 chips·选混合单落位·直达详情空态虚线（演示单已删）') : bad('A11', JSON.stringify(a11));

  /* A12 分享弹层＝封面轨道 n 格＋行数一致（禁 canvas 桌面拼贴＝习惯定式） */
  const a12 = await ev(RAW + `mCurList='l5';mlShareOpen();
    var ids=memOf('l5');
    var cells=document.querySelectorAll('#mlShareGrid > div').length;
    var cv=document.querySelectorAll('#m-sheet-share canvas').length;
    var cap=document.getElementById('mlShareCap').textContent;
    return {cells:cells,n:ids.length,cv:cv,cap:cap};`);
  (a12.cells === a12.n && a12.cv === 0 && a12.cap.indexOf('条') >= 0)
    ? ok('A12 分享预览＝封面轨道 ' + a12.cells + ' 格与成员数齐·零 canvas') : bad('A12', JSON.stringify(a12));
  if (mut === 3) log('MUT3 期望＝本条独红');

  /* A13 TXT/MD 两版现算比对（内容随格式切换，非同一份复制两次） */
  const a13 = await ev(RAW + `mCurList='l1';mlShareOpen();
    var wantTxt=(function(){var ids=memOf('l1');var L=mlOf('l1');
      var lines=ids.map(function(id,i){var x=MDEMO.find(function(k){return k.id===id});return (i+1)+'. '+x.title+' · '+x.kind+' · '+x.state+(x.endedAt?' · '+x.endedAt:'')});
      return [L.name,ML_TYPE[L.type],lines.join('\\n'),'共 '+ids.length+' 条 · 合计 '+(sumOf(ids)/60).toFixed(1)+' h'].join('\\n')})();
    var t0=document.getElementById('mlShareText').value;
    mlFmtPick('md');
    var t1=document.getElementById('mlShareText').value;
    var mdHead=/^# /.test(t1)&&/\\| 条目 \\|/.test(t1);
    var onMd=document.getElementById('mlFmt-md').classList.contains('on'),offTxt=!document.getElementById('mlFmt-txt').classList.contains('on');
    mlFmtPick('txt');
    var back=document.getElementById('mlShareText').value===wantTxt;
    return {t0:t0===wantTxt,back:back,md:mdHead,onMd:onMd,offTxt:offTxt,same:t0===t1};`);
  (a13.t0 && a13.back && a13.md && a13.onMd && a13.offTxt && !a13.same)
    ? ok('A13 文字版 TXT＝独立算子现算对上·MD 表头在场·切换选中态可辨') : bad('A13', JSON.stringify(a13));

  /* A14 复制文字版＝一句回执；存图＝模拟（段内零 canvas/零 a download） */
  const a14 = await ev(`mlCopyText();
    var t=(document.getElementById('toast')||{}).textContent||'';
    mlFakeSave();
    var t2=(document.getElementById('toast')||{}).textContent||'';
    var html=document.getElementById('m-sheet-share').innerHTML;
    return {copy:t,save:t2,noCanvas:/canvas/.test(html),noDown:/<a [^>]*download/.test(html)};`);
  (a14.copy.length > 0 && a14.save.indexOf('模拟') >= 0 && !a14.noCanvas && !a14.noDown)
    ? ok('A14 复制有交代＋存图明示模拟·段内零 canvas 零下载锚') : bad('A14', JSON.stringify(a14));

  /* A15 列表页点卡＝直达详情，标题与成员同单；返回回列表页
        （架面卡上的「n 单」角标属实现批 Flutter 面，原型不铺＝面板判据按原型实态复核后修正） */
  const a15 = await ev(RAW + `navTo('m-lists');
    document.querySelector('.mlrow[data-ml="l2"]').click();
    var page=curPage,title=document.getElementById('mListTitle').textContent;
    var dom=[].map.call(document.querySelectorAll('#mListBody .mlmem'),function(r){return r.dataset.mid}).join(',');
    var want=memOf('l2').join(',');
    goBack();
    return {page:page,title:title,ok:dom===want,back:curPage};`);
  (a15.page === 'm-list' && a15.title === '通勤听' && a15.ok && a15.back === 'm-lists')
    ? ok('A15 列表点卡直达详情·成员同源·返回回列表页') : bad('A15', JSON.stringify(a15));

  /* A16 两面段内零 emoji、零「演示」、零旧占位自注（AGENTS 禁令） */
  const a16 = await ev(`navTo('m-lists');var h=document.getElementById('m-lists').outerHTML+document.getElementById('m-list').outerHTML
    +document.getElementById('m-sheet-mlist').outerHTML+document.getElementById('m-sheet-mlist-new').outerHTML+document.getElementById('m-sheet-share').outerHTML;
    var re=[/[\\u{1F300}-\\u{1FAFF}]/u,/[\\u{2600}-\\u{27BF}]/u,/[\\u{2B00}-\\u{2B5F}]/u,/\\u{FE0F}/u];
    return {hit:re.filter(function(r){return r.test(h)}).length,old:/待批实现|占位演示/.test(h)};`);
  (a16.hit === 0 && !a16.old) ? ok('A16 两面＋三弹层 DOM 段：emoji/占位自注 全 0') : bad('A16', JSON.stringify(a16));
  /* A16b 本批 JS 段零「演示」字样（动作面其余四条演示 toast 属批前技术债＝另单处置） */
  const a16b = await ev(`var src=[mlYearMembers,mlCount,mRenderLists,mRenderList,mlDrag,mlDrop,mlRemove,mlCreate,mRenderListPickSheet,mlToggleMember,mRenderListNewSheet,mlPickNewType,mlNewGo,mlRenameOpen,mlShareText,mlShareMd,mlShareOpen,mRenderShareSheet,mlFmtPick,mlCopyText,mlFakeSave,mlExport]
      .map(function(f){return String(f)}).join('');
    return {demo:(src.match(/演示/g)||[]).length,ph:/待实现|待批/.test(src)}`);
  (a16b.demo === 0 && !a16b.ph) ? ok('A16b 批8b JS 段零「演示」零待实现自注') : bad('A16b', JSON.stringify(a16b));
  await shot('mb8b-04-share');

  /* A17 同态重渲染逐字节等（两面确定性，无随机） */
  const a17 = await ev(`navTo('m-lists');mRenderLists();var a=document.getElementById('mListsBody').innerHTML;mRenderLists();
    mCurList='l1';mRenderList();var b=document.getElementById('mListBody').innerHTML;mRenderList();
    return {l:a===document.getElementById('mListsBody').innerHTML,d:b===document.getElementById('mListBody').innerHTML};`);
  (a17.l && a17.d) ? ok('A17 列表面与详情面同态重渲染逐字节等') : bad('A17', JSON.stringify(a17));

  /* A18 详情头铅笔＝就地改名真接线（回车落名·列表页同步）；底稿藏铅笔 */
  const a18 = await ev(RAW + `navTo('m-list');mCurList='l2';mRenderList();
    var hid0=document.getElementById('mlEditBtn').style.display;
    mCurList='auto';mRenderList();
    var hidY=document.getElementById('mlEditBtn').style.display;
    mCurList='l2';mRenderList();mlRenameOpen();
    var hadIn=!!document.getElementById('mlRenameIn');
    document.getElementById('mlRenameIn').value='通勤听歌';
    document.getElementById('mlRenameIn').dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));
    var name=MLS.find(function(x){return x.id==='l2'}).name;
    var tile=document.querySelector('.mlrow[data-ml="l2"] [data-mlname]')||document.querySelector('.mlrow[data-ml="l2"]');
    var tileTxt=tile?tile.textContent:'';
    MLS.find(function(x){return x.id==='l2'}).name='通勤听';mRenderLists();
    return {hid0:hid0,hidY:hidY,hadIn:hadIn,name:name,tile:tileTxt.indexOf('通勤听歌')>=0};`);
  (a18.hidY === 'none' && a18.hadIn && a18.name === '通勤听歌' && a18.tile)
    ? ok('A18 铅笔改名落库·列表页瓦片同步·底稿无铅笔') : bad('A18', JSON.stringify(a18));

  log('PAGE ERRORS ' + errs.length + (errs.length ? ' :: ' + errs.join(' || ') : ''));
  finish();
})().catch(e => { bad('runner', String((e && e.message) || e)); if (errs.length) log('PAGE ERRORS ' + errs.length + ' :: ' + errs.join(' || ')); finish(); });

function finish() {
  try { ws && ws.close() } catch (e) { }
  try { chrome && chrome.kill() } catch (e) { }
  if (mut) {
    fs.writeFileSync(FILE, ORIG, 'utf8');
    const a = require('crypto').createHash('md5').update(fs.readFileSync(FILE)).digest('hex');
    const b = require('crypto').createHash('md5').update(Buffer.from(ORIG,'utf8')).digest('hex');
    log('MUT 复原 md5 ' + a + (a === b ? ' == 基线全等' : ' != 基线 ' + b + '（红灯）'));
  }
  log('RESULT ' + pass + '/' + (pass + fail) + ' 绿 · fail=' + fail + ' · PAGE ERRORS ' + errs.length);
  process.exit(fail || errs.length ? 1 : 0);
}
