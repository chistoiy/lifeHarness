// prototype/checkjs.js — 提取 HTML 内联 <script> 逐块语法检查
const fs=require('fs'),path=require('path');
const file=process.argv[2];
const html=fs.readFileSync(file,'utf8');
const re=/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/g;let m,i=0,bad=0;
while((m=re.exec(html))){i++;
  try{new Function(m[1]);console.log(`script#${i} OK (${m[1].split('\n').length} lines)`)}
  catch(e){bad++;const ln=e.stack||e.message;console.error(`script#${i} FAIL: ${e.message}`);
    const mm=String(e.message).match(/line (\d+)/i);console.error('  at block line',ln.split('\n').slice(0,3).join(' | '))}
}
console.log(bad?`FAILED ${bad}`:'ALL PASS');process.exit(bad?1:0);
