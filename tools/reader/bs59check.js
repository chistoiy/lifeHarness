/* V1.53.2 轮5.4 · 阅读器 UI 统一 原型回归
 * 用法：node --experimental-websocket tools/reader/bs59check.js（截图：BS59_SHOTS=1） */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF=url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href;
const PORT=Number(process.env.BS59_PORT||9559);
const SHOTS=process.env.BS59_SHOTS==='1';
const SHOTDIR='prototype/shots/reader59';
let pass=0,fail=0;const errs=[];
const LOG='tools/reader/bs59-run.log';
fs.writeFileSync(LOG,'== bs59check start '+new Date().toISOString()+' ==\n');
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

/* 断言辅助：把 'rgba(r, g, b, a)' 转亮度（注意逗号后有空格） */
const LUM = `const L=c=>{const m=c.match(/(\\d+),\\s*(\\d+),\\s*(\\d+)/);return m?0.299*m[1]+0.587*m[2]+0.114*m[3]:-1};`;
/* 条色有 .18s 过渡，必须等落定再量，否则拿到插值中间色 */
async function probe(setup){
  await ev(setup + ';return 1');
  await wait(420);
  return await ev(LUM + `
    const t=document.getElementById('brTop'),b=document.getElementById('brBottom');
    const cs=getComputedStyle(t);
    return {barL:L(cs.backgroundColor),fg:L(cs.color),botL:L(getComputedStyle(b).backgroundColor),
      rgb:cs.backgroundColor,fgs:cs.color,shown:!t.classList.contains('hidden')};`);
}

(async()=>{
 if(!fs.existsSync(CHROME)){bad('chrome 存在');return finish()}
 spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,
  '--user-data-dir='+path.resolve('tools/reader/.bs59-profile'),'--disable-extensions','--no-default-browser-check',
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
 await cmd('Page.navigate',{url:URLF});await wait(2600);

 /* A · 阅读器内不挂全局计时条，离开后恢复 */
 const a=await ev(`timerTap('read','《思考，快与慢》');
   const onShelf=!document.getElementById('timerBar').classList.contains('hidden');
   brOpen('b1');brShowChrome();
   const inReader=document.getElementById('timerBar').classList.contains('hidden');
   const chip=document.getElementById('brSessChip').textContent;
   return {onShelf,inReader,chip,brBar:!!document.getElementById('brSessChip').className.match(/br-chipbg/)};`);
 if(a.__err)bad('计时条',a.__err);
 else{
  (a.onShelf&&a.inReader)?ok('进阅读器即隐藏全局计时条（离开可恢复）','时长改看顶栏胶囊 '+a.chip):bad('计时条',JSON.stringify(a));
  a.brBar?ok('时长胶囊改吃主题变量'):bad('胶囊未换类',a.chip);
 }

 /* B · 浅色主题：顶/底栏随主题变浅底深字 */
 const light=await probe(`brCfg.theme='day';brPagCache={};brRenderPage();brShowChrome()`);
 if(light.__err)bad('浅色主题条',light.__err);
 else (light.barL>150&&light.fg<150&&light.botL>150&&light.shown)
   ?ok('日间主题下顶/底栏＝浅底深字',`栏亮度 ${Math.round(light.barL)} · 字亮度 ${Math.round(light.fg)} · ${light.rgb}`)
   :bad('浅色未生效',JSON.stringify(light));
 await shot('day');

 /* C · 夜间主题：回到深栏浅字 */
 const night=await probe(`brCfg.theme='night';brPagCache={};brRenderPage();brShowChrome()`);
 (!night.__err&&night.barL<120&&night.fg>150)
   ?ok('夜间主题下顶/底栏＝深栏浅字',`栏亮度 ${Math.round(night.barL)} · 字亮度 ${Math.round(night.fg)}`)
   :bad('夜间',JSON.stringify(night));
 await shot('night');

 /* D · 自定义深色底（用户自选颜色）也应判成深栏 */
 const custom=await probe(`brCfg.theme='custom';brCfg.bg='#2b3a2f';brCfg.fg='#e6f0e6';brPagCache={};brRenderPage();brShowChrome()`);
 (!custom.__err&&custom.barL<130&&custom.fg>150)
   ?ok('自定义深底色自动配深栏',custom.rgb):bad('自定义取色',JSON.stringify(custom));

 /* E · 护眼（浅绿）主题：条应是浅绿而非黑 */
 const eye=await probe(`brCfg.theme='eye';brPagCache={};brRenderPage();brShowChrome()`);
 (!eye.__err&&eye.barL>150&&eye.fg<150)
   ?ok('护眼主题下顶栏是浅绿而非黑底',eye.rgb):bad('护眼',JSON.stringify(eye));
 await shot('eye');

 /* F · 从自定义深色切回内置主题：正文底色必须回到主题色（防「深底深字」） */
 const contrast=await probe(`brCfg.theme='custom';brCfg.bg='#2b3a2f';brCfg.fg='#e6f0e6';brPagCache={};brRenderPage();
   brCfg.theme='eye';brPagCache={};brRenderPage();brShowChrome()`);
 if(contrast.__err)bad('对比度',contrast.__err);
 else{
  const stageL=await ev(LUM+`return {L:L(getComputedStyle(document.getElementById('brStage')).backgroundColor),
    fg:L(getComputedStyle(document.getElementById('brStage')).color),
    bg:getComputedStyle(document.getElementById('brStage')).backgroundColor};`);
  (!stageL.__err&&stageL.L>150&&stageL.fg<150&&Math.abs(stageL.L-stageL.fg)>80)
   ?ok('切回护眼主题后正文浅底深字（对比差 '+Math.round(stageL.L-stageL.fg)+'）',stageL.bg)
   :bad('深底深字回归',JSON.stringify(stageL));
 }
 await shot('contrast');

 /* G · 轮5.1~5.3 不回归 */
 const reg=await ev(`brCfg.theme='day';brPagCache={};brRenderPage();
   return {icons:[...document.querySelectorAll('#brBottom .br-ibtn span')].map(x=>x.textContent).join(','),
     pill:!!document.getElementById('brBackPos')||!!document.getElementById('brBackJump'),
     prog:!!document.getElementById('sheetBrProg'),look:!!document.getElementById('brApLum'),
     strip:(BR_OLD_SHOPEN('b1'),!!document.getElementById('brDstrip'))};`);
 (!reg.__err&&reg.icons==='目录,进度,外观'&&!reg.pill&&reg.prog&&reg.look)
   ?ok('三图标/零胶囊/两弹层/详情紧凑条均未回归'):bad('回归',JSON.stringify(reg));

 finish();
 function finish(){
  if(errs.length)errs.slice(0,4).forEach(e=>bad('运行时异常',e));
  log(`== RANGE ${pass} PASS / ${fail} FAIL ==`);
  try{ws&&ws.close()}catch(e){}
  process.exit(fail?1:0);
 }
})();
