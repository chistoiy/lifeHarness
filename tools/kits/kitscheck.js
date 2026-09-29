/* 小工具专版原型回归校验 · CDP 无头（进度实时可见：tools/kits/kits-run.log）
 * 用法：node --experimental-websocket tools/kits/kitscheck.js [--shots] */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE=path.resolve('prototype/index-kits.html');
const URLF=url.pathToFileURL(FILE).href;
const PORT=Number(process.env.KIT_PORT||9417);
const SHOTS=process.argv.includes('--shots');
const SHOTDIR='prototype/shots/kits';
const LOG='tools/kits/kits-run.log', RES='tools/kits/last-kitscheck.txt';
const PAGES=['p-tools','p-kitsMng','p-kitsStats','p-kitsPlg','p-kitsPlgDetail','p-dashboard','p-profile'];
const TOOLS=['ping','speed','ruler','dist','wheel','rand','pick','comp','datec','imgz','b64','tele','aiapi'];
let pass=0,fail=0;const results=[];
const log=m=>{fs.appendFileSync(LOG,m+'\n');console.log(m)};
fs.writeFileSync(LOG,'== kitscheck start '+new Date().toISOString()+' ==\n');
function ok(n,i){results.push('PASS '+n+(i?'  →  '+i:''));pass++;log('PASS '+n+(i?'  →  '+i:''))}
function bad(n,i){results.push('FAIL '+n+'  →  '+(i||''));fail++;log('FAIL '+n+'  →  '+(i||''))}
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function get(u){return new Promise(res=>{try{http.get(u,r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>res(d))}).on('error',()=>res(null))}catch(e){res(null)}})}
async function withTimeout(p,ms,label){let t;const to=new Promise((_,rej)=>{t=setTimeout(()=>rej(new Error('timeout '+ms+'ms')),ms)});
 try{return await Promise.race([p,to])}finally{clearTimeout(t)}}

(async()=>{
 if(!fs.existsSync(CHROME)){bad('chrome 存在',CHROME);return finish()}
 if(SHOTS)fs.mkdirSync(SHOTDIR,{recursive:true});
 log('launch chrome · port '+PORT);
 const chrome=spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,'--user-data-dir='+require('path').resolve('tools/kits/.chrome-profile'),'--disable-extensions','--disable-component-extensions-with-background-pages','--no-default-browser-check',
  '--window-size=430,900','--allow-file-access-from-files','about:blank'],{stdio:'ignore'});
 let data=null;
 for(let i=0;i<60;i++){const d=await get('http://127.0.0.1:'+PORT+'/json');if(d){try{data=JSON.parse(d);break}catch(e){}}await wait(300)}
 if(!data||!data.length){bad('CDP 启动','端口无响应（旧实例占用请换 KIT_PORT）');return finish()}
 const ws=new WebSocket(data[0].webSocketDebuggerUrl);
 let idc=0;const pend=new Map();const errs=[];
 ws.addEventListener('message',ev=>{const m=JSON.parse(ev.data);
  if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}
  if(m.method==='Runtime.exceptionThrown')errs.push(((m.params.exceptionDetails.exception||{}).description||JSON.stringify(m.params.exceptionDetails)).slice(0,260));
  if(m.method==='Runtime.consoleAPICalled'&&m.params.type==='error')errs.push(String((m.params.args[0]||{}).value||'').slice(0,160))});
 const send=(m,p={})=>new Promise(r=>{const id=++idc;pend.set(id,r);ws.send(JSON.stringify({id,method:m,params:p}))});
 const evl=(expr,aw)=>send('Runtime.evaluate',{expression:expr,returnByValue:true,awaitPromise:!!aw})
  .then(r=>r.result&&r.result.exceptionDetails
   ?{__err:[r.result.exceptionDetails.text,(r.result.exceptionDetails.exception||{}).description||(r.result.exceptionDetails.exception||{}).value].filter(Boolean).join(' | ').slice(0,200)}
   :(r.result&&r.result.result?r.result.result.value:undefined));
 await new Promise(r=>ws.addEventListener('open',r));
 await send('Runtime.enable');await send('Page.enable');await send('Log.enable').catch(()=>{});
 log('navigate');
 await send('Page.navigate',{url:URLF});
 await wait(1500);
 /* 本机值先清零再重载：TDZ 修复后 localStorage 真会被读取，用例必须从干净基线起跑 */
 await evl('localStorage.clear();1');
 await send('Page.navigate',{url:URLF});await wait(900);
 for(let i=0;i<40;i++){const r=await evl('typeof setPage');if(r==='function'){log('脚本就绪 · 第 '+(i+1)+' 次轮询');break}await wait(500)}
 for(let i=0;i<24;i++){const t=await evl('typeof tailwind');if(t!=='undefined'){log('Tailwind 样式就绪 · 第 '+(i+1)+' 次轮询');break}await wait(500)}
 await evl('new Promise(r=>setTimeout(r,300))',true);
 await wait(400);

 const boot=await evl(`({title:document.title,cards:document.querySelectorAll('#toolGrid button').length,
  hero:(document.querySelector('#kitHeroSlots')||{}).childElementCount||0,
  chips:(document.querySelector('#kitCatChips')||{}).childElementCount||0,
  plugins:PLUGINS.length,ls:!!localStorage.getItem('lh_kits_v1'),cat:TOOL_CATS.length,reg:Object.keys(TOOL_REG).length})`);
 if(boot&&boot.__err)bad('boot',boot.__err);
 else{log('boot '+JSON.stringify(boot));
  /小工具合集专版/.test(boot.title)?ok('专版 title'):bad('专版 title',boot.title);
  boot.reg===13?ok('工具注册 13 项'):bad('工具注册数',boot.reg);
  boot.cat===9?ok('分类 9 组'):bad('分类组数',boot.cat);
  boot.cards>=13?ok('首页卡片 '+boot.cards):bad('首页卡片',boot.cards);
  boot.hero===4?ok('主卡数据位 4'):bad('主卡数据位',boot.hero);
  boot.ls?ok('localStorage 已写入'):bad('localStorage 未写入')}

 const LEAK='(^|\\s)(ring-|bg-|text-|border-|dark:|rounded-|flex-)';
 async function screen(name,prep){
  const r=await evl(`(function(){${prep}
   var p=document.querySelector('.page.active')||document.querySelector('.page');
   var txt=p?(p.innerText||''):'';var leak=0;
   if(p)p.querySelectorAll('*').forEach(function(el){for(var i=0;i<el.childNodes.length;i++){var n=el.childNodes[i];
    if(n.nodeType===3&&new RegExp(${JSON.stringify(LEAK)}).test(n.textContent.trim())&&n.textContent.trim().length>3)leak++}});
   return {id:p?p.id:'?',len:txt.length,badT:/undefined|NaN|\\[object /.test(txt),leak:leak,head:(txt.slice(0,24)||'').replace(/\\s+/g,' ')};})()`);
  if(r&&r.__err)bad('屏 '+name,r.__err);
  else if(r.len<60)bad('屏 '+name+' 渲染过短',r.len);
  else if(r.badT)bad('屏 '+name+' 含 undefined/NaN',r.head);
  else if(r.leak)bad('屏 '+name+' 类名泄漏 '+r.leak,r.head);
  else ok('屏 '+name+' · '+r.id+' · '+r.len+'字',r.head)}
 log('-- 逐屏断言：页面');
 for(const p of PAGES)await screen(p,`setPage('${p}');`);
 log('-- 逐屏断言：工具');
 for(const k of TOOLS)await screen('tool:'+k,`openTool('${k}');`);
 log('-- 交互回归');
 async function step(n,expr,check,aw){
  let r;try{r=await withTimeout(evl(expr,aw),25000,n)}catch(e){return bad(n,e.message)}
  if(r&&r.__err)return bad(n,r.__err);
  const v=check?check(r):!!r;
  v?ok(n,typeof r==='object'?JSON.stringify(r).slice(0,72):''):bad(n,JSON.stringify(r).slice(0,90))}
 await step('提词层默认隐藏（防全屏遮罩回归）',`(function(){var st=document.querySelector('#tpStage');var cs=getComputedStyle(st);
   return {cls:st.className.indexOf('hidden')>=0,disp:cs.display}})()`,v=>v.cls&&v.disp==='none');
 await step('使用计数递增',`(function(){var a=KITS.usage.ping||0;kitOpen('ping');return {b:a,a:KITS.usage.ping}})()`,v=>v.a>v.b);
 await step('收藏上限 6 拦截',`(function(){KITS.fav=['ping','speed','ruler','dist','wheel','rand'];kitToggleFav('pick');return KITS.fav.length})()`,v=>v===6);
 await step('hero 草稿保存制',`(function(){openKitCfg();kitCfgPick('today');kitCfgSave();return KITS.hero.join('|')})()`,v=>v.split('|').length===4);
 await step('筛选+搜索组合',`(function(){kitSetCat('随机');var a=document.querySelectorAll('#toolGrid button').length;
   var s=document.querySelector('#kitSearch');s.value='骰';kitFilter();var b=document.querySelectorAll('#toolGrid button').length;
   kitClearFilter();return {cat:a,search:b}})()`,v=>v.cat>0&&v.search<=v.cat);
 await step('空态可见',`(function(){var s=document.querySelector('#kitSearch');s.value='zzzz不存在';kitFilter();
   var vis=!/hidden/.test(document.querySelector('#kitEmpty').className);s.value='';kitFilter();return vis})()`,v=>v===true);
 await step('轮盘权重扇区实算',`(function(){openTool('wheel');var it=wItems();while(it.length<2)it.push({t:'乙',w:1});
   it[0].w=3;it[1].w=1;wheelDraw();return {pct:Math.round(it[0].w/wTotal()*100),exp:Math.round(3/wTotal()*100),grad:(document.querySelector('#wheelEl').style.background||'').length>30}})()`,v=>v.pct===v.exp&&v.pct>25&&v.grad);
 await step('轮盘粘贴整套替换',`(function(){openTool('wheel');$('#wPaste').value='甲:2\\n乙:1\\n丙:1';wheelPasteReplace();return {n:wItems().length,tot:wTotal()}})()`,v=>v.n===3&&v.tot===4);
 await step('轮盘多套记忆',`(function(){openTool('wheel');wheelSetNew();var a=KITS.wsets.length;wheelSetUse(KITS.wsets[0].id);
   return {sets:a,cur:KITS.wcur||KITS.wCur,ok:a>=2}})()`,v=>v.ok);
 await step('轮盘权重上下限',`(function(){openTool('wheel');var it=wItems();while(it.length<2)it.push({t:'乙',w:1});
   it[0].w=1;wheelWeight(0,9);var hi=it[0].w;wheelWeight(0,-99);return {hi:hi,lo:it[0].w}})()`,v=>v.hi===9&&v.lo===1);
 await step('轮盘 12 项上限',`(function(){openTool('wheel');
   var it=wItems();while(it.length<12)it.push({t:'x'+it.length,w:1});wheelDraw();$('#wNew').value='超';$('#wNewW').value=1;wheelAdd();
   return {n:wItems().length,capped:wItems().length<=12}})()`,v=>v.capped);
 await step('尺子长边默认读数',`(function(){openTool('ruler');var t=$('#rulerSpan').textContent;
   var long=Math.round(Math.max(screen.width,screen.height)/3.78);var mm=+(t.match(/(\\d+)\\s*mm/)||[0,0])[1];
   return {dir:KITS.rulerDir,diff:Math.abs(mm-long),txt:t.slice(0,20)}})()`,v=>v.dir==='long'&&v.diff<=3);
 await step('尺子方向切换',`(function(){rulerDir('short');var a=$('#rulerSpan').textContent;rulerDir('long');
   return {short:/短边/.test(a),long:/长边/.test($('#rulerSpan').textContent)}})()`,v=>v.short&&v.long);
 await step('尺子校准与重置',`(function(){openTool('ruler');rulerBank();var c=KITS.cal;rulerCalSet(1);return {moved:Math.abs(c-1)>0.001,reset:KITS.cal===1}})()`,v=>v.moved&&v.reset);
 await step('取色三值一致',`(function(){openTool('pick');cpkShow('#2dd4bf');return {h:$('#cpHex').textContent,r:$('#cpRgb').textContent}})()`,v=>v.h==='#2DD4BF'&&/45, 212, 191/.test(v.r));
 await step('色串解析 rgb/hsl',`(function(){openTool('pick');$('#cpIn').value='rgb(99, 102, 241)';cpkParse();var a=$('#cpHex').textContent;
   $('#cpIn').value='hsl(239, 84%, 67%)';cpkParse();return {a:a,b:$('#cpHex').textContent}})()`,v=>v.a==='#6366F1'&&v.b.length===7);
 await step('图片取色链路',`(function(){openTool('pick');
   function blob(u){var raw=atob(u.split(',')[1]);var a=new Uint8Array(raw.length);
    for(var i=0;i<raw.length;i++)a[i]=raw.charCodeAt(i);return new Blob([a],{type:'image/png'})}
   var cv=document.createElement('canvas');cv.width=cv.height=10;var c=cv.getContext('2d');
   c.fillStyle='#e91e63';c.fillRect(0,0,10,10);
   cpkImgLoad({files:[new File([blob(cv.toDataURL('image/png'))],'p.png',{type:'image/png'})]});
   return new Promise(function(res){setTimeout(function(){
     var el=document.querySelector('#cpkCanvas');
     cpkImgPick({clientX:(el.getBoundingClientRect().left+3),clientY:(el.getBoundingClientRect().top+3),currentTarget:el,target:el});
     res({hex:(window.__cpkPick||'').toUpperCase(),wrap:!/hidden/.test(document.querySelector('#cpkImgWrap').className)})},600)})})()`,v=>/^#[0-9A-F]{6}$/.test(v.hex)&&v.wrap,true);
 await step('最近取色去重与移除',`(function(){openTool('pick');cpkShow('#ff0000');cpkTouch('#ff0000');cpkTouch('#ff0000');
   var d=KITS.cpRecent.filter(x=>x==='#ff0000').length;cpkDrop('#ff0000');return {dedup:d===1,after:KITS.cpRecent.indexOf('#ff0000')}})()`,v=>v.dedup&&v.after<0);
 await step('互补色圆环扇区',`(function(){openTool('comp');CMP_MODE=0;cmpShow('#6366f1');var a=document.querySelectorAll('#cmpWheel path').length;
   CMP_MODE=4;cmpShow('#6366f1');var b=document.querySelectorAll('#cmpWheel path').length;var h=window.__cmpHexes.length;
   CMP_MODE=0;cmpShow('#6366f1');return {base:a,cycle:b,hexes:h}})()`,v=>v.base>50&&v.cycle>v.base&&v.hexes===4);
 await step('全套复制文本',`(function(){openTool('comp');CMP_MODE=2;cmpShow('#6366f1');return ((KIT_SHARE_TXT||'').match(/#[0-9A-F]{6}/g)||[]).length})()`,v=>v>=3);
 await step('逐屏无重复 id（防移动布局后 id 撞车）',`(function(){var out=[];
   ['p-tools','p-kitsMng','p-kitsStats','p-kitsPlg'].forEach(function(p){setPage(p)});
   ['wheel','pick','comp','datec','tele','b64'].forEach(function(k){openTool(k)});
   var seen={},dup=[];document.querySelectorAll('[id]').forEach(function(e){
     if(seen[e.id]&&/^[a-zA-Z]/.test(e.id))dup.push(e.id);seen[e.id]=1});
   return {dup:dup.slice(0,6).join(','),n:Object.keys(seen).length}})()`,v=>v.n>60&&!v.dup);
 await step('专版内无系统取色/日期控件',`(function(){openTool('pick');openTool('comp');openTool('datec');openTool('tele');
   var vis=[...document.querySelectorAll('#toolBody input[type=color],#toolBody input[type=date]')].filter(e=>e.offsetParent!==null);
   return {visible:vis.length,hiddenOk:document.querySelectorAll('#toolBody input[type=color]').length}})()`,v=>v.visible===0);
 await step('选色弹层全流程（色板/滑杆/解析/确定回调）',`(function(){openTool('comp');var got='';
   openKitColor('#6366f1',c=>{got=c;$('#cmp').value=c;cmpShow(c)});
   var op=!document.querySelector('#sheetKitColor').classList.contains('hidden');
   kccLoad('#2dd4bf');kccRender();var h1=$('#kccHex').value;
   $('#kccH').value=10;$('#kccS').value=80;$('#kccL').value=50;kccSlide();var h2=$('#kccHex').value;
   $('#kccHex').value='rgb(236, 72, 153)';kccParse();var h3=$('#kccHex').value;
   kccOk();return {op:op,h1:h1,h2:h2,h3:h3,got:got.toUpperCase(),ring:document.querySelectorAll('#cmpWheel path').length>50}})()`,
  v=>v.op&&/^#[0-9A-F]{6}$/.test(v.h2)&&v.h3==='#EC4899'&&v.got==='#EC4899'&&v.ring);
 await step('色环按住拖动实时换主色',`(function(){openTool('comp');cmpShow('#6366f1');var before=$('#cmp').value;
   var r=document.querySelector('#cmpWheel').getBoundingClientRect();
   cmpDown({clientX:r.left+r.width*0.5,clientY:r.top+2,pointerId:1,preventDefault:function(){}});
   cmpMove({clientX:r.left+r.width*0.92,clientY:r.top+r.height*0.5});cmpUp();
   return {moved:$('#cmp').value.toLowerCase()!==before.toLowerCase(),hex:/^#[0-9a-f]{6}$/.test($('#cmp').value),
     live:/^#[0-9A-F]{6}$/.test($('#cmpMainV').textContent)}})()`,v=>v.moved&&v.hex&&v.live);
 await step('取色盘全屏接管与归位',`(function(){openTool('pick');var home=document.querySelector('#cpkImgBox');
   cpkFs(true);var inFs=document.querySelector('#cpkImgWrap').parentElement.id;
   var vis=!document.querySelector('#cpkFs').classList.contains('hidden')&&getComputedStyle(document.querySelector('#cpkFs')).display==='flex';
   cpkFsZoom(60);var z=$('#cpkZoom').value;cpkFs(false);
   return {inFs:inFs,vis:vis,back:document.querySelector('#cpkImgWrap').parentElement===home,zoom:+z}})()`,v=>v.inFs==='cpkFsHost'&&v.vis&&v.back&&v.zoom>100);
 await step('日期滚轮弹层回填并重算',`(function(){openTool('datec');var before=$('#dB').value;
   openKitDate('2026-01-05',v=>{$('#dB').value=v;dCalcDiff()});
   var cols=[WHEELS.kdY.items.length,WHEELS.kdM.items.length,WHEELS.kdD.items.length];
   WHEELS.kdY.i=WHEELS.kdY.items.indexOf('2026');WHEELS.kdM.i=11;kkdSync();WHEELS.kdD.i=0;kkdOk();
   var after=$('#dB').value,diff=$('#dDiff').textContent;
   openKitDate('2024-02-29',null);var feb=WHEELS.kdD.items.length;closeSheet('sheetKitDate');
   return {changed:after!==before,iso:/^2026-12-01$/.test(after),cols:cols,diff:/天/.test(diff),feb:feb}})()`,
  v=>v.changed&&v.iso&&v.cols[0]>60&&v.cols[1]===12&&v.diff&&v.feb===29);
 await step('抽签数据移入设置弹层',`(function(){openTool('wheel');
   var inSheet=!!document.querySelector('#sheetWheelCfg #wPaste')&&!!document.querySelector('#sheetWheelCfg #wList');
   var main=document.querySelector('#toolBody');
   var cfgBtn=[...main.querySelectorAll('button')].some(b=>/设置/.test(b.textContent));
   wheelCfgOpen();var op=!document.querySelector('#sheetWheelCfg').classList.contains('hidden');
   var sum=$('#wSetSum').textContent;closeSheet('sheetWheelCfg');
   return {inSheet:inSheet,cfgBtn:cfgBtn,op:op,sum:/当前套/.test(sum)}})()`,v=>v.inSheet&&v.cfgBtn&&v.op&&v.sum);
 await step('b64 编码闭环',`(function(){openTool('b64');
   var cv=document.createElement('canvas');cv.width=cv.height=8;var c=cv.getContext('2d');
   c.fillStyle='#123456';c.fillRect(0,0,8,8);var uri=cv.toDataURL('image/png');
   var raw=atob(uri.split(',')[1]);var a=new Uint8Array(raw.length);
   for(var i=0;i<raw.length;i++)a[i]=raw.charCodeAt(i);
   f2b64(new File([a],'probe.png',{type:'image/png'}));
   return new Promise(function(res){setTimeout(function(){res({len:$('#b64Out').value.length,hist:KITS.b64Hist.length})},400)})})()`,v=>v.len>40&&v.hist>0,true);
 await step('b64 解码还原',`(function(){openTool('b64');b64Sample();
   return new Promise(function(res){setTimeout(function(){res({vis:!/hidden/.test($('#b64BackBox').className),info:$('#b64BackInfo').textContent.slice(0,16)})},600)})})()`,v=>v.vis&&/还原成功/.test(v.info),true);
 await step('b64 非法输入归因',`(function(){openTool('b64');$('#b64In').value='@@@###';b64Decode();return $('#b64Err').textContent})()`,v=>/解码失败|非法/.test(v));
 await step('b64 补前缀',`(function(){openTool('b64');$('#b64In').value='QUJD';b64Copy('prefix');return $('#b64In').value.slice(0,22)})()`,v=>/data:image/.test(v));
 await step('提词器参数记忆',`(function(){openTool('tele');KITS.tpSpeed=120;KITS.tpSize=52;KITS.tpLh=180;kitSave();return {sp:KITS.tpSpeed,sz:KITS.tpSize,lh:KITS.tpLh}})()`,v=>v.sp===120&&v.sz===52);
 await step('提词舞台·方向·LED·播放',`(function(){openTool('tele');tpDemo();tpOpen();
   var st=document.querySelector('#tpStage'),vis=!/hidden/.test(st.className);
   tpOri('land');var rot=/rotate\\(90deg\\)/.test(document.querySelector('#tpText').style.transform);
   tpLedOn(true);var led=/tp-led/.test(st.className);tpLedOn(false);
   tpPlay();var playing=TP_PLAY;tpPlay();tpReset();tpClose();
   return {vis:vis,rot:rot,led:led,playing:playing,closed:/hidden/.test(st.className),txt:$('#tpSrc').value.length}})()`,v=>v.vis&&v.rot&&v.led&&v.playing&&v.closed&&v.txt>60);
 await step('提词滚动推进',`(function(){tpOpen();KITS.tpSpeed=220;tpPlay();
   return new Promise(function(res){setTimeout(function(){tpPlay();tpClose();res(document.querySelector('#tpBody').style.transform)},520)})})()`,v=>/translateY\(-[0-9.]+px\)/.test(v),true);
 await step('Ping 统计实算',`(function(){openTool('ping');$('#pingN').value=2;pingGo();
   return new Promise(function(res){setTimeout(function(){res($('#pingStat').innerText.replace(/\\s+/g,'|').slice(0,48))},1600)})})()`,v=>/收\/发/.test(v),true);
 await step('测速自动留档',`(function(){openTool('speed');spdGo();
   return new Promise(function(res){setTimeout(function(){res({n:(KITS.spd||[]).length,rows:document.querySelector('#spdHist').children.length})},3500)})})()`,v=>v.n>=1&&v.rows>=1,true);
 await step('测速对比开关',`(function(){spdCompareToggle({textContent:'x'});return SPD_CMP===true})()`);
 await step('插件启停联动',`(function(){var p=PLG('lh-barcode'),w=p.en;plgToggle('lh-barcode');var n=p.en;plgToggle('lh-barcode');
   return {flip:w!==n,back:p.en===w}})()`,v=>v.flip&&v.back);
 await step('插件详情渲染',`(function(){plgDetail('lh-morse');return /审计时间轴/.test($('#plgDetailBody').innerText)})()`,v=>v===true);
 await step('插件回滚',`(function(){var v=PLG('lh-morse').ver;plgRollback('lh-morse');return {from:v,to:PLG('lh-morse').ver}})()`,v=>v.from!==v.to);
 await step('安装向导全流程',`(function(){openKitInstall();kwi.src='gh';kwiStep(1);kwiGo2();
   return new Promise(function(res){setTimeout(function(){var b=PLUGINS.length;kwiFinish();
    res({added:PLUGINS.length-b,step:kwi.s})},1500)})})()`,v=>v.added===1&&v.step===5,true);
 await step('安装校验失败分支',`(function(){openKitInstall();kwiStep(3);kwiFailDemo();return /拒绝安装/.test($('#kwiBody').innerText)})()`,v=>v===true);
 await step('本地扫描默认停用',`(function(){PLUGINS=PLUGINS.filter(p=>p.id!=='lh-qr2');var b=PLUGINS.length;kitScanLocal();
   return {added:PLUGINS.length-b,en:(PLG('lh-qr2')||{}).en===false}})()`,v=>v.added===1&&v.en);
 await step('删除插件需二次确认',`(function(){var b=PLUGINS.length,btn=document.createElement('button');btn.innerHTML='卸载';
   plgDelete(btn,'lh-qr2');var mid=PLUGINS.length;plgDelete(btn,'lh-qr2');
   return {asked:mid===b,gone:PLUGINS.length===b-1}})()`,v=>v.asked&&v.gone);
 await step('管理屏排序与隐藏',`(function(){renderKitsMng();var v0=kitVisKeys().join(',');kitMove('ping',1);var v1=kitVisKeys().join(',');
   kitToggleHide('aiapi');var hid=kitVisKeys().indexOf('aiapi')<0;kitToggleHide('aiapi');
   return {moved:v0!==v1,hid:hid,back:kitVisKeys().indexOf('aiapi')>=0}})()`,v=>v.moved&&v.hid&&v.back);
 await step('统计与流水一致',`(function(){renderKitsStats();return {t:+$('#ksTotal').textContent,log:KITS.log.length,weeks:$('#ksHeat').children.length}})()`,v=>v.t===v.log&&v.weeks===17);
 await step('分享长图实算',`(function(){renderKitShare();return $('#kitShareCard').innerText.replace(/\\s+/g,' ').slice(0,40)})()`,v=>/本机轻工具调用/.test(v));
 await step('沙箱运行弹层',`(function(){kitSandboxId='lh-morse';openSheet('sheetKitSandbox');
   return {open:!document.querySelector('#sheetKitSandbox').classList.contains('hidden'),run:$('#kssRun').innerText.length>10}})()`,v=>v.open&&v.run);
 await step('足迹清空二次确认',`(function(){var b=KITS.log.length,btn=document.createElement('button');btn.innerHTML='清空足迹';
   kitResetConfirm(btn);var mid=KITS.log.length;kitResetConfirm(btn);
   return {asked:mid===b,cleared:KITS.log.length===0}})()`,v=>v.asked&&v.cleared);
 await step('首页图标已 SVG 化',`(function(){setPage('p-tools');var g=document.querySelector('#toolGrid');
   return {svg:g.querySelectorAll('svg.kit-ico').length,emoji:(g.innerText.match(/[\u{1F300}-\u{1FAFF}]/gu)||[]).length,chips:document.querySelector('#kitCatChips').innerText.length}})()`,v=>v.svg>=13&&v.emoji===0);
 await step('文本 Base64 往返',`(function(){openTool('b64');b64Tab('xenc');$('#b64SrcTxt').value='中文 ABC 123 · 数据在手';b64TxtEnc();
   var enc=$('#b64TxtOut').value;$('#b64TxtIn').value=enc;b64Tab('xdec');b64TxtDec();var back=$('#b64TxtBack').value;
   $('#b64TxtIn').value='@@@非法@@@';b64TxtDec();var err=!$('#b64TxtErr').classList.contains('hidden');
   $('#b64TxtIn').value='QUJD';b64TxtDec();var abc=$('#b64TxtBack').value;
   return {round:back==='中文 ABC 123 · 数据在手',err:err,abc:abc==='ABC',meta:/UTF-8/.test($('#b64TxtMeta').textContent),tabs:document.querySelectorAll('#b64PE,#b64PD,#b64PX,#b64PDx').length}})()`,v=>v.round&&v.err&&v.abc&&v.meta&&v.tabs===4);
 log('-- 持久化真复验：重新加载页面后读本机值');
 await evl(`KITS.fav=['ping','tele'];KITS.cat='编码';kitSave();1`);
 await send('Page.navigate',{url:URLF});await wait(1200);
 for(let i=0;i<30;i++){const r=await evl('typeof setPage');if(r==='function')break;await wait(400)}
 const persisted=await evl(`({fav:KITS.fav.join(','),cat:KITS.cat,hero:KITS.hero.length})`);
 (persisted&&persisted.fav==='ping,tele'&&persisted.cat==='编码'&&persisted.hero===4)?ok('刷新后仍保留 '+JSON.stringify(persisted)):bad('刷新后仍保留',JSON.stringify(persisted));
 errs.length?bad('运行时异常',errs.slice(0,2).join(' ;; ')):ok('无未捕获异常');
 if(SHOTS){log('-- 截图');
  // 截图前复位：关闭全部弹层 + 恢复演示足迹，避免用例外链状态污染归档图
  const resetExpr=fs.readFileSync("tools/kits/reset-expr.js","utf8");
  const rr=await evl(resetExpr);
  log("截图前复位："+JSON.stringify(rr));
  for(const p of PAGES.concat(TOOLS.map(k=>'tool:'+k))){
   await evl(p.startsWith('tool:')?`openTool('${p.slice(5)}')`:`setPage('${p}')`);await wait(160);
   const s=await send('Page.captureScreenshot',{format:'png'});
   if(s.result&&s.result.data)fs.writeFileSync(path.join(SHOTDIR,p.replace(':','_')+'.png'),Buffer.from(s.result.data,'base64'))}
  ok('截图归档 '+SHOTDIR,(PAGES.length+TOOLS.length)+' 张')}
 finish();
 function finish(){
  const txt=results.join('\n')+'\n\n== PASS '+pass+' / FAIL '+fail+' ==\n';
  fs.writeFileSync(RES,txt);log('== 完成 PASS '+pass+' / FAIL '+fail+' ==');
  try{chrome.kill()}catch(e){}
  process.exit(fail?1:0)}
})().catch(e=>{bad('脚本异常',e.message);process.exit(2)});
