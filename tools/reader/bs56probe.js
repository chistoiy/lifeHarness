/* 一次性探针：在已加载 ?br55=sel 的页面里手动跑选区流程，把异常原文打出来 */
const {spawn}=require('child_process');
const fs=require('fs'),path=require('path'),http=require('http'),url=require('url');
const CHROME='C:/Program Files/Google/Chrome/Application/chrome.exe';
const URLF=url.pathToFileURL(path.resolve('prototype/index-bookshelf.html')).href;
const PORT=9561;
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function get(u){return new Promise(res=>{try{http.get(u,r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>res(d))}).on('error',()=>res(null))}catch(e){res(null)}})}
let ws,idc=0;const pend=new Map();
function cmd(m,p){return new Promise(res=>{const id=++idc;pend.set(id,res);ws.send(JSON.stringify({id,method:m,params:p||{}}))})}
(async()=>{
 spawn(CHROME,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+PORT,
  '--user-data-dir='+path.resolve('tools/reader/.bs56-probe'),'--window-size=430,900','--allow-file-access-from-files','about:blank'],{stdio:'ignore'});
 let d=null;for(let i=0;i<50;i++){d=await get('http://127.0.0.1:'+PORT+'/json');if(d){try{if(JSON.parse(d).some(x=>x.type==='page'))break}catch(e){}}await wait(300)}
 ws=new WebSocket(JSON.parse(d).find(t=>t.type==='page').webSocketDebuggerUrl);
 await new Promise(r=>{ws.addEventListener('open',r);setTimeout(r,2500)});
 ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id)}});
 await cmd('Runtime.enable');await cmd('Page.enable');
 await cmd('Page.navigate',{url:URLF+'?br55=sel'});await wait(2800);
 for(const expr of [
   "brOpen('b1');'brOpen ok'",
   "brShowChrome();'chrome ok'",
   "(()=>{const el=document.querySelector('#brBody [data-pi=\"2\"]');return el?'found pi2':'no pi2'})()",
   "(()=>{const el=document.querySelector('#brBody [data-pi=\"2\"]');const t=(brChText(brV.b,brLeaves(brV.b)[brV.ci])[2]||{}).t||'';const w=brWordAt(t,4);brSelect(2,2,w[0],w[1]);return 'select ok sel='+JSON.stringify(brV.sel)})()",
   "(()=>{const s=brV.sel;const el=document.querySelector('#brBody [data-pi=\"'+s.p0+'\"]');return 'rect='+JSON.stringify(brCharRect(el,s.o0,false))})()",
   "(()=>{brHandlePlace();const h=document.getElementById('brHStart');return 'hs left='+h.style.left+' top='+h.style.top+' disp='+getComputedStyle(h).display})()",
   "(()=>{try{brProgSheet();return 'prog open='+(!document.getElementById('sheetBrProg').classList.contains('hidden'))}catch(e){return 'prog ERR '+e.message}})()",
   "(()=>{try{brLookSheet();return 'look open='+(!document.getElementById('sheetBrAppearance').classList.contains('hidden'))+' bgs='+document.querySelectorAll('#brApBgs button').length}catch(e){return 'look ERR '+e.message}})()",
   "(()=>{return 'br56 hook m='+(location.search.match(/br56=([a-z]+)/)||['none'])[1]})()",
 ]) {
   const r=await cmd('Runtime.evaluate',{expression:expr,returnByValue:true});
   const v=(r.result&&r.result.result)?r.result.result.value:undefined;
   const ex=(r.result&&r.result.exceptionDetails)?((r.result.exceptionDetails.exception||{}).description||r.result.exceptionDetails.text):'';
   console.log(expr.slice(0,56).replace(/\s+/g,' '),'=>',JSON.stringify(v===undefined?('ERR '+ex):v).slice(0,240));
 }
 ws.close();process.exit(0);
})();
