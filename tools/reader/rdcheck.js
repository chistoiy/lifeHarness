/* 阅读器专版原型回归校验 · CDP 无头（进度实时可见：tools/reader/rd-run.log）
 * 用法：node --experimental-websocket tools/reader/rdcheck.js [--shots] */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE=path.resolve('prototype/index-reader.html');
const URLF=url.pathToFileURL(FILE).href;
const PORT=Number(process.env.RD_PORT||9517);
const SHOTS=process.argv.includes('--shots');
const SHOTDIR='prototype/shots/reader';
const LOG='tools/reader/rd-run.log';
let pass=0,fail=0;const errs=[];
const log=m=>{fs.appendFileSync(LOG,m+'\n');console.log(m)};
fs.writeFileSync(LOG,'== rdcheck start '+new Date().toISOString()+' ==\n');
const ok=(n,i)=>{pass++;log('PASS '+n+(i?'  →  '+i:''))};
const bad=(n,i)=>{fail++;log('FAIL '+n+'  →  '+(i||''))};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function get(u){return new Promise(res=>{try{http.get(u,r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>res(d))}).on('error',()=>res(null))}catch(e){res(null)}})}
let ws,idc=0;const pend=new Map();
function cmd(method,params,target){return new Promise(res=>{const id=++idc;pend.set(id,res);
  (target||ws).send(JSON.stringify({id,method,params:params||{}}))})}
async function ev(expr){const m=await cmd('Runtime.evaluate',{expression:'JSON.stringify((function(){'+expr+'})())',returnByValue:false});
  const r=m.result&&m.result.result;try{return JSON.parse(r.value)}catch(e){return {__err:(r&&r.value)||JSON.stringify(m).slice(0,200)}}}
async function shot(name){if(!SHOTS)return;const m=await cmd('Page.captureScreenshot',{format:'png'});
  if(m.result&&m.result.data)fs.writeFileSync(path.join(SHOTDIR,name+'.png'),Buffer.from(m.result.data,'base64'))}

const LEAK='/(^|[\\s>])(ring-|bg-(slate|indigo|white|black|brand|emerald|amber|rose|sky|teal)|text-(slate|white|brand|rose|amber|emerald)|border-|rounded-|font-|dark:)/';
async function assertPage(p,render,checks){
  const r=await ev(`setPage('${p}');var el=document.getElementById('${p}');if(window.${render})window.${render}();var t=(el.innerText||'');
    var leak=0;el.querySelectorAll('*').forEach(function(e){for(var i=0;i<e.childNodes.length;i++){var n=e.childNodes[i];if(n.nodeType===3&&new RegExp(${JSON.stringify(LEAK)}).test(n.nodeValue))leak++}});
    return {len:t.length,badWord:(t.match(/undefined|NaN|\\[object/g)||[]).length,leak:leak}`);
  if(r.__err)return bad('屏 '+p+' 断言异常',r.__err);
  if(r.len>(checks.minLen||120)&&r.badWord===0&&r.leak===0)ok('屏 '+p,`文本${r.len} · 泄漏0 · 假值0`);
  else bad('屏 '+p,JSON.stringify(r));
  await shot(p)}

(async()=>{
 if(!fs.existsSync(CHROME)){bad('chrome 存在',CHROME);return finish()}
 if(SHOTS)fs.mkdirSync(SHOTDIR,{recursive:true});
 log('launch chrome · port '+PORT);
 const chrome=spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,
  '--user-data-dir='+path.resolve('tools/reader/.chrome-profile'),'--disable-extensions','--no-default-browser-check',
  '--window-size=430,900','--allow-file-access-from-files','about:blank'],{stdio:'ignore'});
 let data=null;
 for(let i=0;i<60;i++){const d=await get('http://127.0.0.1:'+PORT+'/json');if(d){try{data=JSON.parse(d);if(data.length)break}catch(e){}}await wait(300)}
 if(!data){bad('CDP 启动','端口无响应（换 RD_PORT）');return finish()}
 const pg=data.find(t=>t.type==='page')||data[0];
 ws=new WebSocket(pg.webSocketDebuggerUrl);
 await new Promise(r=>{ws.addEventListener('open',r);setTimeout(r,3000)});
 ws.addEventListener('message',ev2=>{const m=JSON.parse(ev2.data);
  if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}
  if(m.method==='Runtime.exceptionThrown')errs.push((m.params.exceptionDetails.exception||{}).description||m.params.exceptionDetails.text)});
 await cmd('Runtime.enable');await cmd('Page.enable');
 log('导航 '+URLF);
 await cmd('Page.navigate',{url:URLF});await wait(2600);
 const boot=await ev(`return {ok:typeof rdBoot==='function'&&RD_BOOKS.length, page:curPage}`);
 if(boot.ok)ok('启动','RD_BOOKS='+boot.ok+' curPage='+boot.page);else bad('启动',JSON.stringify(boot));

 await assertPage('p-readerShelf','rdRenderShelf',{minLen:250});
 /* 视图切换/搜索 */
 const v=await ev(`rdToggleView();var a=$('#rdShelfList').children.length;$('#rdShelfQ').value='赫拉利';rdRenderShelf();var b=$('#rdShelfList').innerText;$('#rdShelfQ').value='';rdToggleView();rdRenderShelf();return {a:a,hit:b.includes('人类简史')}`);
 (v.a>0&&v.hit)?ok('书架视图与搜索'):bad('书架视图与搜索',JSON.stringify(v));
 /* 导入链路：选文件→解析→元信息→入库 */
 await cmd('Runtime.evaluate',{expression:"navTo('p-readerImport');rdImpGo(2)"});await wait(150);
 await shot('import-files');
 const dup=await ev(`rdImpPick('download',0);return RD_IMP.step`);
 const st4=dup===3?'parse-start':'异常';
 await wait(3400);
 const meta=await ev(`return {step:RD_IMP.step,t:$('#rdFM_t').value,dup:$('#rdImpDup').classList.contains('hidden')===false}`);
 (meta.step===4&&meta.t.includes('思考'))?ok('导入·重复守卫',JSON.stringify(meta)):bad('导入·重复守卫',JSON.stringify(meta));
 await shot('import-meta');
 const nb=await ev(`rdImpCommit();return {n:RD_BOOKS.length,last:RD_BOOKS[RD_BOOKS.length-1].t}`);
 nb.n===5?ok('导入·入库','《'+nb.last+'》'):bad('导入·入库',JSON.stringify(nb));
 /* 阅读器主屏 */
 await cmd('Runtime.evaluate',{expression:"rdOpenBook(0);RD_V.pg=0;rdRenderPage()"});await wait(300);
 const rp=await ev(`return {len:$('#rdBody').innerText.length,pg:RD_V.pg,ch:RD_V.ch,page:curPage}`);
 rp.len>60&&rp.page==='p-readerPage'?ok('阅读主屏渲染','页'+(rp.pg+1)+' 章'+rp.ch):bad('阅读主屏渲染',JSON.stringify(rp));
 const fl=await ev(`var p0=RD_V.pg;rdFlip(1);return {d:RD_V.pg!==p0,pct:rdStPct(0)}`);
 fl.d?ok('翻页 · 进度实算',JSON.stringify(fl)):bad('翻页',JSON.stringify(fl));
 /* 划词 → 高亮 → 批注 → 笔记联动 */
 const hlB=await ev(`return RD_HL.length`);
 await cmd('Runtime.evaluate',{expression:"rdSelect(1,2)"});await wait(150);
 const sb=await ev(`return {vis:!$('#rdSelBar').classList.contains('hidden'),acts:$('#rdSelActs').children.length}`);
 (sb.vis&&sb.acts>=8)?ok('划词菜单',JSON.stringify(sb)):bad('划词菜单',JSON.stringify(sb));
 await shot('reader-select');
 const hl=await ev(`var n0=RD_HL.length,m0=D.notes.length;rdAddHl('y');return {d:RD_HL.length-n0,nd:D.notes.length-m0}`);
 (hl.d===1&&hl.nd>=1)?ok('高亮落库+同步笔记','notes+'+hl.nd):bad('高亮落库',JSON.stringify(hl));
 const an=await ev(`var nn=D.notes.length;rdSelect(4,4);rdAnOpen();$('#rdAnText').value='校验批注';rdAnSave();return {d:D.notes.length-nn,an:RD_AN.length}`);
 (an.d===1&&an.an>=3)?ok('批注·绑定CFI·同步',JSON.stringify(an)):bad('批注',JSON.stringify(an));
 const j=await ev(`rdJumpCfi(0,'c1',3);return {ch:RD_V.ch,page:curPage}`);
 (j.ch==='c1'&&j.page==='p-readerPage')?ok('批注跳原文(CFI)'):bad('跳原文',JSON.stringify(j));
 /* AI 解读 */
 await cmd('Runtime.evaluate',{expression:"rdSelect(3,3);rdAiOpen()"});await wait(2700);
 const ai=await ev(`return RD_AI.text.length>60&&!$('#rdAiOut').innerText.includes('正在')`);
 ai?ok('AI 流式解读'):bad('AI 流式解读');
 await shot('sheet-ai');
 await cmd('Runtime.evaluate',{expression:"closeSheet('sheetRtAi');rdSelHide()"});
 /* 目录 / 进度条 / 主题 / 字号 / 模式 / 外观保存 */
 const toc=await ev(`rdTocRender();return $('#rdTocList').children.length`);
 toc>15?ok('目录渲染',toc+' 行'):bad('目录',JSON.stringify(toc));
 await cmd('Runtime.evaluate',{expression:"openSheet('sheetRtToc')"});await wait(250);await shot('sheet-toc');
 await cmd('Runtime.evaluate',{expression:"closeSheet('sheetRtToc');RD_V.chrome=true;$('#rdTop').classList.remove('hidden');$('#rdTop').classList.add('flex');$('#rdBottom').classList.remove('hidden');$('#rdBottom').classList.add('flex');$('#rdScroll').scrollTop=0;RD_V.ch='c4';RD_V.pg=0;rdRenderPage()"});await wait(150);await shot('reader-chrome');
 const seek=await ev(`rdSeek(rdTotalPages(0)*0.5|0);return {pct:rdStPct(0),ch:RD_V.ch}`);
 (seek.pct>35&&seek.pct<80)?ok('进度条拖动定位',seek.pct+'%'):bad('进度定位',JSON.stringify(seek));
 const th=await ev(`rdThemeCycle();return rdSt(0).theme`);
 (th==='eye')?ok('主题循环','→ '+th):bad('主题',th);
 const ap=await ev(`var t0=rdTotalPages(0);openSheet('sheetRtAppearance');rdApOpen('book');rdApSet('fs',28);return 1`);
 await wait(200);await shot('sheet-appearance');
 const ap0=await ev(`return rdTotalPages(0)`);
 await cmd('Runtime.evaluate',{expression:"rdApSave()"});
 const ap1=await ev(`return rdTotalPages(0)`);
 await cmd('Runtime.evaluate',{expression:"rdApOpen('book');rdApSet('fs',19);rdApSave()"});
 (ap1>ap0)?ok('外观草稿保存→重排页数',ap0+'→'+ap1):bad('外观重排',ap0+'→'+ap1);
 await cmd('Runtime.evaluate',{expression:"rdImgOpen('图 7-1 · 锚定值随转速分布变化（示意）')"});await wait(250);await shot('sheet-image');
 await cmd('Runtime.evaluate',{expression:"closeSheet('sheetRtImg');rdSeek(0)"});
 const md=await ev(`rdModeToggle();return RD_V.mode`);
 (md==='scroll')?ok('滚动模式切换'):bad('滚动模式',md);
 await cmd('Runtime.evaluate',{expression:"rdModeToggle()"});
 /* 检索 */
 await cmd('Runtime.evaluate',{expression:"navTo('p-readerSearch');$('#rdSq').value='锚定';rdSearchRender()"});await wait(150);
 const s=await ev(`var n=$('#rdSHits').children.length;$('#rdSq').value='';return n`);
 s>0?ok('全书检索',s+' 命中'):bad('全书检索',JSON.stringify(s));
 /* 批注列表 + 导出内容 */
 await cmd('Runtime.evaluate',{expression:"rdGotoNotes(0)"});await wait(150);
 const nl=await ev(`return {rows:$('#rdNotesList').children.length,txt:rdExLines().join('\\n').length}`);
 (nl.rows>=4&&nl.txt>100)?ok('批注列表+MD导出串',JSON.stringify(nl)):bad('批注列表',JSON.stringify(nl));
 const tab=await ev(`rdNotesTab='an';rdRenderNotes();var n=$('#rdNotesList').children.length;rdNotesTab='all';rdRenderNotes();return n`);
 tab>=1?ok('批注 Tab 筛选',tab+' 条'):bad('Tab 筛选',JSON.stringify(tab));
 /* 统计 */
 await cmd('Runtime.evaluate',{expression:"rdOpenStats(0)"});await wait(150);
 const st=await ev(`var t=$('#rdStatsBody').innerText;return {ok:/小时/.test(t)&&!/undefined|NaN/.test(t),rem:!!$('#rdStRemT')}`);
 st.ok?ok('统计屏'):bad('统计屏',JSON.stringify(st));
 /* 设置 + 逐书持久化 */
 await cmd('Runtime.evaluate',{expression:"navTo('p-readerSettings')"});await wait(150);
 const se=await ev(`rdSetPut('linkAsk','deny');var seg=$('#rdLinkSeg').children.length;var pb=$('#rdPerBook').children.length;rdSetPut('linkAsk','ask');var ls=JSON.parse(localStorage.getItem('lh_reader_v1')||'{}');return {seg:seg,pb:pb,persist:!!(ls.cfg&&ls.pos)}`);
 (se.seg===3&&se.persist)?ok('设置屏+localStorage',JSON.stringify(se)):bad('设置/持久化',JSON.stringify(se));
 /* 删除书籍（守卫文案） */
 const del=await ev(`rdDelOpen(4);rdDeleteCommit();return RD_BOOKS.length`);
 del===4?ok('删除本书（源文件保留默认）'):bad('删除',JSON.stringify(del));
 /* 真重载持久化回归（localStorage 恢复） */
 const before=await ev(`return {hl:RD_HL.length,an:RD_AN.length,cfg:JSON.stringify(rdCfg).length}`);
 await cmd('Page.navigate',{url:URLF});await wait(2600);
 const after=await ev(`return {hl:RD_HL.length,an:RD_AN.length,seed:4}`);
 (after.hl>before.hl-1&&after.hl>=5)?ok('真重载后高亮批注仍恢复',JSON.stringify({before:before.hl,after:after.hl})):bad('持久化真重载',JSON.stringify({before,after}));
 /* 各屏逐屏断言 */
 await assertPage('p-readerShelf','rdRenderShelf',{minLen:250});
 await assertPage('p-readerBook','rdRenderBook',{minLen:200});
 await assertPage('p-readerNotes','rdRenderNotes',{minLen:100});
 await assertPage('p-readerStats','rdRenderStats',{minLen:100});
 await assertPage('p-readerSettings','rdRenderSettings',{minLen:100});
 await assertPage('p-readerPage','rdRenderPage',{minLen:50});
 log('JS 异常 '+(errs.length?(':\n'+errs.join('\n')):'0 条'));
 if(errs.length)bad('无 JS 异常',errs.length+' 条');else ok('无 JS 异常');
 /* 深链新实例 */
 const t2=await cmd('Target.createTarget',{url:URLF+'#p-readerBook_b2'});await wait(2200);
 const list=await get('http://127.0.0.1:'+PORT+'/json');const tg=JSON.parse(list).find(x=>x.id===t2.result.targetId)||JSON.parse(list).find(x=>x.type==='page');
 ws.close();await new Promise(r=>setTimeout(r,300));
 ws=new WebSocket(tg.webSocketDebuggerUrl);await new Promise(r=>{ws.addEventListener('open',r);setTimeout(r,2500)});
 ws.addEventListener('message',ev2=>{const m=JSON.parse(ev2.data);if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}});
 await cmd('Runtime.enable');
 const dl=await ev(`return {page:curPage,bk:rdCurBook&&rdBook(rdCurBook).t}`);
 (dl.page==='p-readerBook'&&dl.bk==='克拉拉与太阳')?ok('深链 #p-readerBook_b2',JSON.stringify(dl)):bad('深链',JSON.stringify(dl));
 await shot('deeplink-book');
 finish();
 function finish(){try{chrome.kill()}catch(e){}
  log('== 结果 PASS '+pass+' / FAIL '+fail+' ==');process.exit(fail?1:0)}})().catch(e=>{log('CRASH '+e.stack);try{process.exit(2)}catch(_){}});
