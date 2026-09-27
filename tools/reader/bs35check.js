/* 批3.5 原型增量回归 · 整本预载 / 单书清缓存三态 / 重新载入 / 源丢失挂回
 * 用法：node --experimental-websocket tools/reader/bs35check.js（截图：BSRD_SHOTS=1）
 * 逐态用 ?br35=xxx 深链新实例，避免互相污染。 */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE=path.resolve('prototype/index-bookshelf.html');
const URLF=url.pathToFileURL(FILE).href;
const PORT=Number(process.env.BSRD_PORT||9537);
const SHOTS=process.env.BSRD_SHOTS==='1';
const SHOTDIR='prototype/shots/reader';
const LOG='tools/reader/bs35-run.log';
let pass=0,fail=0;const errs=[];
const log=m=>{fs.appendFileSync(LOG,m+'\n');console.log(m)};
fs.writeFileSync(LOG,'== bs35check start '+new Date().toISOString()+' ==\n');
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
async function gotoQ(q){await cmd('Page.navigate',{url:URLF+q});await wait(2600)}

(async()=>{
 if(!fs.existsSync(CHROME)){bad('chrome 存在');return finish()}
 log('launch chrome · port '+PORT);
 const chrome=spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,
  '--user-data-dir='+path.resolve('tools/reader/.bs35-profile'),'--disable-extensions','--no-default-browser-check',
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

 /* ============ A · 基线（无 ?br35）：不伤既有 ============ */
 await gotoQ('');
 const base=await ev(`return {b1:bsBook('b1').local,st:bsBook('b1').epub&&bsBook('b1').epub.st,ovl:document.querySelectorAll('.br-covovl').length}`);
 (base.b1===1&&base.ovl===0&&base.st==null)?ok('基线·默认无演示态覆盖层'):bad('基线',JSON.stringify(base));
 const op=await ev(`setPage('p-bookshelf');renderShelf();shOpen('b1');return {p:curPage}`);
 (op.p==='p-readerPage')?ok('基线·就绪书点封面仍直达阅读'):bad('基线直达',JSON.stringify(op));
 /* 导入新书 → 进入预载态 */
 await cmd('Runtime.evaluate',{expression:"navTo('p-localImport');brImpGo(2);brImpPick('download',0)"});await wait(3600);
 const nc=await ev(`brImpCommit();var b=BS_BOOKS[BS_BOOKS.length-1];return {st:b.epub.st,pr:b.epub.pr,cache:b.epub.cache}`);
 (nc.st==='pre'&&nc.pr>=2)?ok('导入·新书自动进入整本预载',JSON.stringify(nc)):bad('导入预载',JSON.stringify(nc));
 const newId=await ev(`return BS_BOOKS[BS_BOOKS.length-1].id`);
 const guard=await ev(`stack.length=0;setPage('p-bookshelf');shOpen('${newId}');return {p:curPage,active:document.querySelector('.page.active').id,t:document.getElementById('toast').textContent}`);
 (guard.active!=='p-readerPage'&&/预载/.test(guard.t))?ok('预载中·点封面被守卫'):bad('守卫',JSON.stringify(guard));
 /* 等预载跑完 → 秒进 */
 await wait(5200);
 const rdy=await ev(`var b=bsBook('${newId}');return {st:b.epub.st,timers:Object.keys(brPre.timers).length}`);
 (rdy.st==='rdy'&&rdy.timers===0)?ok('预载完成→就绪且计时器清理',JSON.stringify(rdy)):bad('预载完成',JSON.stringify(rdy));
 const fast=await ev(`shOpen('${newId}');return curPage`);
 (fast==='p-readerPage')?ok('就绪后点封面秒进'):bad('秒进',fast);
 await cmd('Runtime.evaluate',{expression:"brLeave&&brLeave();goBack()"});
 /* 清理缓存 → 三态迁移（源可读） */
 const cl=await ev(`setPage('p-bookshelf');brCacheOpen('${newId}');var s=document.getElementById('sheetBrCache');return {open:!s.classList.contains('hidden'),size:document.getElementById('brCacheSize').textContent}`);
 (cl.open&&/MB/.test(cl.size))?ok('详情入口·清理缓存弹层',JSON.stringify(cl)):bad('清理弹层',JSON.stringify(cl));
 await shot('bs35-a-cache-sheet');
 const cc=await ev(`brCacheCommit();var b=bsBook('${newId}');return {st:b.epub.st,local:b.local,pos:1,quotes:BS_QUOTES.filter(q=>q.b==='${newId}').length,t:document.getElementById('toast').textContent}`);
 (cc.st==='cl'&&cc.local===1&&/源文件未删除/.test(cc.t))?ok('清理后·记录保留仅状态迁移'):bad('清理迁移',JSON.stringify(cc));
 const clBadge=await ev(`renderShelf();return {cl_ovl:document.querySelectorAll('.br-covovl.cl').length,cached:document.querySelectorAll('.br-cached').length}`);
 (clBadge.cl_ovl>=1&&clBadge.cached>=1)?ok('封面·已清缓存蒙层与角标',JSON.stringify(clBadge)):bad('封面蒙层',JSON.stringify(clBadge));
 await shot('bs35-a-cleared');
 /* 点已清缓存封面 → 重新载入弹层 → 预载 */
 const rl=await ev(`shOpen('${newId}');var s=document.getElementById('sheetBrReload');return {open:!s.classList.contains('hidden'),p:curPage}`);
 (rl.open&&rl.p!=='p-readerPage')?ok('已清·点封面→重新载入弹层'):bad('重载弹层',JSON.stringify(rl));
 await shot('bs35-a-reload-sheet');
 const rp=await ev(`brReloadCommit();return bsBook('${newId}').epub.st`);
 (rp==='pre')?ok('确认重新拷贝并预载→pre'):bad('重载提交',rp);
 await ev(`brPreStop('${newId}')`);

 /* ============ B · ?br35=frozen 预载封面静态态 ============ */
 await gotoQ('?br35=frozen');
 const frz=await ev(`var b=bsBook('b1');var o=document.querySelector('.br-covovl.pre');
  return {st:b.epub.st,pct:o&&o.querySelector('.br-prepct').textContent,bar:!!(o&&o.querySelector('.br-prebar i'))}`);
 (frz.st==='pre'&&/预载中/.test(frz.pct||'')&&frz.bar)?ok('br35=frozen·封面预载进度条',JSON.stringify(frz)):bad('frozen',JSON.stringify(frz));
 await shot('bs35-b-frozen-cover');
 const fguard=await ev(`shOpen('b1');return {p:curPage,t:document.getElementById('toast').textContent}`);
 (fguard.p!=='p-readerPage'&&/预载/.test(fguard.t))?ok('frozen·点封面被守卫'):bad('frozen守卫',JSON.stringify(fguard));

 /* ============ C · ?br35=pre 进度实时推进 ============ */
 await gotoQ('?br35=pre');
 const t0=await ev(`return bsBook('b1').epub.pr`);
 await wait(1800);
 const t1=await ev(`return {pr:bsBook('b1').epub.pr,w:document.querySelector('[data-brpre="b1"]').style.width}`);
 (t1.pr>t0&&t1.w)?ok('br35=pre·进度条实时推进',t0+'→'+t1.pr+' w='+t1.w):bad('进度推进',JSON.stringify({t0,t1}));
 await shot('bs35-c-progress');
 await ev(`brPreStop('b1')`);

 /* ============ D · ?br35=detail 本地卡·已清可读态 ============ */
 await gotoQ('?br35=detail');
 const det=await ev(`return {p:curPage,row:!!document.getElementById('brDcache'),txt:document.getElementById('brDcache')&&document.getElementById('brDcache').innerText,openBtn:!!document.querySelector('#brDcard button[onclick^="shOpen("]')}`);
 (det.p==='p-bookDetail'&&det.row&&/重新载入/.test(det.txt)&&det.openBtn)?ok('br35=detail·本地卡缓存行(已清可读)+打开钮走守卫',JSON.stringify(det.txt||'').slice(0,80)):bad('detail卡',JSON.stringify(det));
 await shot('bs35-d-detail-cleared');

 /* ============ E · ?br35=lost 源丢失→重选→挂回原记录 ============ */
 await gotoQ('?br35=lost');
 const lost=await ev(`return {b9:bsBook('b9').local,st:bsBook('b9').epub.st,srcOk:bsBook('b9').epub.srcOk,open:!!document.getElementById('sheetBrLost')}`);
 (lost.b9===1&&lost.st==='cl'&&!lost.srcOk)?ok('br35=lost·种子 b9 已清+源丢失'):bad('lost种子',JSON.stringify(lost));
 await shot('bs35-e-lost-sheet');
 /* 长按入口也应分流 */
 const lpm=await ev(`shLongMenu('b9');var h=document.getElementById('lpOps').innerHTML;return {read:/brLpRead/.test(h)}`);
 lpm.read?ok('长按·开始阅读钮改走状态守卫'):bad('长按',JSON.stringify(lpm));
 await cmd('Runtime.evaluate',{expression:"closeSheet('sheetLongPress')"});
 /* 弹层 → 导入页第 2 步带提示 */
 const go=await ev(`brLostGoImp();return {p:curPage,step:brImp.step,hint:document.getElementById('brAttachHint')&&!document.getElementById('brAttachHint').classList.contains('hidden'),hintTxt:document.getElementById('brAttachHint').textContent}`);
 (go.p==='p-localImport'&&go.step===2&&go.hint&&/万历十五年/.test(go.hintTxt))?ok('源丢失·引导重选→导入页提示条'):bad('引导',JSON.stringify(go));
 await shot('bs35-e-import-hint');
 /* 选「万历十五年.epub」→ 第 4 步应识别挂回原记录 */
 const idx=await ev(`return BR_FILES.download.findIndex(f=>f.n==='万历十五年.epub')`);
 await cmd('Runtime.evaluate',{expression:`brImpPick('download',${idx})`});await wait(3600);
 const m4=await ev(`return {step:brImp.step,merge:brImp.mergeTo,lostId:brImp.lostId,dup:!document.getElementById('brDup').classList.contains('hidden'),dupTxt:document.getElementById('brDup').textContent,btn:document.getElementById('brSaveBtn').textContent}`);
 (m4.step===4&&m4.merge==='b9'&&m4.lostId==='b9'&&m4.dup&&/挂回原记录/.test(m4.dupTxt)&&/挂回/.test(m4.btn))?ok('重选·文件名匹配挂回 b9'):bad('匹配',JSON.stringify(m4));
 await shot('bs35-e-merge-back');
 /* 提交 → b9 回到预载 → 完成秒进；书摘计时保留 */
 const cm=await ev(`var q0=BS_QUOTES.filter(q=>q.b==='b9').length;var n0=BS_BOOKS.length;brImpCommit();var b=bsBook('b9');return {st:b.epub.st,nSame:BS_BOOKS.length===n0,q0:q0,t:document.getElementById('toast').textContent}`);
 (cm.st==='pre'&&cm.nSame&&/挂回/.test(cm.t))?ok('挂回提交·原记录进预载·不新增书目'):bad('挂回提交',JSON.stringify(cm));
 const fin=await ev(`bsBook('b9').epub.pr=100;brPre.stop('b9');bsBook('b9').epub.st='rdy';renderShelf();shOpen('b9');return {p:curPage,src:bsBook('b9').src}`);
 (fin.p==='p-readerPage')?ok('挂回完成后点封面秒进'):bad('挂回秒进',JSON.stringify(fin));
 /* 清理已挂回的书 → 源文件此时可读，清后应转入「可重新载入」态 */
 const cl2=await ev(`brCacheOpen('b9')`);await wait(150);
 const cl3=await ev(`brCacheCommit();return {st:bsBook('b9').epub.st,srcOk:bsBook('b9').epub.srcOk,lostAt:bsBook('b9').epub.lostAt}`);
 (cl3.st==='cl'&&cl3.srcOk===1&&!cl3.lostAt)?ok('挂回后再清理→转入可重新载入态'):bad('再清理',JSON.stringify(cl3));

 log('JS 异常 '+(errs.length?(':\n'+errs.join('\n')):'0 条'));
 errs.length?bad('无 JS 异常',errs.length+' 条'):ok('无 JS 异常');
 finish();
 function finish(){try{chrome.kill()}catch(e){}
  log('== 结果 PASS '+pass+' / FAIL '+fail+' ==');process.exit(fail?1:0)}})().catch(e=>{log('CRASH '+e.stack);console.log(e.stack);process.exit(2)});
