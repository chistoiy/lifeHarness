/* V1.53.2 轮5.1 · 第二轮反馈原型回归
 * 用法：node --experimental-websocket tools/reader/bs56check.js（截图：BS56_SHOTS=1）
 * 覆盖：手柄跟随选区 / 底栏三图标 / 进度与外观弹层 / 自绘取色 / 图片背景 + 轮5 四项不回归 */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF=url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href;
const PORT=Number(process.env.BS56_PORT||9556);
const SHOTS=process.env.BS56_SHOTS==='1';
const SHOTDIR='prototype/shots/reader56';
let pass=0,fail=0;const errs=[];
const LOG='tools/reader/bs56-run.log';
fs.writeFileSync(LOG,'== bs56check start '+new Date().toISOString()+' ==\n');
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
async function gotoQ(q){await cmd('Page.navigate',{url:URLF+q});await wait(2600)}

(async()=>{
 if(!fs.existsSync(CHROME)){bad('chrome 存在');return finish()}
 spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,
  '--user-data-dir='+path.resolve('tools/reader/.bs56-profile'),'--disable-extensions','--no-default-browser-check',
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

 /* A · 底栏三图标 + 内嵌面板已消失 */
 await gotoQ('?br56=look');
 const bar=await ev(`return {icons:[...document.querySelectorAll('#brBottom .br-ibtn span')].map(x=>x.textContent),
   panels:['brPnlProg','brPnlBright','brPnlFont'].map(i=>!!document.getElementById(i)),
   look:!document.getElementById('sheetBrAppearance').classList.contains('hidden'),
   lum:!!document.getElementById('brApLum'),bgs:document.querySelectorAll('#brApBgs button').length,
   tex:document.querySelectorAll('#brApTex button').length,
   nativeColor:document.querySelectorAll('#sheetBrAppearance input[type=color]').length,
   hue:!!document.getElementById('brApHue'),dim:!!document.getElementById('brApDim'),
   imgBtn:!!document.getElementById('brApImgFile')};`);
 if(bar.__err)bad('底栏读取',bar.__err);
 else{
  (bar.icons.join(',')==='目录,进度,外观')?ok('底栏收成三图标',bar.icons.join('/')):bad('图标',JSON.stringify(bar.icons));
  bar.panels.every(x=>!x)?ok('三个内嵌面板已移除'):bad('面板残留',JSON.stringify(bar.panels));
  (bar.look&&bar.lum&&bar.hue&&bar.dim&&bar.imgBtn)?ok('外观弹层含亮度/取色/图片入口'):bad('弹层内容',JSON.stringify(bar));
  (bar.bgs>=5&&bar.tex>=4)?ok('背景色板与纹理就位',`${bar.bgs} 色 / ${bar.tex} 纹理`):bad('色板纹理',JSON.stringify(bar));
  bar.nativeColor===0?ok('未使用系统取色控件（自绘滑条）'):bad('仍有 input[type=color]',bar.nativeColor);
 }
 /* A2 · 弹层按钮必须可点（轮5.1b 修的遮挡：底栏 z-70 压住保存钮） */
 const top=await ev(`const b=[...document.querySelectorAll('#sheetBrAppearance button')]
     .find(x=>/保存应用/.test(x.textContent));
   if(!b)return {err:'no save btn'};
   const r=b.getBoundingClientRect();
   const hit=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2);
   return {z:getComputedStyle(document.getElementById('sheetBrAppearance')).zIndex,
     chromeZ:getComputedStyle(document.getElementById('brBottom')).zIndex,
     inSheet:!!(hit&&hit.closest&&hit.closest('#sheetBrAppearance')),
     hit:hit?(hit.id||hit.className||hit.tagName):'null',
     inView:r.top>=0&&r.bottom<=window.innerHeight};`);
 if(top.__err||top.err)bad('遮挡检测',JSON.stringify(top));
 else (top.inSheet&&top.inView)?ok('保存钮可见且在最上层（无遮挡）',`sheet z${top.z} > 底栏 z${top.chromeZ}`)
   :bad('仍被遮挡',JSON.stringify(top));
 await shot('look');

 /* B · 自定义颜色：拖色相/明度 → 底色变化并作用到预览 */
 const pick=await ev(`const before=brDraft.bg;
   const h=document.getElementById('brApHue'),l=document.getElementById('brApLite');
   h.value=205;l.value=92;h.dispatchEvent(new Event('input'));
   const bgAfter=brDraft.bg;
   brApTgt('fg');h.value=210;l.value=20;l.dispatchEvent(new Event('input'));
   const fgHex=document.getElementById('brApHex').textContent;
   return {before,bgAfter,fg:brDraft.fg,fgHex,theme:brDraft.theme,
     prevBg:getComputedStyle(document.getElementById('brApPrev')).backgroundColor};`);
 if(pick.__err)bad('取色',pick.__err);
 else{
  (pick.bgAfter!==pick.before&&/^hsl\(/.test(pick.bgAfter))?ok('拖色相/明度 → 底色即时改',pick.bgAfter):bad('底色未变',JSON.stringify(pick));
  (/^hsl\(/.test(pick.fg)&&/字色/.test(pick.fgHex))?ok('切「改字色」后写字色',pick.fgHex):bad('字色',JSON.stringify(pick));
  pick.prevBg!=='rgba(0, 0, 0, 0)'?ok('预览卡同步新底色',pick.prevBg):bad('预览未跟',JSON.stringify(pick));
 }

 /* C · 图片背景：纹理 + 淡化写入层叠 */
 const tex=await ev(`brApTexSet(1);brDraft.dim=40;brApCtl();brApPrev();
   const css=brStageBgCss(brDraft);
   return {tex:!!brDraft.bgTex,first:css.image.slice(0,28),count:css.image.split(',').length,
     prevImg:document.getElementById('brApPrev').style.backgroundImage.slice(0,20)};`);
 if(tex.__err)bad('图片背景',tex.__err);
 else (tex.tex&&/linear-gradient/.test(tex.first)&&tex.count>=2)
   ?ok('纹理 + 淡化层叠生效',tex.first+' …'):bad('层叠',JSON.stringify(tex));
 const clr=await ev(`brApTexSet(0);brDraft.bgImg='';brApCtl();
   return {tex:brDraft.bgTex,none:brStageBgCss(brDraft).image};`);
 (clr.__err?false:clr.tex===''&&clr.none==='')?ok('点「无」回到纯色'):bad('清除失败',JSON.stringify(clr));

 /* D · 进度弹层 */
 await gotoQ('?br56=prog');
 const prog=await ev(`return {open:!document.getElementById('sheetBrProg').classList.contains('hidden'),
   embedded:!!document.getElementById('brPnlProg'),
   pct:document.getElementById('brStPct').textContent,min:document.getElementById('brStMin').textContent,
   note:document.getElementById('brStNote').textContent,cfi:document.getElementById('brProgCfi').textContent,
   sl:!!document.getElementById('brProg'),auto:document.getElementById('brBtnAuto').textContent,
   detail:document.getElementById('sheetBrProg').textContent.indexOf('阅读明细')>=0};`);
 if(prog.__err)bad('进度弹层',prog.__err);
 else{
  (prog.open&&!prog.embedded)?ok('进度改弹层且内嵌面板不再存在'):bad('结构',JSON.stringify(prog));
  (prog.cfi&&prog.cfi!=='—'&&prog.sl&&prog.detail)?ok('弹层含统计/滑条/明细/自动翻页',prog.cfi+' · '+prog.auto):bad('内容',JSON.stringify(prog));
 }
 const seek=await ev(`const s=document.getElementById('brProg');s.value=Math.round(s.max*0.6);s.dispatchEvent(new Event('input'));
   return {pct:document.getElementById('brStPct').textContent,ci:brV.ci};`);
 (!seek.__err&&+seek.pct>=50)?ok('弹层内拖进度生效',seek.pct+'% · ci'+seek.ci):bad('拖进度',JSON.stringify(seek));
 await shot('prog');

 /* E · 手柄跟随选区（核心修复） */
 await gotoQ('?br55=sel');
 const h1=await ev(`const s=brV.sel;
   const el=document.querySelector('#brBody [data-pi="'+s.p0+'"]');
   const want=brCharRect(el,s.o0,false);const hs=document.getElementById('brHStart');
   const stage=document.getElementById('brStage').getBoundingClientRect();
   return {want:want?Math.round(want.left-stage.left-5):null,got:parseInt(hs.style.left),
     disp:getComputedStyle(hs).display,sel:{p0:s.p0,o0:s.o0,o1:s.o1}};`);
 if(h1.__err)bad('手柄读取',h1.__err);
 else (h1.disp!=='none'&&Math.abs(h1.want-h1.got)<=2)
   ?ok('起点手柄落在选区首字上',`期望 ${h1.want}px / 实际 ${h1.got}px`):bad('手柄错位',JSON.stringify(h1));
 const move=await ev(`/* 先把终点拖到行尾撑开选区，再把起点往里拖（起点不可越过终点） */
   const el=document.querySelector('#brBody [data-pi="${h1.sel.p0}"]');const r=el.getBoundingClientRect();
   const before=document.getElementById('brHStart').style.left;
   brHandleDrag('e',{clientX:r.left+r.width*0.92,clientY:r.top+6});
   const wide={o0:brV.sel.o0,o1:brV.sel.o1};
   brHandleDrag('s',{clientX:r.left+r.width*0.45,clientY:r.top+6});
   brHandlePlace();
   /* 拖拽会整页重绘，旧节点已脱离文档 → 必须重新取段元素再算期望位 */
   const el2=document.querySelector('#brBody [data-pi="'+brV.sel.p0+'"]');
   const stage=document.getElementById('brStage').getBoundingClientRect();
   const want=brCharRect(el2,brV.sel.o0,false);
   return {before,after:document.getElementById('brHStart').style.left,wide,
     now:{o0:brV.sel.o0,o1:brV.sel.o1},
     want:want?Math.round(want.left-stage.left-5):null};`);
 if(move.__err)bad('拖拽跟随',move.__err);
 else (move.before!==move.after&&move.now.o0!==move.wide.o0&&move.now.o0<move.now.o1
       &&move.want!==null&&Math.abs(move.want-parseInt(move.after))<=2)
   ?ok('拖起点手柄 → 选区与手柄同步跟到新字符位',`o0 ${move.wide.o0}→${move.now.o0} · ${move.before}→${move.after}px（期望 ${move.want}px）`)
   :bad('手柄跟随',JSON.stringify(move));
 await shot('handles');

 /* F · 轮5 三项回归（折叠 / 跳章返回 / 注释卡） */
 await gotoQ('?br55=fold');
 const fold=await ev(`return {btn:!!document.getElementById('brDrFoldAll'),
   folded:Object.keys(BR_DR.fold).filter(k=>BR_DR.fold[k]).length,groups:(BS_TOC[brV.b]||[]).length};`);
 (!fold.__err&&fold.btn&&fold.folded>=fold.groups)?ok('目录一键全折叠仍生效',`${fold.folded}/${fold.groups}`):bad('折叠',JSON.stringify(fold));
 await gotoQ('?br55=jump');
 const jp=await ev(`return {from:_brJumpFrom&&_brJumpFrom.ci,ci:brV.ci,
   pill:!document.getElementById('brBackJump').classList.contains('hidden'),
   lbl:document.getElementById('brPgLbl').textContent};`);
 (!jp.__err&&jp.pill&&jp.from!==null&&jp.from<jp.ci)?ok('跳章留痕与返回胶囊仍生效',jp.from+'→'+jp.ci):bad('跳章',JSON.stringify(jp));
 /^[\d/]+ 页 · 约第 \d+\/\d+ 页 · \d+%$/.test(jp.lbl||'')?ok('底栏读数格式保持',jp.lbl):bad('读数',jp.lbl);
 await gotoQ('?br55=note');
 const nt=await ev(`return {card:!!document.getElementById('brNoteCard')};`);
 (!nt.__err&&nt.card)?ok('注释卡仍弹出'):bad('注释卡',JSON.stringify(nt));

 finish();
 function finish(){
  if(errs.length)errs.slice(0,4).forEach(e=>bad('运行时异常',e));
  log(`== RANGE ${pass} PASS / ${fail} FAIL ==`);
  try{ws&&ws.close()}catch(e){}
  process.exit(fail?1:0);
 }
})();
