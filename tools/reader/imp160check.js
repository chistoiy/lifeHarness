/* V1.60 导入流程改造批 · 原型回归（规格＝交棒话术20261002 §3G 拍板）
 * 用法：node --experimental-websocket tools/reader/imp160check.js（截图：IMP160_SHOTS=1）
 * 覆盖：解析步只剩四项 / 进度收敛自动进核对 / 核对步文案 / ?imp=1..4+pre+enter 深链 /
 *       预载中点封面可进（守卫摘除）/ 完整导入提交→预载中→直接开书 / 已清缓存守卫不回归 */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF=url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href;
const PORT=Number(process.env.IMP160_PORT||9561);
const SHOTS=process.env.IMP160_SHOTS==='1';
const SHOTDIR='D:/dev_workplace/flutter_te/tempWork/imp160-shots';
let pass=0,fail=0;const errs=[];
const LOG='tools/reader/imp160-run.log';
fs.writeFileSync(LOG,'== imp160check start '+new Date().toISOString()+' ==\n');
const log=m=>{fs.appendFileSync(LOG,m+'\n');console.log(m)};
const ok=(n,i)=>{pass++;log('PASS '+n+(i?'  →  '+i:''))};
const bad=(n,i)=>{fail++;log('FAIL '+n+'  →  '+(i||''))};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function get(u){return new Promise(res=>{try{http.get(u,r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>res(d))}).on('error',()=>res(null))}catch(e){res(null)}})}
let ws,idc=0;const pend=new Map();
function cmd(method,params){return new Promise(res=>{const id=++idc;pend.set(id,res);ws.send(JSON.stringify({id,method,params:params||{}}))})}
async function ev(expr){const m=await cmd('Runtime.evaluate',{expression:'JSON.stringify((function(){'+expr+'})())',returnByValue:false,awaitPromise:true});
  const r=m.result&&m.result.result;try{return JSON.parse(r.value)}catch(e){return {__err:(r&&r.value)||JSON.stringify(m).slice(0,240)}}}
async function shot(name){if(!SHOTS)return;fs.mkdirSync(SHOTDIR,{recursive:true});const m=await cmd('Page.captureScreenshot',{format:'png'});
  if(m.result&&m.result.data)fs.writeFileSync(path.join(SHOTDIR,name+'.png'),Buffer.from(m.result.data,'base64'))}
async function gotoQ(q,w){await cmd('Page.navigate',{url:URLF+q});await wait(w===undefined?2600:w)}

(async()=>{
 if(!fs.existsSync(CHROME)){bad('chrome 存在');return finish()}
 spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,
  '--user-data-dir='+path.resolve('tools/reader/.imp160-profile'),'--disable-extensions','--no-default-browser-check',
  '--window-size=430,900','--allow-file-access-from-files','about:blank'],{stdio:'ignore'});
 let data=null;
 for(let i=0;i<60;i++){const d=await get('http://127.0.0.1:'+PORT+'/json');if(d){try{data=JSON.parse(d);if(data.some(x=>x.type==='page'))break}catch(e){}}await wait(300)}
 if(!data){bad('调试端口');return finish()}
 ws=new WebSocket(data.find(t=>t.type==='page').webSocketDebuggerUrl);
 await new Promise(r=>{ws.addEventListener('open',r);setTimeout(r,3000)});
 ws.addEventListener('message',e2=>{const m=JSON.parse(e2.data);
  if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}
  if(m.method==='Runtime.exceptionThrown')errs.push(((m.params.exceptionDetails.exception||{}).description||'').slice(0,240))});
 await cmd('Runtime.enable');await cmd('Page.enable');

 /* A+B · ?imp=3 解析步：四项同屏 · 进度条在走 · 全页无「分页预计算」· 走完自动进核对步 */
 await gotoQ('?imp=3',2100);
 const p3=await ev(`const t3=document.getElementById('brImp3');
   if(!t3)return {err:'页面未就绪'};
   return {shown:!t3.classList.contains('hidden'),
   items:document.querySelectorAll('#brTaskList > div').length,
   txt:document.getElementById('brTaskList').textContent,
   leak:document.documentElement.innerHTML.includes('分页预计算'),
   bar:document.getElementById('brBar').style.width,step:brImp.step};`);
 if(p3.__err||p3.err)bad('imp=3 读取',JSON.stringify(p3));
 else{
  (p3.shown&&p3.items===4&&!/分页预计算/.test(p3.txt))?ok('第3步只渲染四条任务',p3.items+' 项 · '+p3.bar):bad('第3步',JSON.stringify(p3));
  !p3.leak?ok('全页无「分页预计算」残留'):bad('文案残留',JSON.stringify(p3));
  parseFloat(p3.bar)>0?ok('进度条随四条推进',p3.bar):bad('进度条',p3.bar);
 }
 await shot('imp3-parsing');
 await wait(3000);
 const p4a=await ev(`return {step:brImp.step,shown:!document.getElementById('brImp4').classList.contains('hidden'),
   bar:document.getElementById('brBar').style.width};`);
 (!p4a.__err&&p4a.step===4&&p4a.shown&&parseFloat(p4a.bar)===100)?ok('四项跑完进度收敛100%·自动进核对',p4a.bar):bad('收敛',JSON.stringify(p4a));

 /* C · ?imp=4 核对步文案口径 */
 await gotoQ('?imp=4');
 const c4=await ev(`return {title:document.getElementById('brF_t').value,
   btn:document.getElementById('brSaveBtn').textContent,
   foot:(document.querySelector('#brImp4 .text-center')||{}).textContent||'',
   step:brImp.step};`);
 if(c4.__err)bad('imp=4 读取',c4.__err);
 else{
  (c4.title==='克拉拉与太阳'&&c4.step===4)?ok('核对步元数据就位',c4.title):bad('核对步',JSON.stringify(c4));
  (c4.btn==='加入书架 · 开始阅读')?ok('保存钮不再承诺「预载后可读」'):bad('保存钮',c4.btn);
  (/整本分页后台续算/.test(c4.foot)&&!/分页缓存/.test(c4.foot))?ok('底注改口径为后台续算',c4.foot.trim()):bad('底注',c4.foot);
 }
 await shot('imp4-check');

 /* D · ?imp=1 / ?imp=2 步容器 */
 await gotoQ('?imp=1');
 const d1=await ev(`return !document.getElementById('brImp1').classList.contains('hidden')&&brImp.step===1;`);
 d1===true?ok('imp=1 直达授权步'):bad('imp=1',JSON.stringify(d1));
 await gotoQ('?imp=2');
 const d2=await ev(`return !document.getElementById('brImp2').classList.contains('hidden')&&document.querySelectorAll('#brFiles button').length>=3;`);
 d2===true?ok('imp=2 直达选文件步'):bad('imp=2',JSON.stringify(d2));

 /* E · ?imp=pre 书架预载中书卡 + 点封面直接进入（守卫已摘） */
 await gotoQ('?imp=pre');
 const e1=await ev(`const ov=document.querySelector('#p-bookshelf .br-covovl.pre');
   return {ov:!!ov,txt:ov?ov.textContent:'',st:bsBook('b1').epub.st};`);
 if(e1.__err)bad('imp=pre 读取',e1.__err);
 else (e1.ov&&/预载中/.test(e1.txt)&&e1.st==='pre')?ok('书卡预载中态在位（复用批3.5视觉）',e1.txt.trim()):bad('预载态',JSON.stringify(e1));
 await shot('pre-card');
 /* E2 口径（§3G 拍板）：预载中点封面＝可进＋后台仍续算；toast 会被阅读器自身提示覆盖，不 assert 文案 */
 const e2=await ev(`const card=[...document.querySelectorAll('#p-bookshelf [onclick]')].find(x=>(x.getAttribute('onclick')||'').includes("shOpen('b1')"));
   if(!card)return {err:'no card'};card.click();
   return {page:curPage,st:bsBook('b1').epub.st};`);
 if(e2.__err||e2.err)bad('预载中点封面',JSON.stringify(e2));
 else (e2.page==='p-readerPage'&&e2.st==='pre')?ok('预载中点封面＝直接开书·后台仍预载','当前页 '+e2.page+' · st='+e2.st):bad('点封面被挡',JSON.stringify(e2));
 await shot('pre-tap-enter');

 /* F · ?imp=enter 预载中开书后的阅读态（toast 文案含「后台续算」，1400ms 内未被 2.2s 定时器抹掉） */
 await gotoQ('?imp=enter',1800);
 const f1=await ev(`return {page:curPage,st:bsBook('b1').epub.st,toast:document.getElementById('toast').textContent};`);
 if(f1.__err)bad('imp=enter 读取',f1.__err);
 else (f1.page==='p-readerPage'&&f1.st==='pre'&&/后台续算/.test(f1.toast))?ok('深链直落预载中阅读态',f1.toast):bad('imp=enter',JSON.stringify(f1));
 await shot('enter-reader');

 /* G · 完整导入提交链：选文件→解析四项→核对→提交＝预载中书卡→立刻可开书 */
 await gotoQ('',400);
 const g0=await ev(`navTo('p-localImport');brImpGo(2);brImpPick('download',0);return brImp.step;`);
 g0===3?ok('提交链进入解析步'):bad('提交链起步',JSON.stringify(g0));
 await wait(3600);
 const g1=await ev(`if(brImp.step!==4)return {err:'未到核对步',step:brImp.step};
   const n=BS_BOOKS.length;brImpCommit();
   const nb=BS_BOOKS[BS_BOOKS.length-1];
   return {added:BS_BOOKS.length>n,id:nb.id,st:nb.epub&&nb.epub.st,page:curPage};`);
 if(g1.__err||g1.err)bad('提交落架',JSON.stringify(g1));
 else{
  (g1.added&&g1.st==='pre')?ok('提交即入「预载中」态',g1.id+' st='+g1.st):bad('提交态',JSON.stringify(g1));
 }
 await wait(600);
 const g2=await ev(`const b=BS_BOOKS[BS_BOOKS.length-1];shOpen(b.id);
   return {page:curPage,st:b.epub.st};`);
 (!g2.__err&&g2.page==='p-readerPage'&&g2.st==='pre')?ok('新书预载中即可开读',g2.st):bad('新书开读',JSON.stringify(g2));

 /* H · 回归：?br35=cl 已清缓存守卫不被动到（点封面走重新载入弹层） */
 await gotoQ('?br35=cl');
 const h1=await ev(`const ov=document.querySelector('#p-bookshelf .br-covovl.cl');
   const card=[...document.querySelectorAll('#p-bookshelf [onclick]')].find(x=>(x.getAttribute('onclick')||'').includes("shOpen('b1')"));
   if(card)card.click();
   return {ov:!!ov,page:curPage,sheet:!!document.getElementById('sheetBrReload')&&!document.getElementById('sheetBrReload').classList.contains('hidden')};`);
 if(h1.__err)bad('br35=cl 回归',h1.__err);
 else (h1.ov&&h1.sheet&&h1.page!=='p-readerPage')?ok('已清缓存分流弹层不回归'):bad('cl 分流',JSON.stringify(h1));

 finish();
 function finish(){
  if(errs.length)errs.slice(0,4).forEach(e=>bad('运行时异常',e));
  else ok('页面零运行时报错');
  log(`== RANGE ${pass} PASS / ${fail} FAIL ==`);
  try{ws&&ws.close()}catch(e){}
  process.exit(fail?1:0);
 }
})();
