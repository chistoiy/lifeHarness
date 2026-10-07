/* media_b5check.js · 影音游批5 原型先行三面的无头闸（m-notes 影音笔记库 · m-review 名场面复习卡 · m-sheet-note-edit 唯一录入表单）
 * 规格依据＝docs/handoff/交棒话术-20261008-影音游批5笔记库与复习原型.md §1（三源口径：计划 L206~L208 为准）
 * 纪律（2026-10-08 固化）＝本件由 tools/media_b4check.js 改名复用；断言期望值一律页面内现算，不硬编码计数；截图默认关（MB5_SHOTS=1 才拍）
 * 标记类：.mrow 笔记行 · .mempty 空态虚线件
 * 用法：node --experimental-websocket tools/media_b5check.js */
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http'), url = require('url');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE = path.resolve('prototype/index-media.html');
const URLF = url.pathToFileURL(FILE).href;
const PORT = Number(process.env.MB5_PORT || 9613);
const SHOTS = process.env.MB5_SHOTS === '1';
const SHOTDIR = 'D:/dev_workplace/flutter_te/tempWork/media-b5-shots';
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
async function shot(name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTDIR, { recursive: true });
  const m = await cmd('Page.captureScreenshot', { format: 'png' });
  if (m.result && m.result.data) fs.writeFileSync(path.join(SHOTDIR, name + '.png'), Buffer.from(m.result.data, 'base64'));
}

/* 页面内探针：全部期望值现算，不写死数 */
const PRELUDE = String.raw`
window.__live=function(){return MNOTES.filter(function(n){return !n.gone})};
window.__nb=function(){return [].slice.call(document.querySelectorAll('#mNotesBody .mrow'))};
window.__cnt=function(){var e=document.getElementById('mNotesCount');return e?e.textContent.replace(/\s+/g,''):''};
window.__exp=function(p){var l=__live().filter(p||function(){return true});return l.length+'条·标星'+l.filter(function(n){return n.starred}).length};
window.__expN=function(p){return __live().filter(p||function(){return true}).length};
window.__chip=function(sel,label){var b=[].slice.call(document.querySelectorAll(sel+' .mds-chip')).filter(function(x){return x.textContent===label})[0];if(b)b.click();return !!b};
window.__hex=function(h){var m=h.replace('#','');return 'rgb('+parseInt(m.slice(0,2),16)+', '+parseInt(m.slice(2,4),16)+', '+parseInt(m.slice(4,6),16)+')'};
window.__rid=function(el){var a=el.getAttribute('onclick').match(/'([^']+)'/g);return a[a.length-1].replace(/'/g,'')};
window.__act=function(el,lb){return [].slice.call(el.querySelectorAll('.mds-chip')).filter(function(x){return x.textContent===lb})[0]};
window.__toast=function(){var t=document.getElementById('toast');return t?t.textContent:''};
window.__snap=function(){return MNOTES.map(function(n){return [n.id,n.rev,n.starred,n.gone||0]})};
window.__restore=function(s){s.forEach(function(a){var n=MNOTES.find(function(x){return x.id===a[0]});if(n){n.rev=a[1];n.starred=a[2];n.gone=a[3]}});mNoteType='all';mNoteKind='all';mNoteItem='all';mNoteStar=false;mNoteTag='all';mNoteQ='';mNoteView='card';mRenderNotes()};
window.__due=function(){return MNOTES.filter(mRevDue).length};
`;

(async () => {
  if (!fs.existsSync(CHROME)) { bad('chrome 存在'); return finish() }
  chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--remote-debugging-port=' + PORT,
    '--user-data-dir=' + path.resolve('tools/.media5-profile'), '--disable-extensions', '--no-default-browser-check',
    '--window-size=430,900', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
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
  await cmd('Page.navigate', { url: URLF }); await wait(2800);
  await ev(PRELUDE + 'return 1;');

  /* A0 影音架不回归 */
  const a0 = await ev(`navTab('m-shelf');return {p:curPage,c:document.querySelectorAll('#mShelfBody .mds-item').length};`);
  (a0.p === 'm-shelf' && a0.c >= 8) ? ok('A0 影音架桌面视图照旧（' + a0.c + ' 张）') : bad('A0', JSON.stringify(a0));

  /* A1 笔记库骨架：六组筛选＋四视图＋计数行，kind 钮是真筛选不是演示 */
  const a1 = await ev(`navTab('m-notes');
    return {p:curPage,
      g:['mNoteTypeChips','mNoteKindChips','mNoteItemChips','mNoteQ','mNoteStarChip','mNoteTagChips','mNoteViewSeg','mNotesCount'].filter(function(i){return document.getElementById(i)}).length,
      rows:__nb().length,cnt:__cnt(),exp:__exp(),
      segs:[].slice.call(document.querySelectorAll('#mNoteViewSeg .mds-chip')).map(function(b){return b.textContent}).join('/'),
      kindDemo:/演示/.test(document.getElementById('mNoteKindChips').textContent)};`);
  (a1.p === 'm-notes' && a1.g === 8 && a1.rows === a1.exp.split('条')[0] * 1 && a1.cnt === a1.exp && a1.segs === '卡片/行/按条目/截图墙' && !a1.kindDemo)
    ? ok('A1 六组筛选＋四视图＋计数行到位，kind 钮不再是演示', a1.cnt) : bad('A1', JSON.stringify(a1));

  /* A2 类型／kind／条目三 chip 各真生效（期望值现算） */
  const a2 = await ev(`var o={};
    [['#mNoteTypeChips','台词','type','line'],['#mNoteKindChips','剧集','kind','series'],['#mNoteItemChips','《范特西》','itemId','mu1']].forEach(function(p){
      __chip(p[0],p[1]);o[p[1]]={n:__nb().length,exp:__live().filter(function(x){return x[p[2]]===p[3]}).length,cnt:__cnt(),expCnt:__exp(function(x){return x[p[2]]===p[3]}),
        on:[].slice.call(document.querySelectorAll(p[0]+' .mds-chip')).filter(function(b){return b.textContent===p[1]})[0].className.indexOf('on')>=0};
      document.querySelector(p[0]+' .mds-chip').click();});
    return o;`);
  (['台词', '剧集', '《范特西》'].every(k => a2[k].n === a2[k].exp && a2[k].cnt === a2[k].expCnt && a2[k].on && a2[k].n > 0))
    ? ok('A2 类型/kind/条目 chip 是真筛选（选中态可辨·行数与现算期望等）', ['台词', '剧集', '《范特西》'].map(k => a2[k].n).join('/')) : bad('A2', JSON.stringify(a2));

  /* A3 关键词命中正文／条目名／批注三条路，搜不到＝0 行 */
  const a3 = await ev(`var q=document.getElementById('mNoteQ'),o={};
    [['锈带','body'],['方文山的词','body'],['奥本海默','title'],['一周后再看','thought'],['zz不存在词','none']].forEach(function(p){
      q.value=p[0];mNoteQ=p[0];mRenderNotes();o[p[0]]={n:__nb().length,empty:!!document.querySelector('#mNotesBody .mempty')};});
    q.value='';mNoteQ='';mRenderNotes();return o;`);
  (a3['锈带'].n === 1 && a3['方文山的词'].n === 1 && a3['奥本海默'].n === 1 && a3['一周后再看'].n === 1 && a3['zz不存在词'].n === 0 && a3['zz不存在词'].empty)
    ? ok('A3 关键词三处入口（正文/条目名/批注）均命中，无命中出「当前筛选没有笔记」虚线件') : bad('A3', JSON.stringify(a3));

  /* A4 标星 toggle 与「只看看过的」 */
  const a4 = await ev(`var b=document.getElementById('mNoteStarChip');b.click();
    var r={n:__nb().length,cnt:__cnt(),exp:__exp(function(x){return x.starred}),on:b.className.indexOf('on')>=0,
      allStar:__nb().every(function(el){return /取消标星/.test(el.textContent)})};
    b.click();return r;`);
  (a4.n > 0 && a4.n === Number(a4.cnt.split('条')[0]) && a4.cnt === a4.exp && a4.on && a4.allStar)
    ? ok('A4 标星 toggle 生效（计数行跟着走·筛出的全是标星行）', a4.cnt) : bad('A4', JSON.stringify(a4));

  /* A5 标签 chip 生效 */
  const a5 = await ev(`var tg=[].slice.call(document.querySelectorAll('#mNoteTagChips .mds-chip')).map(function(b){return b.textContent});
    var lb=tg.filter(function(t){return t!=='不限标签'})[0];__chip('#mNoteTagChips',lb);
    var r={lb:lb,n:__nb().length,cnt:__cnt(),expN:__expN(function(x){return x.tag===lb}),exp:__exp(function(x){return x.tag===lb}),tags:tg.length};
    document.querySelector('#mNoteTagChips .mds-chip').click();return r;`);
  (a5.tags > 1 && a5.n === a5.expN && a5.cnt === a5.exp) ? ok('A5 标签 chip 由实际标签生成并生效（' + a5.lb + '＝' + a5.n + ' 条）') : bad('A5', JSON.stringify(a5));

  /* A6 四视图同一条数；按条目带分组小计；截图墙标出无截图 */
  const a6 = await ev(`var n0=__live().length,o={};
    [['卡片','card'],['行','list'],['按条目','byitem'],['截图墙','wall']].forEach(function(p){mNoteView=p[1];mRenderNotes();
      o[p[0]]={rows:__nb().length};
      if(p[1]==='byitem'){o[p[0]].groups=document.querySelectorAll('#mNotesBody > div.mb-3').length;
        o[p[0]].sub=([].slice.call(document.querySelectorAll('#mNotesBody > div.mb-3')).every(function(d){return d.firstElementChild.textContent.indexOf('条')>=0}));}
      if(p[1]==='wall')o[p[0]].noimg=(document.getElementById('mNotesBody').textContent.match(/无截图/g)||[]).length;});
    mNoteView='card';mRenderNotes();
    o.expN=n0;o.expGroups=(function(){var s={};__live().forEach(function(x){s[x.itemId]=1});return Object.keys(s).length})();
    o.expNoimg=__live().filter(function(x){return !x.img}).length;return o;`);
  (['卡片', '行', '按条目', '截图墙'].every(k => a6[k].rows === a6.expN) && a6['按条目'].groups === a6.expGroups && a6['按条目'].sub && a6['截图墙'].noimg === a6.expNoimg)
    ? ok('A6 四视图同数（' + a6.expN + ' 条），按条目分 ' + a6['按条目'].groups + ' 组各带条数小计，截图墙如实标 ' + a6['截图墙'].noimg + ' 张无截图') : bad('A6', JSON.stringify(a6));

  /* A7 色标按类型落位（行左边框＝词典色） */
  const a7 = await ev(`var okc=0,bad2=[];
    __nb().forEach(function(el){var id=__rid(el),n=MNOTES.find(function(x){return x.id===id});
      var c=getComputedStyle(el).borderLeftColor;if(c===__hex(MTYPE_COLOR[n.type]))okc++;else bad2.push(n.type+':'+c);});
    return {ok:okc,total:__nb().length,bad:bad2.slice(0,2)};`);
  (a7.ok === a7.total && a7.total > 0) ? ok('A7 每一行的色标都等于其类型色（' + a7.ok + '/' + a7.total + '）') : bad('A7', JSON.stringify(a7));

  /* A8 行内「标星」就地改档，不跳页也不弹复习 */
  const a8 = await ev(`var el=__nb().filter(function(x){return /(^|>)标星</.test(x.innerHTML)||/标星/.test(x.textContent)})[0];
    el=__nb().filter(function(x){var i=__rid(x);return MNOTES.find(function(n){return n.id===i}).starred===0})[0];
    if(!el)return {skip:'无未标星行'};
    var id=__rid(el),r0=el.innerHTML.length;var before=curPage;__act(el,'标星').click();
    var after=__nb().filter(function(x){return __rid(x)===id})[0];
    return {page:curPage,star:MNOTES.find(function(n){return n.id===id}).starred,nowLabel:after?__act(after,'取消标星')?'已翻成取消标星':'没翻':'行没了',
      sheetOpen:!document.getElementById('m-review').classList.contains('hidden'),cntAfter:__cnt()};`);
  (!a8.skip && a8.page === 'm-notes' && a8.star === 1 && a8.nowLabel === '已翻成取消标星' && !a8.sheetOpen)
    ? ok('A8 行内标星就地改档·不跳页·不弹复习（复习只在点行时发生）') : bad('A8', JSON.stringify(a8));

  /* A9 删除：确认框取消＝不删；确认＝行与计数同帧减一，条目时间线同步只数未删 */
  const a9 = await ev(`var el=__nb()[0],id=__rid(el);
    window.confirm=function(){return false};__act(el,'删除').click();
    var noDel=__nb().length;
    window.confirm=function(){return true};var el2=__nb().filter(function(x){return __rid(x)===id})[0];__act(el2,'删除').click();
    mCurDetail=MDEMO.find(function(k){return k.id===MNOTES.find(function(n){return n.id===id}).itemId});mRenderDetail();
    return {before:noDel,after:__nb().length,cnt:__cnt(),exp:__exp(),gone:!!MNOTES.find(function(n){return n.id===id}).gone,
      inDetail:new RegExp(id).test('0')||document.getElementById('mdsDetailBody').textContent.indexOf(MNOTES.find(function(n){return n.id===id}).body.slice(0,6))>=0};`);
  (a9.before > a9.after && a9.cnt === a9.exp && a9.gone && !a9.inDetail)
    ? ok('A9 删除走确认（取消不删）·确认后行 ' + a9.before + '→' + a9.after + ' 且计数同帧·条目时间线不再显示') : bad('A9', JSON.stringify(a9));

  /* A10 复习角标＝到期条数，实时重算 */
  const a10 = await ev(`var b=document.getElementById('mNoteRevBadge');return {t:b.textContent,shown:b.style.display!=='none',due:__due()};`);
  (a10.shown && a10.t === String(a10.due) && a10.due > 0) ? ok('A10 顶栏「复习」角标＝到期条数（' + a10.t + ' 条）') : bad('A10', JSON.stringify(a10));

  /* A11 复习卡：正面只给画面，翻面才给出处＋批注；未写批注走虚线 */
  const a11 = await ev(`mOpenReview('due');var q=mRevQueue.length;
    var f0=document.getElementById('mdsRevFront').textContent;
    var pre={open:!document.getElementById('m-review').classList.contains('hidden'),pos:document.getElementById('mRevPos').textContent,
      frontHasBody:q>0&&f0.indexOf(mRevQueue[0].body.slice(0,8))>=0,
      srcLeak:/出处|《/.test(f0)||new RegExp(mRevQueue[0].title.slice(0,4)).test(f0),flip:document.getElementById('mdsRevCard').classList.contains('flipped')};
    mFlipReview();
    var bk=document.getElementById('mdsRevBack').textContent;
    return {pre:pre,flip:document.getElementById('mdsRevCard').classList.contains('flipped'),hasSrc:/出处/.test(bk),hasAnno:/我的批注/.test(bk),
      dashed:/未写批注/.test(bk),q:q};`);
  (a11.pre.open && a11.q > 0 && !a11.pre.srcLeak && !a11.pre.flip && a11.flip && a11.hasSrc && a11.hasAnno)
    ? ok('A11 翻面前不出出处，翻面后「出处＋我的批注」同屏' + (a11.dashed ? '（未写批注者出虚线位）' : ''), '队列 ' + a11.q + ' 条') : bad('A11', JSON.stringify(a11));

  /* A12 档位三 chip＋「记住了」推档摘队＋「跳过」不动档 */
  const a12 = await ev(`var chips=[].slice.call(document.querySelectorAll('#mRevStageChips .mds-chip'));
    var labels=chips.map(function(c){return c.textContent}).join('/');
    var id=mRevQueue[mRevIdx].id,r0=MNOTES.find(function(n){return n.id===id}).rev,q0=mRevQueue.length;
    mReviewDone();var afterDone={q:mRevQueue.length,rev:MNOTES.find(function(n){return n.id===id}).rev,r0:r0,toast:__toast()};
    var id2=mRevQueue[mRevIdx].id,r2=MNOTES.find(function(n){return n.id===id2}).rev;
    mReviewSkip();
    return {n:chips.length,labels:labels,q0:q0,afterDone:afterDone,kept:MNOTES.find(function(n){return n.id===id2}).rev===r2,q2:mRevQueue.length};`);
  (a12.n === 3 && /1 天/.test(a12.labels) && /3 天/.test(a12.labels) && /7 天/.test(a12.labels)
    && a12.afterDone.q === a12.q0 - 1 && a12.afterDone.rev === a12.afterDone.r0 + 1 && a12.kept && a12.q2 === a12.afterDone.q - 1)
    ? ok('A12 三档 1/3/7 在位·「记住了」推一档并摘队·「跳过」只出下一条不动档', a12.afterDone.toast) : bad('A12', JSON.stringify(a12));

  /* A13 队列走完＝虚线空态（卡片整块收起，不摆假数据） */
  const a13 = await ev(`while(mRevQueue.length)mReviewSkip();
    return {wrapOff:document.getElementById('mRevWrap').style.display==='none',
      shown:!document.getElementById('mRevEmpty').classList.contains('hidden'),
      txt:document.getElementById('mRevEmpty').textContent.replace(/\s+/g,''),
      dash:getComputedStyle(document.getElementById('mRevEmpty')).borderBottomStyle};`);
  (a13.wrapOff && a13.shown && a13.txt === '今天没有到期的复习' && a13.dash === 'dashed')
    ? ok('A13 复习走空＝虚线「今天没有到期的复习」，卡片收起不编数', a13.dash) : bad('A13', JSON.stringify(a13));
  await shot('mb5-review-empty');

  /* A14 点行＝单条复习（只这一条·位置写「单条」·不蹭档位） */
  const SNAP = await ev(`return {s:__snap()}`);
  const a14b = await ev(`__restore(${JSON.stringify(SNAP.s)});navTab('m-notes');
    var el=__nb()[0],id=__rid(el),r0=MNOTES.find(function(n){return n.id===id}).rev;el.click();
    var q=mRevQueue.length,pos=document.getElementById('mRevPos').textContent;mReviewDone();
    return {q:q,pos:pos,kept:MNOTES.find(function(n){return n.id===id}).rev===r0,open:!document.getElementById('m-review').classList.contains('hidden')};`);
  (a14b.q === 1 && a14b.pos === '单条' && a14b.kept && a14b.open)
    ? ok('A14 点笔记行＝单条复习（位置「单条」·看完不推档）') : bad('A14', JSON.stringify(a14b));

  /* A15 录入面：条目预选＋五类色标类型＋单位提示随 kind＋创建时间默认现在＋识图置灰不隐藏＋附件可× */
  const a15 = await ev(`__restore(${JSON.stringify(SNAP.s)});closeSheet('m-review');mOpenNoteEdit('mu1');
    var on=[].slice.call(document.querySelectorAll('#mdsNoteItemChips .mds-chip')).filter(function(b){return b.className.indexOf('on')>=0}).map(function(b){return b.textContent}).join('');
    var tc=[].slice.call(document.querySelectorAll('#mdsNoteTypeChips .mds-chip'));
    var kinds={};[['mv1','movie'],['tv1','series'],['mu1','music'],['gm1','game']].forEach(function(p){mOpenNoteEdit(p[0]);kinds[p[1]]=document.getElementById('mdNoteUnit').placeholder});
    var bs=[].slice.call(document.querySelectorAll('#m-sheet-note-edit .mds-chip'));
    var ocr=bs.filter(function(b){return b.textContent==='识图'})[0];
    var ta=document.getElementById('mdNoteBody');ta.value='';mNotePaste();var pasted=ta.value.length>0;
    mNoteAddImg();mNoteAddImg();
    return {on:on,types:tc.length,colored:tc.every(function(b){return /border-left/.test(b.getAttribute('style')||'')}),
      fields:['mdNoteUnit','mdNoteAt','mdNoteBody','mdNoteAnno','mdNoteTag','mdNoteWhen'].filter(function(i){return document.getElementById(i)}).length,
      when:document.getElementById('mdNoteWhen').value,kinds:kinds,
      ocr:!!ocr,op:ocr?getComputedStyle(ocr).opacity:'',title:ocr?ocr.title:'',pasted:pasted,
      imgs:document.querySelectorAll('#mdNoteImgs > div').length,x:document.querySelectorAll('#mdNoteImgs button').length};`);
  (a15.on === '《范特西》' && a15.types === 5 && a15.colored && a15.fields === 6 && a15.when === '现在'
    && !/曲目/.test(a15.kinds.movie) && /第.*集/.test(a15.kinds.series) && /曲目/.test(a15.kinds.music) && /章节|周目/.test(a15.kinds.game)
    && a15.ocr && Number(a15.op) <= 0.6 && /识别库|暂不可用/.test(a15.title) && a15.pasted && a15.imgs === 2 && a15.x === 2)
    ? ok('A15 录入面＝条目预选＋五色标类型＋单位随 kind 四套＋创建时间默认现在；识图置灰不隐藏；粘贴与附件可×', a15.kinds.movie + '/' + a15.kinds.game) : bad('A15', JSON.stringify(a15));

  /* A16 空正文＝校验红字贴在字段旁（LH-K32）；补正文后保存＝列表与计数同帧 +1 且落对条目 */
  const a16 = await ev(`mOpenNoteEdit('mv1','line');var ta=document.getElementById('mdNoteBody');ta.value='  ';
    document.getElementById('mdNoteErr').classList.add('hidden');mNoteSave();
    var err=document.getElementById('mdNoteErr'),r1=err.getBoundingClientRect(),r2=ta.getBoundingClientRect();
    var bad={shown:!err.classList.contains('hidden'),txt:err.textContent.replace(/\s+/g,''),near:Math.abs(r1.top-r2.bottom)<40,toast:__toast()};
    var c0=__cnt();ta.value='保罗驯沙虫那段，声音全剪掉只剩沙暴。';document.getElementById('mdNoteAt').value='1:12:40';mNoteSave();
    navTab('m-notes');
    return {bad:bad,c0:c0,c1:__cnt(),hidden:document.getElementById('m-sheet-note-edit').classList.contains('hidden'),
      top:MNOTES[0]?{kind:MNOTES[0].kind,item:MNOTES[0].itemId,type:MNOTES[0].type,at:MNOTES[0].at,rev:MNOTES[0].rev}:null,
      inList:/保罗驯沙虫/.test(document.getElementById('mNotesBody').textContent)};`);
  (a16.bad.shown && a16.bad.txt === '先写正文' && a16.bad.near
    && a16.c1 === __a16exp(a16) && a16.hidden && a16.inList && a16.top && a16.top.item === 'mv1' && a16.top.type === 'line' && a16.top.at === '1:12:40' && a16.top.rev === 0)
    ? ok('A16 空正文就地报错（不弹提示条）；保存即落该条目·四视图与计数同帧 +1', a16.c0 + '→' + a16.c1) : bad('A16', JSON.stringify(a16));

  /* A17 唯一录入面：详情与计时页两个入口都走 mOpenNoteEdit；→日记／→待办 联动口在位 */
  const a17 = await ev(`navTab('m-shelf');mOpen('mv1');
    var d=[].slice.call(document.querySelectorAll('#mdsDetailBody .mds-chip')).map(function(b){return b.getAttribute('onclick')||''});
    var t=document.querySelector("#m-timer [onclick*='mOpenNoteEdit']");
    mOpenNoteEdit('mv1');var lb=[].slice.call(document.querySelectorAll('#m-sheet-note-edit .mds-chip')).map(function(b){return b.textContent});
    return {detail:d.filter(function(o){return /mOpenNoteEdit/.test(o)}).length,bare:d.filter(function(o){return /openSheet..m-sheet-note-edit/.test(o)}).length,
      timer:!!t,diary:lb.some(function(x){return /日记/.test(x)}),todo:lb.some(function(x){return /待办/.test(x)})};`);
  (a17.detail === 1 && a17.bare === 0 && a17.timer && a17.diary && a17.todo)
    ? ok('A17 两处入口都走同一录入面（无裸开弹层残留），→日记／→待办 联动口在位') : bad('A17', JSON.stringify(a17));

  /* A18 空库虚线话术 ≠ 筛选无命中话术（两种空态分得开） */
  const a18 = await ev(`var keep=MNOTES.slice();MNOTES.length=0;mRenderNotes();
    var b=document.getElementById('mNotesBody');
    var e1={txt:b.textContent.replace(/\s+/g,''),rows:b.querySelectorAll('.mrow').length,dash:b.querySelector('.mempty')?getComputedStyle(b.querySelector('.mempty')).borderBottomStyle:''};
    MNOTES.push.apply(MNOTES,keep);mNoteKind='game';mNoteType='lyric';mRenderNotes();
    var b2=document.getElementById('mNotesBody');var e2={txt:b2.textContent.replace(/\s+/g,'')};
    mNoteKind='all';mNoteType='all';mRenderNotes();return {e1:e1,e2:e2};`);
  (a18.e1.rows === 0 && /还没有影音笔记/.test(a18.e1.txt) && a18.e1.dash === 'dashed' && a18.e2.txt === '当前筛选没有笔记' && a18.e1.txt !== a18.e2.txt)
    ? ok('A18 两种空态各说各话（空库＝引导记一条；筛空＝当前筛选没有笔记）') : bad('A18', JSON.stringify(a18));

  /* A19 收尾一致性：恢复演示行后列表/计数/角标同口径，架面与详情不回归 */
  const a19 = await ev(`__restore(${JSON.stringify(SNAP.s)});
    var r={cnt:__cnt(),rows:__nb().length,exp:__exp(),badge:document.getElementById('mNoteRevBadge').textContent,due:__due()};
    navTab('m-shelf');mOpen('mv1');r.detail=/名场面时间线/.test(document.getElementById('mdsDetailBody').textContent);
    r.shelf=document.querySelectorAll('#mShelfBody .mds-item').length;return r;`);
  (a19.rows === a19.cnt.split('条')[0] * 1 && a19.cnt === a19.exp && a19.badge === String(a19.due) && a19.detail && a19.shelf >= 8)
    ? ok('A19 恢复后列表·计数·角标同口径，架面与详情未回归', a19.cnt + ' · 角标 ' + a19.badge) : bad('A19', JSON.stringify(a19));

  const pe = errs.filter(e => !/lh-gov|init skip/.test(e));
  (pe.length === 0 ? ok : bad)('Z0 PAGE ERRORS', pe.length ? pe.join(' || ') : '0');

  finish();
})().catch(e => { bad('工装异常 ' + e.message); finish() });

/* A16 期望值现算：保存后＝保存前行数 +1，标星数不变 */
function __a16exp(o) { const n = Number(o.c0.split('条')[0]), s = (o.c0.match(/标星(\d+)/) || [])[1]; return (n + 1) + '条·标星' + s }

function finish() { try { if (ws) ws.close() } catch (e) { } try { chrome && chrome.kill() } catch (e) { }
  log('---- media_b5check: ' + pass + '/' + (pass + fail) + ' 绿 ----');
  process.exit(fail ? 1 : 0);
}
