/* V1.53.2 轮5.2 · 去胶囊 + 计时自动结算 原型回归
 * 用法：node --experimental-websocket tools/reader/bs57check.js（截图：BS57_SHOTS=1）
 * 深链：?br57=jump|home|set|short|long */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF=url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href;
const PORT=Number(process.env.BS57_PORT||9557);
const SHOTS=process.env.BS57_SHOTS==='1';
const SHOTDIR='prototype/shots/reader57';
let pass=0,fail=0;const errs=[];
const LOG='tools/reader/bs57-run.log';
fs.writeFileSync(LOG,'== bs57check start '+new Date().toISOString()+' ==\n');
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
async function gotoQ(q){await cmd('Page.navigate',{url:URLF+q});await wait(2600)}

(async()=>{
 if(!fs.existsSync(CHROME)){bad('chrome 存在');return finish()}
 spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,
  '--user-data-dir='+path.resolve('tools/reader/.bs57-profile'),'--disable-extensions','--no-default-browser-check',
  '--window-size=430,900','--allow-file-access-from-files','about:blank'],{stdio:'ignore'});
 let d=null;
 for(let i=0;i<60;i++){d=await get('http://127.0.0.1:'+PORT+'/json');if(d){try{if(JSON.parse(d).some(x=>x.type==='page'))break}catch(e){}}await wait(300)}
 if(!d){bad('调试端口');return finish()}
 ws=new WebSocket(JSON.parse(d).find(t=>t.type==='page').webSocketDebuggerUrl);
 await new Promise(r=>{ws.addEventListener('open',r);setTimeout(r,3000)});
 ws.addEventListener('message',e2=>{const m=JSON.parse(e2.data);
  if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}
  if(m.method==='Runtime.exceptionThrown')errs.push(((m.params.exceptionDetails.exception||{}).description||'').slice(0,240))});
 await cmd('Runtime.enable');await cmd('Page.enable');

 /* A · 正文区不再有任何悬浮「返回」胶囊 */
 await gotoQ('');
 const pills=await ev(`brOpen('b1');brShowChrome();brGotoCh(5);
   const stage=document.getElementById('brStage');
   const floats=[...document.querySelectorAll('#p-readerPage > button, #p-readerPage > div')]
     .filter(x=>/返回/.test(x.textContent||'')&&getComputedStyle(x).position==='absolute')
     .map(x=>x.id);
   return {old:!!document.getElementById('brBackPos')||!!document.getElementById('brBackJump'),
     floats,inStage:!!stage.querySelector('#brBackJump,#brBackPos'),
     drBar:!!document.getElementById('brDrBack'),progHome:!!document.getElementById('brProgHome')};`);
 if(pills.__err)bad('胶囊读取',pills.__err);
 else{
  (!pills.old&&pills.floats.length===0&&!pills.inStage)?ok('正文区无任何悬浮返回胶囊'):bad('仍有胶囊',JSON.stringify(pills));
  (pills.drBar&&pills.progHome)?ok('返回入口改挂抽屉横条与进度弹层'):bad('新入口缺失',JSON.stringify(pills));
 }

 /* B · 跳章后：开抽屉见「回到刚才在读」，点它回到原章 */
 const jb=await ev(`brTocOpen('toc');
   const bar=document.getElementById('brDrBack');
   const shown=!bar.classList.contains('hidden');
   const lbl=document.getElementById('brDrBackLbl').textContent;
   const from=brV.home.ci;
   bar.click();
   return {shown,lbl,from,to:brV.ci,hiddenAfter:bar.classList.contains('hidden')};`);
 if(jb.__err)bad('抽屉返回',jb.__err);
 else (jb.shown&&jb.to===jb.from&&jb.hiddenAfter&&jb.lbl)
  ?ok('抽屉「回到刚才在读」→ 回到跳章前并收起',`「${jb.lbl}」 ci${jb.from}→ci${jb.to}`):bad('抽屉返回',JSON.stringify(jb));
 await shot('drawer-back');

 /* C · 进度弹层「回到进书位置」：在位时隐藏，拖离后出现且可点 */
 const ph=await ev(`brGoHome();brV.ci=brV.home.ci;brV.pg=brV.home.pg;brRenderPage();brProgSheet();
   const atHome=document.getElementById('brProgHome').classList.contains('hidden');
   brSeek(Math.round(document.getElementById('brProg').max*0.7));
   const away=!document.getElementById('brProgHome').classList.contains('hidden');
   const txt=document.getElementById('brProgHome').textContent;
   document.getElementById('brProgHome').click();
   return {atHome,away,txt,backCi:brV.ci,homeCi:brV.home.ci,
     sheetOpen:!document.getElementById('sheetBrProg').classList.contains('hidden')};`);
 if(ph.__err)bad('进度弹层返回',ph.__err);
 else (ph.atHome&&ph.away&&ph.backCi===ph.homeCi)
  ?ok('进度弹层「回到进书位置」按偏离显隐并可回位',ph.txt):bad('进度弹层返回',JSON.stringify(ph));
 await shot('prog-home');

 /* D · 设置项：短于 N 秒不计入 · 默认 30 */
 const st=await ev(`const g=(typeof BS_SET_GROUPS!=='undefined'?BS_SET_GROUPS:[]).flat?null:0;
   const row=[...document.querySelectorAll('#p-settings *, #sheetSet *')].length;
   const txt=document.body.innerHTML;
   return {def:BS_SET.brMinSecs,has:/短于该时长的阅读不计入/.test(txt),
     gate:brMinGate(),opts:(function(){const m=txt.match(/\\[5,10,15,30,60,120,300\\]/);return m?m[0]:null})()};`);
 if(st.__err)bad('设置项',st.__err);
 else (st.def===30&&st.has&&st.gate===30&&st.opts)
  ?ok('设置含「短于该时长的阅读不计入」默认 30 秒',st.opts):bad('设置项',JSON.stringify(st));

 /* E · 长会话：自动写入起止章节/页/百分比 */
 const long=await ev(`const b=bsBook('b1');bsSessList(b);   // 先让旧种子落缓存，再量增量
   const before=(BS_SESS_CACHE[b.id]||[]).length;
   brOpen('b1');brV.ownT=1;brV.sessT0=Date.now()-5*60*1000;
   brGotoCh(4);brV.pg=1;
   const t0=brV.sessFrom, t1=brLocSnap();
   brLeave();
   const s=(BS_SESS_CACHE[b.id]||[])[0];
   return {added:(BS_SESS_CACHE[b.id]||[]).length-before,s:s&&{min:s.min,from:s.from,to:s.to,ch0:s.ch0,ch1:s.ch1,p0:s.p0,p1:s.p1,loc1:s.loc1},
     from:t0&&{ch:t0.ch,pg:t0.pg,pct:t0.pct},to:t1&&{ch:t1.ch,pg:t1.pg,pct:t1.pct}};`);
 if(long.__err)bad('长会话',long.__err);
 else if(long.added===1&&long.s&&long.s.ch0&&long.s.ch1&&long.s.from===long.from.pg&&long.s.to===long.to.pg
         &&long.s.p0===long.from.pct&&long.s.p1===long.to.pct&&long.s.loc1)
   ok('退出自动记 章节/页/百分比（无需手动）',`${long.s.ch0} P${long.s.from}·${long.s.p0}% → ${long.s.ch1} P${long.s.to}·${long.s.p1}% · ${long.s.min}分钟`);
 else bad('长会话',JSON.stringify(long));

 /* F · 短会话：低于门槛不入账、不加时长 */
 const short=await ev(`const b=bsBook('b1');bsSessList(b);const n0=(BS_SESS_CACHE[b.id]||[]).length,m0=b.min||0,t0=b.times||0;
   brOpen('b1');brV.ownT=1;brV.sessT0=Date.now()-12*1000;brLeave();
   return {added:(BS_SESS_CACHE[b.id]||[]).length-n0,minDelta:(b.min||0)-m0,timesDelta:(b.times||0)-t0,gate:brMinGate()};`);
 if(short.__err)bad('短会话',short.__err);
 else (short.added===0&&short.minDelta===0&&short.gate===30)
  ?ok('12 秒会话不计入（时长/次数/明细均不动）'):bad('短会话被入账',JSON.stringify(short));
 /* 阈值可改：设成 5 秒后同长度应入账 */
 const gate=await ev(`BS_SET.brMinSecs=5;const b=bsBook('b1');bsSessList(b);const n0=(BS_SESS_CACHE[b.id]||[]).length;
   brOpen('b1');brV.ownT=1;brV.sessT0=Date.now()-12*1000;brLeave();
   BS_SET.brMinSecs=30;
   return {added:(BS_SESS_CACHE[b.id]||[]).length-n0};`);
 (!gate.__err&&gate.added===1)?ok('阈值改成 5 秒后同样时长即计入'):bad('阈值不生效',JSON.stringify(gate));

 /* G · 明细行展示位置摘要 */
 const row=await ev(`bsSessOpen('b1');
   const txt=document.getElementById('rlRoot').textContent;
   const m=txt.match(/P\\d+→P\\d+/);const p=txt.match(/\\d+%→\\d+%/);
   return {pg:m?m[0]:null,pct:p?p[0]:null};`);
 if(row.__err)bad('明细展示',row.__err);
 else (row.pg&&row.pct)?ok('明细行展示起止页与百分比',row.pg+' · '+row.pct):bad('明细展示',JSON.stringify(row));
 await shot('readlog');

 /* H · 轮5.1 不回归：三图标 / 外观弹层无遮挡 / 手柄跟随 */
 await gotoQ('?br56=look');
 const back=await ev(`const b=[...document.querySelectorAll('#sheetBrAppearance button')].find(x=>/保存应用/.test(x.textContent));
   const r=b.getBoundingClientRect();const hit=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2);
   return {icons:[...document.querySelectorAll('#brBottom .br-ibtn span')].map(x=>x.textContent).join(','),
     inSheet:!!(hit&&hit.closest&&hit.closest('#sheetBrAppearance'))};`);
 (!back.__err&&back.icons==='目录,进度,外观'&&back.inSheet)
  ?ok('轮5.1 结构未回归',back.icons):bad('回归',JSON.stringify(back));
 await gotoQ('?br55=sel');
 const hd=await ev(`const s=brV.sel,el=document.querySelector('#brBody [data-pi="'+s.p0+'"]');
   const stage=document.getElementById('brStage').getBoundingClientRect();
   const want=brCharRect(el,s.o0,false);
   return {d:Math.abs(want.left-stage.left-5-parseInt(document.getElementById('brHStart').style.left))};`);
 (!hd.__err&&hd.d<=2)?ok('轮5.1 手柄跟随未回归','偏差 '+hd.d+'px'):bad('手柄回归',JSON.stringify(hd));

 finish();
 function finish(){
  if(errs.length)errs.slice(0,4).forEach(e=>bad('运行时异常',e));
  log(`== RANGE ${pass} PASS / ${fail} FAIL ==`);
  try{ws&&ws.close()}catch(e){}
  process.exit(fail?1:0);
 }
})();
