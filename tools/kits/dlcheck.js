/* 深链可达性校验（单 target · 每次带 query 强制重载以触发 boot 深链） */
const {spawn}=require('child_process');const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const FILE=path.resolve('prototype/index-kits.html');
const BASE=url.pathToFileURL(FILE).href;
const PORT=Number(process.env.KIT_PORT||9551);
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const get=u=>new Promise(res=>{try{http.get(u,r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>res(d))}).on('error',e=>res(null))}catch(e){res(null)}});
const PAGES=['p-tools','p-kitsMng','p-kitsStats','p-kitsPlg','p-kitsPlgDetail','p-dashboard','p-calendar','p-todo','p-profile'];
const TOOLS=['ping','speed','ruler','dist','wheel','rand','pick','comp','datec','imgz','b64','tele','aiapi'];
const cases=[...PAGES.map(p=>({hash:'#'+p,want:p})),...TOOLS.map(k=>({hash:'#p-toolDetail_'+k,want:'p-toolDetail',title:({ping:'Ping 工具',speed:'网络测速',ruler:'尺子',dist:'测距',wheel:'轮盘抽签',rand:'随机数',pick:'取色盘',comp:'互补色方案',datec:'日期计算',imgz:'图片体积缩小',b64:'Base64 转换',tele:'提词器',aiapi:'AI API 验证'})[k]}))];
let pass=0,fail=0;const lines=[];
(async()=>{
 const ch=spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--disable-extensions',
  '--user-data-dir='+path.resolve('tools/kits/.chrome-profile2'),'--remote-debugging-port='+PORT,
  '--host-resolver-rules=MAP *.tailwindcss.com 127.0.0.1,MAP *.googleapis.com 127.0.0.1','about:blank'],{stdio:'ignore'});
 let d=null;for(let i=0;i<50;i++){const x=await get('http://127.0.0.1:'+PORT+'/json');if(x){try{d=JSON.parse(x);break}catch(e){}}await wait(250)}
 if(!d||!d.length){console.log('CDP 无法启动');process.exit(1)}
 const page=d.find(t=>t.type==='page')||d[0];
 const ws=new WebSocket(page.webSocketDebuggerUrl);
 let idc=0;const pend=new Map();
 ws.addEventListener('message',ev=>{const m=JSON.parse(ev.data);if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}});
 const send=(mm,p={})=>new Promise(r=>{const id=++idc;pend.set(id,r);ws.send(JSON.stringify({id,method:mm,params:p}))});
 const evl=async e=>{const r=await send('Runtime.evaluate',{expression:e,returnByValue:true});
  return r.result&&r.result.result?r.result.result.value:null};
 await new Promise(r=>ws.addEventListener('open',r));
 await send('Runtime.enable');await send('Page.enable');
 for(const c of cases){
  const u=BASE+'?dl='+Date.now()+c.hash;
  await send('Page.navigate',{url:u});
  let got=null;
  for(let i=0;i<16;i++){await wait(320);
   got=JSON.parse(await evl(`JSON.stringify({id:(document.querySelector('.page.active')||{}).id||'?',
     title:(document.querySelector('#pageTitle')||{}).textContent||'',
     len:((document.querySelector('.page.active')||{}).innerText||'').length,
     dl:!!window.__kitDl||true})`)||'{}');
   if(got&&got.id===c.want&&got.len>50)break}
  const okTitle=!c.title||(got.title||'').indexOf(c.title)>=0;
  if(got&&got.id===c.want&&got.len>50&&okTitle){lines.push('PASS '+c.hash+' → '+got.id+' · '+got.len+'字'+(c.title?' · '+got.title:''));pass++}
  else{lines.push('FAIL '+c.hash+' → '+(got?got.id+' / '+got.len+'字 / '+got.title:'无'));fail++}
 }
 lines.forEach(l=>console.log(l));
 console.log('== 深链 PASS '+pass+' / FAIL '+fail+' / 共 '+cases.length+' ==');
 fs.writeFileSync('tools/kits/last-deeplink.txt',lines.join('\n')+'\n\nPASS '+pass+' FAIL '+fail);
 ch.kill();process.exit(fail?1:0);
})().catch(e=>{console.error('EX',e.stack);process.exit(2)});
