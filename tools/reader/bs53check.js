/* V1.53 轮3 · 阅读器底栏五图标+三面板+长按选区 原型回归
 * 用法：node --experimental-websocket tools/reader/bs53check.js（截图：BS53_SHOTS=1）
 * 逐态用 ?br53=prog|bright|font|sel 深链新实例，避免互相污染。 */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE=path.resolve('prototype/index-bookshelf.html');
const URLF=url.pathToFileURL(FILE).href;
const PORT=Number(process.env.BS53_PORT||9553);
const SHOTS=process.env.BS53_SHOTS==='1';
const SHOTDIR='prototype/shots/reader53';
const LOG='tools/reader/bs53-run.log';
let pass=0,fail=0;const errs=[];
const log=m=>{fs.appendFileSync(LOG,m+'\n');console.log(m)};
fs.writeFileSync(LOG,'== bs53check start '+new Date().toISOString()+' ==\n');
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
  '--user-data-dir='+path.resolve('tools/reader/.bs53-profile'),'--disable-extensions','--no-default-browser-check',
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

 /* A · 基线：无深链不自动开面板 */
 await gotoQ('');
 const base=await ev(`return {ibtns:document.querySelectorAll('#brBottom .br-ibtn').length,
   pnl:['brPnlProg','brPnlBright','brPnlFont'].map(i=>document.getElementById(i).classList.contains('hidden')),
   lum:!!document.getElementById('brLumMask'),back:!!document.getElementById('brBackPos')}`);
 (base.ibtns===5)?ok('基线·底栏五图标'):bad('基线图标数',JSON.stringify(base));
 (base.pnl.every(Boolean)&&base.lum&&base.back)?ok('基线·三面板默认收起且遮罩/胶囊就位'):bad('基线面板',JSON.stringify(base));

 /* B · 进度面板（图1） */
 await gotoQ('?br53=prog');
 const pr=await ev(`return {open:!document.getElementById('brPnlProg').classList.contains('hidden'),
   on:document.getElementById('brBtnProg').classList.contains('on'),
   pct:document.getElementById('brStPct').textContent,mins:document.getElementById('brStMin').textContent,
   note:document.getElementById('brStNote').textContent,eta:document.getElementById('brStEta').textContent,
   sl:!!document.getElementById('brProg'),detail:document.querySelector('#brPnlProg button').textContent,
   auto:document.getElementById('brBtnAuto').textContent}`);
 (pr.open&&pr.on&&/^\d+$/.test(pr.pct)&&pr.detail==='阅读明细'&&/自动翻页/.test(pr.auto))
   ?ok('进度面板·统计三格+滑条+两按钮',JSON.stringify(pr)):bad('进度面板',JSON.stringify(pr));
 const au=await ev(`brQuickToggleAuto();const t=document.getElementById('brBtnAuto').textContent;brQuickToggleAuto();return {t,back:document.getElementById('brBtnAuto').textContent}`);
 (/暂停/.test(au.t)&&/开启/.test(au.back))?ok('进度面板·自动翻页一键开关'):bad('自动翻页',JSON.stringify(au));
 await shot('b_prog');

 /* C · 亮度面板（图2） */
 await gotoQ('?br53=bright');
 const br=await ev(`return {open:!document.getElementById('brPnlBright').classList.contains('hidden'),
   colors:document.getElementById('brBtColors').children.length,bgs:document.getElementById('brBtBgs').children.length,
   lum:!!document.getElementById('brBright')}`);
 (br.open&&br.colors===4&&br.bgs===5&&br.lum)?ok('亮度面板·滑条+颜色4档+背景5图',JSON.stringify(br)):bad('亮度面板',JSON.stringify(br));
 const lm=await ev(`brBrightSet(50);const o=document.getElementById('brLumMask').style.opacity;brBrightSet(100);return {o,o2:document.getElementById('brLumMask').style.opacity}`);
 (+lm.o>0.1&&+lm.o2===0)?ok('亮度面板·遮罩随滑条变化'):bad('亮度遮罩',JSON.stringify(lm));
 const tp=await ev(`brThemePick('night');const bg=document.getElementById('brStage').style.background;brThemePick('day');return {bg,bg2:document.getElementById('brStage').style.background}`);
 (/16,\s*19,\s*23/.test(tp.bg)&&/250,\s*246,\s*238/.test(tp.bg2))?ok('亮度面板·颜色档即时换肤可回退'):bad('换肤',JSON.stringify(tp));
 const bp=await ev(`brBgPick(3);const c=document.getElementById('brStage').style.background;brThemePick('day');return {c}`);
 (/246,\s*231,\s*211/.test(bp.c))?ok('亮度面板·背景缩略图生效'):bad('背景',JSON.stringify(bp));
 await shot('c_bright');

 /* D · 字号面板（图3） */
 await gotoQ('?br53=font');
 const fo=await ev(`return {open:!document.getElementById('brPnlFont').classList.contains('hidden'),
   fs:document.getElementById('brFsSl').value,num:document.getElementById('brFsNum').textContent,
   mar:!!document.getElementById('brBtnIndent'),mode:document.getElementById('brModeBtn').textContent}`);
 (fo.open&&+fo.fs>0&&fo.num===String(fo.fs)&&/翻页方式/.test(fo.mode))?ok('字号面板·滑条回填+三chip',JSON.stringify(fo)):bad('字号面板',JSON.stringify(fo));
 const fsr=await ev(`const a=brSt(brV.b).fs;brFsSlSet(a+3);const b=brSt(brV.b).fs;brFsSlSet(a);return {a,b,back:brSt(brV.b).fs}`);
 (fsr.b===fsr.a+3&&fsr.back===fsr.a)?ok('字号面板·滑条即时重排可回退'):bad('字号滑条',JSON.stringify(fsr));
 const mg=await ev(`const a=brSt(brV.b).mar;brMarNudge(1);const b=brSt(brV.b).mar;brMarNudge(-1);const c=brSt(brV.b).lh;brLhNudge(1);const d=brSt(brV.b).lh;brLhNudge(-1);return {a,b,c,d}`);
 (mg.b===mg.a+4&&mg.d>mg.c)?ok('字号面板·边距/行距微调'):bad('微调',JSON.stringify(mg));
 const ind=await ev(`brIndentToggle();const on=document.getElementById('brStage').classList.contains('no-indent');brIndentToggle();return {on}`);
 (ind.on===true)?ok('字号面板·首行缩进开关'):bad('缩进',JSON.stringify(ind));
 await shot('d_font');
 const ex=await ev(`brTogglePanel('prog');return {prog:!document.getElementById('brPnlProg').classList.contains('hidden'),
   fontHidden:document.getElementById('brPnlFont').classList.contains('hidden')}`);
 (ex.prog&&ex.fontHidden)?ok('面板互斥·开进度即收字号'):bad('互斥',JSON.stringify(ex));

 /* E · 长按选区与返回原进度（图4） */
 await gotoQ('?br53=sel');
 const se=await ev(`return {bar:!document.getElementById('brSelBar').classList.contains('hidden'),
   acts:document.getElementById('brSelActs').children.length,
   first:document.getElementById('brSelActs').children[1].textContent,
   para:(document.querySelector('#brBody span[onpointerdown]')||{getAttribute:()=>''}).getAttribute('onpointerdown').slice(0,10),
   zone:(document.getElementById('brZoneC').getAttribute('onpointerdown')||'').slice(0,13),
   pill:!document.getElementById('brBackPos').classList.contains('hidden')}`);
 (se.bar&&se.acts>=10&&/复制/.test(se.first)&&/brLpStart/.test(se.para)&&/brZoneLpStart/.test(se.zone)&&se.pill)
   ?ok('长按选区·工具条弹出且段落/热区均可长按',JSON.stringify(se)):bad('长按选区',JSON.stringify(se));
 await shot('e_sel');
 const hide=await ev(`brSelHide();const before=brV.chrome;brTapCenter();return {before,after:brV.chrome}`);
 (hide.before!==hide.after)?ok('长按后点按恢复 chrome 收放'):bad('点按恢复',JSON.stringify(hide));
 const gh=await ev(`const h={ci:brV.home.ci,pg:brV.home.pg};brSeek(Math.min(brTotal(brV.b)-1,brGPos(brV.b,h.ci,h.pg)+40));
   const pill=!document.getElementById('brBackPos').classList.contains('hidden');brGoHome();
   return {pill,back:brV.ci===h.ci&&brV.pg===h.pg,gone:document.getElementById('brBackPos').classList.contains('hidden')}`);
 (gh.pill&&gh.back&&gh.gone)?ok('拖进度出「返回原进度」胶囊且可归位'):bad('胶囊归位',JSON.stringify(gh));

 const jsErrs=errs.filter(e=>!/favicon/.test(e));
 jsErrs.length?bad('JS 异常 '+jsErrs.length,jsErrs[0].slice(0,200)):ok('无 JS 异常');
 finish();setTimeout(()=>{try{chrome.kill()}catch(e){}},800);
})().catch(e=>{bad('顶层崩溃',String(e).slice(0,300));finish();});
function finish(){log('== 结果 PASS '+pass+' / FAIL '+fail+' ==');process.exit(fail?1:0)}
