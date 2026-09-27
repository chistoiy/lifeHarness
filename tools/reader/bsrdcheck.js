/* 书架专版·阅读器（V1.50 · V1.51 目录侧边抽屉）回归校验 · CDP 无头
 * 用法：node --experimental-websocket tools/reader/bsrdcheck.js [--shots] */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE=path.resolve('prototype/index-bookshelf.html');
const URLF=url.pathToFileURL(FILE).href;
const PORT=Number(process.env.BSRD_PORT||9527);
const SHOTS=process.env.BSRD_SHOTS==='1';
const SHOTDIR='prototype/shots/reader';
const LOG='tools/reader/bsrd-run.log';
let pass=0,fail=0;const errs=[];
const log=m=>{fs.appendFileSync(LOG,m+'\n');console.log(m)};
fs.writeFileSync(LOG,'== bsrdcheck start '+new Date().toISOString()+' ==\n');
const ok=(n,i)=>{pass++;log('PASS '+n+(i?'  →  '+i:''))};
const bad=(n,i)=>{fail++;log('FAIL '+n+'  →  '+(i||''))};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function get(u){return new Promise(res=>{try{http.get(u,r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>res(d))}).on('error',()=>res(null))}catch(e){res(null)}})}
let ws,idc=0;const pend=new Map();
function cmd(method,params,target){return new Promise(res=>{const id=++idc;pend.set(id,res);
  (target||ws).send(JSON.stringify({id,method,params:params||{}}))})}
async function ev(expr){const m=await cmd('Runtime.evaluate',{expression:'JSON.stringify((function(){'+expr+'})())',returnByValue:false});
  const r=m.result&&m.result.result;try{return JSON.parse(r.value)}catch(e){return {__err:(r&&r.value)||JSON.stringify(m).slice(0,220)}}}
async function shot(name){if(!SHOTS)return;fs.mkdirSync(SHOTDIR,{recursive:true});const m=await cmd('Page.captureScreenshot',{format:'png'});
  if(m.result&&m.result.data)fs.writeFileSync(path.join(SHOTDIR,name+'.png'),Buffer.from(m.result.data,'base64'))}
const LEAK='/(^|[\\s>])(ring-|bg-(slate|indigo|white|black|brand|emerald|amber|rose|sky|teal)|text-(slate|white|brand|rose|amber|emerald)|border-|rounded-|font-|dark:)/';
async function assertPage(p,render,minLen){
  const r=await ev(`setPage('${p}');var el=document.getElementById('${p}');if(window.${render})window.${render}();var t=(el.innerText||'');
    var leak=0;el.querySelectorAll('*').forEach(function(e){for(var i=0;i<e.childNodes.length;i++){var n=e.childNodes[i];if(n.nodeType===3&&new RegExp(${JSON.stringify(LEAK)}).test(n.nodeValue))leak++}});
    return {len:t.length,badWord:(t.match(/undefined|NaN|\\[object/g)||[]).length,leak:leak}`);
  if(r.__err)return bad('屏 '+p,r.__err);
  (r.len>(minLen||100)&&r.badWord===0&&r.leak===0)?ok('屏 '+p,'文本'+r.len+' · 泄漏0 · 假值0'):bad('屏 '+p,JSON.stringify(r));
  await shot('bs-'+p)}

(async()=>{
 if(!fs.existsSync(CHROME)){bad('chrome 存在');return finish()}
 log('launch chrome · port '+PORT);
 const chrome=spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,
  '--user-data-dir='+path.resolve('tools/reader/.bsrd-profile'),'--disable-extensions','--no-default-browser-check',
  '--window-size=430,900','--allow-file-access-from-files','about:blank'],{stdio:'ignore'});
 let data=null;
 for(let i=0;i<60;i++){const d=await get('http://127.0.0.1:'+PORT+'/json');if(d){try{data=JSON.parse(d);if(data.some(x=>x.type==='page'))break}catch(e){}}await wait(300)}
 const pg=data.find(t=>t.type==='page');
 ws=new WebSocket(pg.webSocketDebuggerUrl);
 await new Promise(r=>{ws.addEventListener('open',r);setTimeout(r,3000)});
 ws.addEventListener('message',e2=>{const m=JSON.parse(e2.data);
  if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}
  if(m.method==='Runtime.exceptionThrown')errs.push(((m.params.exceptionDetails.exception||{}).description||'').slice(0,260))});
 await cmd('Runtime.enable');await cmd('Page.enable');
 await cmd('Page.navigate',{url:URLF});await wait(2800);
 const boot=await ev(`return {bs:typeof brBoot==='undefined'&&BS_BOOKS.length,b1:bsBook('b1').local,fn:typeof brOpen==='function'}`);
 (boot.fn&&boot.b1===1)?ok('启动·b1 已挂本地文件','BS_BOOKS='+boot.bs):bad('启动',JSON.stringify(boot));
 /* 导入：新书 */
 await cmd('Runtime.evaluate',{expression:"navTo('p-localImport');brImpGo(2)"});await wait(150);
 const n0=await ev(`return BS_BOOKS.length`);
 await cmd('Runtime.evaluate',{expression:"brImpPick('download',0)"});await wait(3600);
 const meta=await ev(`return {step:brImp.step,t:document.getElementById('brF_t').value,dup:!document.getElementById('brDup').classList.contains('hidden')}`);
 (meta.step===4&&meta.t==='克拉拉与太阳'&&!meta.dup)?ok('导入·解析与元信息',JSON.stringify(meta)):bad('导入·解析',JSON.stringify(meta));
 await shot('bs-import-meta');
 const nc=await ev(`brImpCommit();var b=BS_BOOKS[BS_BOOKS.length-1];return {n:BS_BOOKS.length,local:b.local,tags:b.tags,toc:(BS_TOC[b.id]||[]).length,hasToc:brLeaves(b.id).length}`);
 (nc.n===n0+1&&nc.local===1&&nc.tags.includes('本地')&&nc.hasToc===12)?ok('导入·入库+本地标签',JSON.stringify(nc)):bad('导入·入库',JSON.stringify(nc));
 const newId=await ev(`return BS_BOOKS[BS_BOOKS.length-1].id`);
 /* 导入：合并到已有记录 */
 await cmd('Runtime.evaluate',{expression:"navTo('p-localImport');brImpGo(2);brImpPick('download',1)"});await wait(3600);
 const mg=await ev(`return {step:brImp.step,dup:!document.getElementById('brDup').classList.contains('hidden'),btn:document.getElementById('brSaveBtn').textContent}`);
 (mg.step===4&&mg.dup&&mg.btn.includes('合并'))?ok('导入·同书合并守卫',JSON.stringify(mg)):bad('导入·合并',JSON.stringify(mg));
 const mg2=await ev(`brImpCommit();return {n:BS_BOOKS.length,b1:bsBook('b1').local}`);
 (mg2.n===n0+1&&mg2.b1===1)?ok('导入·合并落库'):bad('导入·合并2',JSON.stringify(mg2));
 /* DRM / PDF 拦截 */
 const blk=await ev(`var s=brImp.step;brImpPick('download',2);var a=brImp.step;brImpPick('docs',1);return {blocked:a===s&&brImp.step===s}`);
 blk.blocked?ok('DRM/PDF 拦截'):bad('拦截',JSON.stringify(blk));
 await cmd('Runtime.evaluate',{expression:"brImpGo(1)"});
 /* 书架本地标识 */
 const bdg=await ev(`setPage('p-bookshelf');renderShelf();return document.querySelectorAll('#p-bookshelf .br-local').length`);
 bdg>=1?ok('书架封面本地徽标',bdg+' 枚'):bad('本地徽标',JSON.stringify(bdg));
 /* 点击直达阅读 */
 const op=await ev(`shOpen('b1');return {p:curPage,timer:!!timer,tgt:timerTarget}`);
 (op.p==='p-readerPage'&&op.timer&&op.tgt.includes('思考'))?ok('点击本地书→直达阅读+自动计时',op.tgt):bad('直达',JSON.stringify(op));
 await wait(200);await shot('bs-reader');
 const rp=await ev(`return {len:document.getElementById('brBody').innerText.length,cfi:document.getElementById('brCfi').textContent}`);
 rp.len>60?ok('阅读主屏渲染','CFI '+rp.cfi):bad('渲染',JSON.stringify(rp));
 const fl=await ev(`var c=brV.ci;brFlip(1);return {moved:brV.ci!==c||brV.pg>0}`);
 fl.moved?ok('翻页跨页'):bad('翻页',JSON.stringify(fl));
 /* 划词→划线书摘 */
 const q0=await ev(`return BS_QUOTES.length`);
 await cmd('Runtime.evaluate',{expression:"brV.ci=0;brV.pg=0;brRenderPage();brSelect(1,2)"});await wait(150);
 const sb=await ev(`return {vis:!document.getElementById('brSelBar').classList.contains('hidden'),acts:document.getElementById('brSelActs').children.length}`);
 (sb.vis&&sb.acts>=9)?ok('划词菜单 7 操作+前后扩',JSON.stringify(sb)):bad('划词',JSON.stringify(sb));
 await shot('bs-select');
 const hl=await ev(`brAddHl('重点');var q=BS_QUOTES[0];return {d:BS_QUOTES.length-${q0},tg:q.tg,src:q.src,cf:!!q.cf,ch:q.ch,bq:bsBook('b1').q}`);
 (hl.d===1&&hl.tg==='重点'&&hl.src==='阅读器'&&hl.cf)?ok('划线=书摘（同库同源）',JSON.stringify(hl)):bad('划线书摘',JSON.stringify(hl));
 const hlv=await ev(`return document.querySelectorAll('#brBody p[style*="6366f1"]').length`);
 hlv>=1?ok('高亮渲染回显',hlv+' 段'):bad('高亮渲染',JSON.stringify(hlv));
 const dl=await ev(`var before=BS_QUOTES.length;brV.ci=0;brSelect(1,2);brDelHl();return BS_QUOTES.length-before`);
 dl===-1?ok('删划线同步移除书摘'):bad('删划线',JSON.stringify(dl));
 /* 书摘表单对接 */
 const qe=await ev(`brSelect(3,3);brToQuote();return {p:curPage,txt:document.getElementById('qeText').value.length,pg:document.getElementById('qePg').value,ch:document.getElementById('qeCh').value}`);
 (qe.p==='p-quoteEdit'&&qe.txt>10&&qe.ch.includes('两位主角'))?ok('添加书摘→既有摘录表单',JSON.stringify(qe).slice(0,120)):bad('书摘表单',JSON.stringify(qe));
 const qs=await ev(`var n=BS_QUOTES.length;qeSave();return {d:BS_QUOTES.length-n,back:curPage}`);
 (qs.d===1&&qs.back==='p-readerPage')?ok('摘录保存→回阅读页',JSON.stringify(qs)):bad('摘录保存',JSON.stringify(qs));
 /* AI 解读 */
 await cmd('Runtime.evaluate',{expression:"brSelect(1,1);brAiOpen()"});await wait(1800);
 const ai=await ev(`return brAI.text.length>60`);
 ai?ok('AI 流式解读'):bad('AI');
 const aq=await ev(`brAiToQuote();var v=document.getElementById('qeThink').value;qeSave();return {ok:v.includes('AI 解读'),p:curPage}`);
 (aq.ok&&aq.p==='p-readerPage')?ok('AI→存为感想书摘'):bad('AI→书摘',JSON.stringify(aq));
 /* 目录 · V1.51 侧边抽屉（微信读书式） */
 const toc=await ev(`brTocOpen();return {open:!document.getElementById('brTocDrawer').classList.contains('hidden'),rows:document.querySelectorAll('#brTocList [onclick^="brGotoCh"]').length,cur:!!document.querySelector('#brTocList [data-cur]'),tabs:document.getElementById('brDrTabs').children.length}`);
 (toc.open&&toc.rows>=14&&toc.cur&&toc.tabs===2)?ok('目录抽屉·打开/当前行/双Tab',JSON.stringify(toc)):bad('目录抽屉',JSON.stringify(toc));
 await wait(350);
 await shot('bs-toc-drawer');
 await cmd('Runtime.evaluate',{expression:"brTocOpen('search');document.getElementById('brDrQ').value='折扣';brDrSearch()"});await wait(400);await shot('bs-toc-drawer-search');
 await cmd('Runtime.evaluate',{expression:"brDrTab('toc');brDrCollapse()"});await wait(400);await shot('bs-toc-drawer-rail');
 await cmd('Runtime.evaluate',{expression:"brDrExpand();brTocClose()"});await wait(300);
 const fold=await ev(`brDrFold(0);var a=document.querySelectorAll('#brTocList [onclick^="brGotoCh"]').length;brDrFold(0);var b2=document.querySelectorAll('#brTocList [onclick^="brGotoCh"]').length;return {folded:a,shown:b2}`);
 (fold.folded<fold.shown&&fold.shown>=14)?ok('分组折叠隐藏子项',JSON.stringify(fold)):bad('分组折叠',JSON.stringify(fold));
 const srch=await ev(`brDrTab('search');document.getElementById('brDrQ').value='损失厌恶';brDrSearch();return {hits:document.querySelectorAll('#brDrHits button').length,tocHidden:document.getElementById('brTocList').classList.contains('hidden')}`);
 (srch.hits>=1&&srch.tocHidden)?ok('搜本书Tab·抽屉内命中',JSON.stringify(srch)):bad('抽屉检索',JSON.stringify(srch));
 const sj=await ev(`brDrHitGo(0);return {p:curPage,out:document.getElementById('brDrPanel').classList.contains('out'),lbl:document.getElementById('brHitsLbl').textContent}`);
 (sj.p==='p-readerPage'&&sj.out&&sj.lbl.includes('处'))?ok('抽屉命中跳转·抽屉自动收起',sj.lbl):bad('抽屉跳转',JSON.stringify(sj));
 const rail=await ev(`brTocOpen();brDrCollapse();var r=!document.getElementById('brDrRail').classList.contains('hidden')&&document.getElementById('brDrWide').classList.contains('hidden');brDrExpand();var w=!document.getElementById('brDrWide').classList.contains('hidden');brTocClose();return {rail:r,wide:w}`);
 (rail.rail&&rail.wide)?ok('折叠到边栏⇄展开'):bad('边栏',JSON.stringify(rail));
 const bm=await ev(`brTocOpen();brAddBookmark();var v=brPos['b1'].bm;brTocClose();return Array.isArray(v)&&v.length===3`);
 bm?ok('当前读到行·添加书签落位'):bad('书签',JSON.stringify(bm));
 const img=await ev(`brGotoCh(7);return {ch:brLeaves('b1')[brV.ci],fig:document.querySelectorAll('#brBody .brp-i').length}`);
 (img.ch==='8 时间折扣'&&img.fig===1)?ok('图文混排·书内插图',img.ch):bad('插图',JSON.stringify(img));
 const iv=await ev(`brImgOpen('图 8-1');return !document.getElementById('sheetBrImg').classList.contains('hidden')`);
 iv?ok('图片放大查看'):bad('图片');
 await cmd('Runtime.evaluate',{expression:"closeSheet('sheetBrImg')"});
 const lk=await ev(`rsChip('brLink','询问');brExtLink('https://x.test');return !document.getElementById('sheetBrLink').classList.contains('hidden')`);
 lk?ok('外链询问弹层'):bad('外链');
 await cmd('Runtime.evaluate',{expression:"closeSheet('sheetBrLink');rsChip('brLink','禁止');brExtLink('https://x.test');rsChip('brLink','询问');return 1"});
 /* 外观草稿+逐书记忆 */
 const ap0=await ev(`return brTotal('b1')`);
 await cmd('Runtime.evaluate',{expression:"brApOpen();brApSet('fs',28)"});await wait(150);await shot('bs-appearance');
 const ap1=await ev(`brApSave();return brTotal('b1')`);
 (ap1>ap0)?ok('外观草稿保存→重排页数',ap0+'→'+ap1):bad('外观',ap0+'→'+ap1);
 await cmd('Runtime.evaluate',{expression:"brApOpen();brApSet('fs',19);brApSave()"});
 const th=await ev(`brThemeCycle();return brCfg.theme`);
 th==='eye'?ok('主题循环'):bad('主题',th);
 await cmd('Runtime.evaluate',{expression:"brThemeCycle();brThemeCycle()"});
 /* 离开结算 */
 const lv=await ev(`brOpen('b1');var b=bsBook('b1');var m0=b.min,t0=b.times;b.min=b.min;document.getElementById('timerSec').textContent='2:05';brLeave();return {p:curPage,dm:b.min-m0,dt:b.times-t0,timer:!!timer}`);
 (lv.dm>=2&&lv.dt===1&&!lv.timer)?ok('退出结算→时长/次数/进度入既有模型',JSON.stringify(lv)):bad('结算',JSON.stringify(lv));
 /* 详情卡 */
 const dc=await ev(`brOpenDetail();return {p:curPage,card:!!document.getElementById('brDcard')}`);
 (dc.p==='p-bookDetail'&&dc.card)?ok('详情页本地 EPUB 卡'):bad('详情卡',JSON.stringify(dc));
 /* 删除本地书 */
 const del=await ev(`brDelOpen('${newId}');brDelCommit();return bsBook('${newId}').local`);
 del===0?ok('删除·仅清阅读数据保留源文件'):bad('删除',JSON.stringify(del));
 /* 设置分组 */
 const se=await ev(`navTo('p-readset');rsPickTab(RS_SEC.length-1);var t=document.getElementById('p-readset').innerText;return {grp:t.includes('本地阅读器'),epub:t.includes('导入本地 EPUB'),link:t.includes('书籍内外部链接')}`);
 (se.grp&&se.epub&&se.link)?ok('阅读设置·本地阅读器分组'):bad('设置组',JSON.stringify(se));
 /* 检索 */
 await cmd('Runtime.evaluate',{expression:"CURBK='b1';navTo('p-readerSearch');document.getElementById('brSq').value='折扣';brSearchRender()"});await wait(150);
 const s=await ev(`return document.getElementById('brSHits').children.length`);
 s>2?ok('全书检索',s+' 命中'):bad('检索',JSON.stringify(s));
 await shot('bs-search');
 const hj=await ev(`brHitJump(0);return {p:curPage,lbl:document.getElementById('brHitsLbl').textContent}`);
 (hj.p==='p-readerPage'&&hj.lbl.includes('第'))?ok('命中跳转+上/下一处',hj.lbl):bad('跳转',JSON.stringify(hj));
 /* 持久化真重载 */
 const p0=await ev(`brPos['b1']={ci:7,pg:1};brPersist();return 1`);
 await cmd('Page.navigate',{url:URLF});await wait(2600);
 const p1=await ev(`var s=JSON.parse(localStorage.getItem('lh_reader_bs_v1')||'{}');return {pos:!!(s.pos&&s.pos.b1),cfg:!!s.cfg}`);
 (p1.pos&&p1.cfg)?ok('真重载后位置/外观恢复'):bad('持久化',JSON.stringify(p1));
 /* 逐屏断言 */
 await assertPage('p-bookshelf','renderShelf',150);
 await assertPage('p-localImport','brImpRender',80);
 await assertPage('p-readerPage','brRenderPage',40);
 await cmd('Runtime.evaluate',{expression:"CURBK='b1';brV.b='b1';document.getElementById('brSq').value='折扣'"});await assertPage('p-readerSearch','brSearchRender',60);
 await assertPage('p-readset','renderReadSet',100);
 /* 既有能力回归抽查 */
 const reg=await ev(`renderShelf();renderQuotes();renderBookDetail();renderReadStat();return {shelf:document.getElementById('shBody').children.length>0,quotes:document.getElementById('qtList').innerText.length>50}`);
 reg.shelf&&reg.quotes?ok('既有书架/笔记库渲染回归'):bad('既有回归',JSON.stringify(reg));
 log('JS 异常 '+(errs.length?(':\n'+errs.join('\n')):'0 条'));
 errs.length?bad('无 JS 异常',errs.length+' 条'):ok('无 JS 异常');
 /* 深链新实例 */
 const t2=await cmd('Target.createTarget',{url:URLF+'#p-readerPage'});await wait(2600);
 const list=await get('http://127.0.0.1:'+PORT+'/json');
 const tg=JSON.parse(list).find(x=>x.id===t2.result.targetId)||JSON.parse(list).find(x=>x.type==='page');
 ws.close();await new Promise(r=>setTimeout(r,300));
 ws=new WebSocket(tg.webSocketDebuggerUrl);await new Promise(r=>{ws.addEventListener('open',r);setTimeout(r,2500)});
 ws.addEventListener('message',e2=>{const m=JSON.parse(e2.data);if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}});
 await cmd('Runtime.enable');
 const dlp=await ev(`return {p:curPage,b:brV.b}`);
 dlp.p==='p-readerPage'?ok('深链 #p-readerPage','书 idx '+dlp.b):bad('深链',JSON.stringify(dlp));
 await shot('bs-deeplink');
 finish();
 function finish(){try{chrome.kill()}catch(e){}
  log('== 结果 PASS '+pass+' / FAIL '+fail+' ==');process.exit(fail?1:0)}})().catch(e=>{log('CRASH '+e.stack);process.exit(2)});
