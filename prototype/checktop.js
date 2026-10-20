// prototype/checktop.js — 跨 <script> 顶层词法声明重名检测（浏览器会整块脚本 SyntaxError）
const fs=require('fs');
const html=fs.readFileSync(process.argv[2]||'index-ledger.html','utf8');
const re=/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/g;let m,blocks=[],i=0;
while((m=re.exec(html))){blocks.push({i:++i,src:m[1]})}
const seen=new Map();let bad=0;
function reg(n,bi,line){
  if(seen.has(n)){if(seen.get(n).bi!==bi){console.log('DUP-CROSS',n,'script#'+seen.get(n).bi,'vs script#'+bi,'|',line.trim().slice(0,70));bad++}return}
  seen.set(n,{bi,line})}
for(const b of blocks){
  for(const line of b.src.split('\n')){
    if(!/^(?:let|const|var)\s/.test(line))continue;
    const mms=/^(?:let|const|var)\s+(.*)/.exec(line);
    let depth=0,cur='',parts=[];
    for(const ch of mms[1]){if('([{'.includes(ch))depth++;if(')]}'.includes(ch))depth--;
      if(ch===','&&!depth){parts.push(cur);cur=''}else cur+=ch}
    parts.push(cur);
    for(const p of parts){const nm=/\s*([A-Za-z_$][\w$]*)\s*(=|$|;)/.exec(p);if(nm)reg(nm[1],b.i,line)}
  }
}
console.log(bad?`CROSS-CONFLICTS ${bad}`:'top-level cross-script OK');
process.exit(bad?1:0);
