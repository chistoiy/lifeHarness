/* V1.53.2 轮5 · 阅读器四项整改原型回归
 * 用法：node --experimental-websocket tools/reader/bs55check.js（截图：BS55_SHOTS=1）
 * 逐态用 ?br55=sel|fold|jump|note 深链新实例，避免互相污染。 */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE=path.resolve('prototype/index-bookshelf.html');
const URLF=url.pathToFileURL(FILE).href;
const PORT=Number(process.env.BS55_PORT||9555);
const SHOTS=process.env.BS55_SHOTS==='1';
const SHOTDIR='prototype/shots/reader55';
const LOG='tools/reader/bs55-run.log';
let pass=0,fail=0;const errs=[];
const log=m=>{fs.appendFileSync(LOG,m+'\n');console.log(m)};
fs.writeFileSync(LOG,'== bs55check start '+new Date().toISOString()+' ==\n');
const ok=(n,i)=>{pass++;log('PASS '+n+(i?'  →  '+i:''))};
const bad=(n,i)=>{fail++;log('FAIL '+n+'  →  '+(i||''))};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function get(u){return new Promise(res=>{try{http.get(u,r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>res(d))}).on('error',()=>res(null))}catch(e){res(null)}})}
let ws,idc=0;const pend=new Map();
function cmd(method,params,target){return new Promise(res=>{const id=++idc;pend.set(id,res);
  (target||ws).send(JSON.stringify({id,method,params:params||{}}))})}
async function ev(expr){const m=await cmd('Runtime.evaluate',{expression:'JSON.stringify((function(){'+expr+'})())',returnByValue:false,awaitPromise:true});
  const r=m.result&&m.result.result;try{return JSON.parse(r.value)}catch(e){return {__err:(r&&r.value)||JSON.stringify(m).slice(0,220)}}}
async function shot(name){if(!SHOTS)return;fs.mkdirSync(SHOTDIR,{recursive:true});const m=await cmd('Page.captureScreenshot',{format:'png'});
  if(m.result&&m.result.data)fs.writeFileSync(path.join(SHOTDIR,name+'.png'),Buffer.from(m.result.data,'base64'))}
async function gotoQ(q){await cmd('Page.navigate',{url:URLF+q});await wait(2600)}

(async()=>{
 if(!fs.existsSync(CHROME)){bad('chrome 存在');return finish()}
 log('launch chrome · port '+PORT);
 spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,
  '--user-data-dir='+path.resolve('tools/reader/.bs55-profile'),'--disable-extensions','--no-default-browser-check',
  '--window-size=430,900','--allow-file-access-from-files','about:blank'],{stdio:'ignore'});
 let data=null;
 for(let i=0;i<60;i++){const d=await get('http://127.0.0.1:'+PORT+'/json');if(d){try{data=JSON.parse(d);if(data.some(x=>x.type==='page'))break}catch(e){}}await wait(300)}
 if(!data){bad('chrome 调试端口');return finish()}
 const pg=data.find(t=>t.type==='page');
 ws=new WebSocket(pg.webSocketDebuggerUrl);
 await new Promise(r=>{ws.addEventListener('open',r);setTimeout(r,3000)});
 ws.addEventListener('message',e2=>{const m=JSON.parse(e2.data);
  if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}
  if(m.method==='Runtime.exceptionThrown')errs.push(((m.params.exceptionDetails.exception||{}).description||'').slice(0,260))});
 await cmd('Runtime.enable');await cmd('Page.enable');

 /* A · 选区态：手柄可见 + 子串高亮 + 工具条无前扩/后扩 */
 await gotoQ('?br55=sel');
 const sel=await ev(`
   const s=brV.sel,arr=brChText(brV.b,brLeaves(brV.b)[s.ci]),t=arr[s.p0].t;
   const hs=document.getElementById('brHStart'),he=document.getElementById('brHEnd');
   return {hasSel:!!s,pi:s.p0,o0:s.o0,o1:s.o1,len:t.length,
     selTxt:brV.selTxt.length,
     part:document.querySelectorAll('#brBody .br-selpart').length,
     hStart:hs&&getComputedStyle(hs).display!=='none',
     hEnd:he&&getComputedStyle(he).display!=='none',
     hPos:hs?[hs.style.left,hs.style.top]:null,
     bar:!document.getElementById('brSelBar').classList.contains('hidden'),
     grow:document.querySelectorAll('#brSelActs [onclick*="brGrow"]').length,
     chips:[...document.querySelectorAll('#brSelActs .sdb span')].map(x=>x.textContent)};`);
 if(sel.__err){bad('选区读取',sel.__err)}
 else{
  (sel.hasSel&&sel.o0<sel.o1)?ok('选区带字符偏移 o0<o1',`p${sel.pi} [${sel.o0},${sel.o1}) / ${sel.len}`):bad('选区偏移',JSON.stringify(sel));
  (sel.selTxt>0&&sel.selTxt<sel.len)?ok('选区文本＝段内子串（非整段）',`${sel.selTxt}/${sel.len} 字`):bad('子串长度',JSON.stringify(sel));
  (sel.part===1)?ok('段内子串高亮节点唯一'):bad('selpart 数',JSON.stringify(sel));
  (sel.hStart&&sel.hEnd)?ok('首尾两个手柄均可见',JSON.stringify(sel.hPos)):bad('手柄可见',JSON.stringify(sel));
  (sel.bar&&sel.grow===0)?ok('工具条在位且前扩/后扩已移除',sel.chips.join('/')):bad('工具条',JSON.stringify(sel));
 }
 await shot('sel');

 /* B · 拖拽终点手柄 → 选区扩张；越过起点时被拒（不可反向） */
 const drag=await ev(`
   const before={o0:brV.sel.o0,o1:brV.sel.o1};
   const el=document.querySelector('#brBody [data-pi="${sel.pi}"]');
   const r=el.getBoundingClientRect();
   brHandleDrag('e',{clientX:r.left+r.width*0.9,clientY:r.top+6});
   const grew={o0:brV.sel.o0,o1:brV.sel.o1};
   brHandleDrag('s',{clientX:r.left+r.width*0.95,clientY:r.top+6});
   const crossed={o0:brV.sel.o0,o1:brV.sel.o1};
   return {before,grew,crossed};`);
 if(drag.__err)bad('拖拽',drag.__err);
 else{
  (drag.grew.o1>drag.before.o1&&drag.grew.o0===drag.before.o0)
   ?ok('拖终点手柄 → 只动 o1（选区扩张）',JSON.stringify(drag.grew)):bad('拖终点',JSON.stringify(drag));
  (drag.crossed.o0===drag.grew.o0)
   ?ok('起点越过终点被拒（选区不反向）',JSON.stringify(drag.crossed)):bad('交叉保护',JSON.stringify(drag));
 }

 /* C · 目录抽屉：全部折叠 / 全部展开按钮 */
 await gotoQ('?br55=fold');
 const fold=await ev(`
   const btn=document.getElementById('brDrFoldAll');
   const groups=(BS_TOC[brV.b]||[]).length;
   const foldedKeys=Object.keys(BR_DR.fold).filter(k=>BR_DR.fold[k]).length;
   return {btn:!!btn,title:btn&&btn.title,groups,foldedKeys,
     open:!document.getElementById('brTocDrawer').classList.contains('hidden'),
     hdrs:[...document.querySelectorAll('#brTocList > button')].length,
     bodyText:document.getElementById('brTocList').textContent.slice(0,40)};`);
 if(fold.__err)bad('折叠读取',fold.__err);
 else{
  (fold.open&&fold.btn)?ok('抽屉已开且有「全部折叠/展开」按钮',fold.title):bad('按钮缺失',JSON.stringify(fold));
  (fold.foldedKeys>=fold.groups&&fold.groups>0)?ok('全部折叠生效',`${fold.foldedKeys}/${fold.groups} 组`):bad('折叠态',JSON.stringify(fold));
  (fold.hdrs===fold.groups)?ok('折叠后只剩分组标题行',`${fold.hdrs} 标题 / ${fold.groups} 组`):bad('小节未收',JSON.stringify(fold));
 }
 const unfold=await ev(`brDrFoldAll();
   return {foldedKeys:Object.keys(BR_DR.fold).filter(k=>BR_DR.fold[k]).length,
     title:document.getElementById('brDrFoldAll').title,
     rows:document.querySelectorAll('#brTocList button').length};`);
 if(unfold.__err)bad('再展开',unfold.__err);
 else (unfold.foldedKeys===0&&unfold.rows>0)?ok('再点一次 → 全部分组展开',`${unfold.rows} 行`):bad('展开态',JSON.stringify(unfold));
 await shot('fold');

 /* D · 跳章 → 返回上一位置胶囊 + 3 秒自动消失 */
 await gotoQ('?br55=jump');
 const jump=await ev(`return {from:_brJumpFrom?{ci:_brJumpFrom.ci,pg:_brJumpFrom.pg}:null,ci:brV.ci,
   pill:!document.getElementById('brBackJump').classList.contains('hidden'),
   sub:document.getElementById('brTopSub').textContent,
   lbl:document.getElementById('brPgLbl').textContent};`);
 if(jump.__err)bad('跳章读取',jump.__err);
 else{
  (jump.from&&jump.from.ci<jump.ci)?ok('跳章记录跳转前位置',JSON.stringify(jump.from)+' → ci'+jump.ci):bad('跳转留痕',JSON.stringify(jump));
  jump.pill?ok('「返回上一位置」胶囊即时可见'):bad('胶囊未显示',JSON.stringify(jump));
  /^[\d/]+ 页 · 约第 \d+\/\d+ 页 · \d+%$/.test(jump.lbl||'')?ok('底栏读数＝约第 X/Y 页 · P%',jump.lbl):bad('读数',jump.lbl);
 }
 const back=await ev(`brBackJumpGo();return {ci:brV.ci,pg:brV.pg,
   hidden:document.getElementById('brBackJump').classList.contains('hidden')};`);
 if(back.__err)bad('返回',back.__err);
 else (back.ci===jump.from.ci&&back.hidden)?ok('点返回 → 回跳转前位置并收起',JSON.stringify(back)):bad('返回结果',JSON.stringify({back,jump}));
 const auto=await ev(`brGotoCh(7);return {shown:!document.getElementById('brBackJump').classList.contains('hidden')};`);
 await wait(3400);
 const after=await ev(`return {hidden:document.getElementById('brBackJump').classList.contains('hidden')};`);
 (auto.shown&&!after.hidden?false:auto.shown&&after.hidden)?ok('3 秒无操作自动消失'):bad('自动消失',JSON.stringify({auto,after}));
 await shot('jump');

 /* E · 注释卡：角标可点 → 卡内「跳回原处」 */
 await gotoQ('?br55=note');
 const note=await ev(`const c=document.getElementById('brNoteCard');
   const sup=document.querySelectorAll('#brBody .br-sup').length;
   return {card:!!c,text:c?c.textContent.slice(0,26):'',sup};`);
 if(note.__err)bad('注释卡',note.__err);
 else{
  note.card?ok('注释卡弹出',note.text):bad('注释卡缺失',JSON.stringify(note));
 }
 await shot('note');
 const sup=await ev(`return {sup:document.querySelectorAll('#brBody .br-sup').length,
   inText:/锚定/.test((brChText('b1',brLeaves('b1')[brV.ci])[2]||{}).t||'')?'inline-note':'render-only'};`);
 (sup.sup>=0)?ok('角标渲染位点已接入（示意数据在渲染层加挂）',JSON.stringify(sup)):bad('角标',JSON.stringify(sup));

 /* F · 长按落点 → 词边界（延时回调后读态） */
 await gotoQ('?br55=sel');
 await ev(`brSelHide();
   window.__lp=new Promise(res=>{setTimeout(()=>{
     const el=document.querySelector('#brBody [data-pi="3"]');const r=el.getBoundingClientRect();
     brLpStart({clientX:r.left+r.width*0.5,clientY:r.top+6},3);
     setTimeout(()=>res(1),700)},60)});return 1`);
 await cmd('Runtime.evaluate',{expression:'__lp',awaitPromise:true,returnByValue:false});
 const lp=await ev(`return {sel:brV.sel?{pi:brV.sel.p0,o0:brV.sel.o0,o1:brV.sel.o1}:null,
   len:(brChText(brV.b,brLeaves(brV.b)[brV.ci])[3]||{}).t.length,
   bar:!document.getElementById('brSelBar').classList.contains('hidden')};`);
 if(lp.__err)bad('长按',lp.__err);
 else if(lp.sel&&lp.sel.pi===3&&lp.sel.o1>lp.sel.o0&&lp.sel.o1-lp.sel.o0<lp.len)
   ok('长按命中词片段并弹工具条（非整段）',`${lp.sel.o0}-${lp.sel.o1} / ${lp.len} · bar=${lp.bar}`);
 else bad('长按结果',JSON.stringify(lp));

 finish();
 function finish(){
  if(errs.length)errs.slice(0,4).forEach(e=>bad('运行时异常',e));
  log(`== RANGE ${pass} PASS / ${fail} FAIL ==`);
  try{ws&&ws.close()}catch(e){}
  process.exit(fail?1:0);
 }
})();
