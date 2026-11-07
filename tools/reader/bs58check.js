/* V1.53.2 轮5.3 · 详情页本地 EPUB 条上移 原型回归
 * 用法：node --experimental-websocket tools/reader/bs58check.js（截图：BS58_SHOTS=1） */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF=url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href;
const PORT=Number(process.env.BS58_PORT||9558);
const SHOTS=process.env.BS58_SHOTS==='1';
const SHOTDIR='prototype/shots/reader58';
let pass=0,fail=0;const errs=[];
const LOG='tools/reader/bs58-run.log';
fs.writeFileSync(LOG,'== bs58check start '+new Date().toISOString()+' ==\n');
const log=m=>{fs.appendFileSync(LOG,m+'\n');console.log(m)};
const ok=(n,i)=>{pass++;log('PASS '+n+(i?'  →  '+i:''))};
const bad=(n,i)=>{fail++;log('FAIL '+n+'  →  '+(i||''))};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function get(u){return new Promise(res=>{try{http.get(u,r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>res(d))}).on('error',()=>res(null))}catch(e){res(null)}})}
let ws,idc=0;const pend=new Map();
function cmd(m,p){return new Promise(res=>{const id=++idc;pend.set(id,res);ws.send(JSON.stringify({id,method:m,params:p||{}}))})}
async function ev(expr){const m=await cmd('Runtime.evaluate',{expression:'JSON.stringify((function(){'+expr+'})())',returnByValue:false,awaitPromise:true});
  const r=m.result&&m.result.result;try{return JSON.parse(r.value)}catch(e){return {__err:(r&&r.value)||JSON.stringify(m).slice(0,240)}}}
async function shot(n){if(!SHOTS)return;fs.mkdirSync(SHOTDIR,{recursive:true});const m=await cmd('Page.captureScreenshot',{format:'png'});
  if(m.result&&m.result.data)fs.writeFileSync(path.join(SHOTDIR,n+'.png'),Buffer.from(m.result.data,'base64'))}

(async()=>{
 if(!fs.existsSync(CHROME)){bad('chrome 存在');return finish()}
 spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,
  '--user-data-dir='+path.resolve('tools/reader/.bs58-profile'),'--disable-extensions','--no-default-browser-check',
  '--window-size=430,1000','--allow-file-access-from-files','about:blank'],{stdio:'ignore'});
 let d=null;
 for(let i=0;i<60;i++){d=await get('http://127.0.0.1:'+PORT+'/json');if(d){try{if(JSON.parse(d).some(x=>x.type==='page'))break}catch(e){}}await wait(300)}
 if(!d){bad('调试端口');return finish()}
 ws=new WebSocket(JSON.parse(d).find(t=>t.type==='page').webSocketDebuggerUrl);
 await new Promise(r=>{ws.addEventListener('open',r);setTimeout(r,3000)});
 ws.addEventListener('message',e2=>{const m=JSON.parse(e2.data);
  if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}
  if(m.method==='Runtime.exceptionThrown')errs.push(((m.params.exceptionDetails.exception||{}).description||'').slice(0,240))});
 await cmd('Runtime.enable');await cmd('Page.enable');
 await cmd('Page.navigate',{url:URLF});await wait(2600);

 /* A · 打开本地书详情页：旧整卡消失，紧凑条落在统计行与 tabs 之间 */
 const a=await ev(`BR_OLD_SHOPEN('b1');renderBookDetail();
   const strip=document.getElementById('brDstrip'),tabs=document.getElementById('btToc');
   const host=tabs&&tabs.parentElement;
   return {old:!!document.getElementById('brDcard'),
     strip:!!strip,beforeTabs:!!(strip&&host&&host.previousElementSibling===strip),
     h:strip?Math.round(strip.getBoundingClientRect().height):0,
     txt:strip?strip.textContent.replace(/\\s+/g,' ').trim().slice(0,120):'',
     btns:strip?strip.querySelectorAll('button').length:0,
     rootLast:document.getElementById('bdRoot').lastElementChild&&document.getElementById('bdRoot').lastElementChild.id,
     cur:curPage,shown:!!document.querySelector('#p-bookDetail.page-on')};`);
 await wait(500);
 /* 页面切换有动画，量高度要等布局稳定（否则拿到 0） */
 const hh=await ev(`const s=document.getElementById('brDstrip');
   return {h:s?Math.round(s.getBoundingClientRect().height):0,
     rows:s?s.querySelectorAll(':scope > div').length:0};`);
 if(a.__err)bad('详情页读取',a.__err);
 else{
  (!a.old&&a.strip&&a.beforeTabs)?ok('旧底部整卡已删 · 紧凑条插到 tabs 之上','末元素='+(a.rootLast||'—')):bad('位置',JSON.stringify(a));
  (hh.h>0&&hh.h<96&&hh.rows===2&&a.btns===4)?ok('紧凑两行 · 四个操作钮（?/打开/检索/删除）',hh.h+'px · '+hh.rows+' 行 · '+a.btns+' 钮'):bad('紧凑度',JSON.stringify({a,hh}));
  (/EPUB/.test(a.txt)&&/无 DRM/.test(a.txt)&&/进度 \d+%/.test(a.txt)&&/划线 \d+ 处/.test(a.txt))
   ?ok('关键信息仍在条上',a.txt.slice(0,72)):bad('信息缺失',a.txt);
 }
 await shot('strip');

 /* B · 「?」弹层：路径 / 口径说明 / 缓存行 + 清理入口 */
 const b=await ev(`document.querySelector('#brDstrip button[title=\"本地文件与缓存说明\"]').click();
   const s=document.getElementById('sheetBrLocalInfo');
   const t=document.getElementById('brLiPath').textContent;
   const cache=document.getElementById('brLiCache').textContent;
   return {open:!s.classList.contains('hidden'),path:t,meta:document.getElementById('brLiMeta').textContent,
     pos:document.getElementById('brLiPos').textContent,cache,
     hasDel:/仅清除阅读数据/.test(s.textContent),
     clean:!document.getElementById('brLiClean').classList.contains('hidden'),
     z:getComputedStyle(s).zIndex};`);
 if(b.__err)bad('说明弹层',b.__err);
 else{
  (b.open&&/\.epub/.test(b.path)&&/8\.4 MB/.test(b.meta)&&/epub\//.test(b.pos))
   ?ok('弹层含路径/体积/位置明细',b.meta+' · '+b.pos):bad('明细',JSON.stringify(b));
  (b.hasDel&&b.cache&&b.clean)?ok('删除口径与缓存说明收进弹层',b.cache.slice(0,30)):bad('说明缺失',JSON.stringify(b));
  b.z==='80'?ok('弹层层级高于底栏（z80）'):bad('层级',b.z);
 }
 await shot('info');
 const close=await ev(`document.querySelector('#sheetBrLocalInfo button').click();
   return {hidden:document.getElementById('sheetBrLocalInfo').classList.contains('hidden')};`);
 (!close.__err&&close.hidden)?ok('「知道了」关闭弹层'):bad('关闭',JSON.stringify(close));

 /* C · 重复进详情页不重复插条 */
 const c=await ev(`closeSheet('sheetBrLocalInfo');renderBookDetail();renderBookDetail();
   return {n:document.querySelectorAll('#brDstrip').length};`);
 (!c.__err&&c.n===1)?ok('重进详情页不重复插条'):bad('重复插入',JSON.stringify(c));

 /* D · 轮5.1/5.2 不回归 */
 const dk=await ev(`brOpen('b1');brShowChrome();brGotoCh(3);
   return {icons:[...document.querySelectorAll('#brBottom .br-ibtn span')].map(x=>x.textContent).join(','),
     pill:!!document.getElementById('brBackPos')||!!document.getElementById('brBackJump')};`);
 (!dk.__err&&dk.icons==='目录,进度,外观'&&!d.pill)?ok('底栏三图标与零悬浮未回归'):bad('回归',JSON.stringify(dk));

 finish();
 function finish(){
  if(errs.length)errs.slice(0,4).forEach(e=>bad('运行时异常',e));
  log(`== RANGE ${pass} PASS / ${fail} FAIL ==`);
  try{ws&&ws.close()}catch(e){}
  process.exit(fail?1:0);
 }
})();
