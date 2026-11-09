// prototype/checkconf.js — 检测记账脚本与既有脚本的全局名冲突
const fs=require('fs');
const html=fs.readFileSync(process.argv[2]||'index-ledger.html','utf8');
const re=/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/g;let m,blocks=[];
while((m=re.exec(html))){blocks.push(m[1])}
const mine=['TODAY','LIC','svgIco','LCATS','lcat','lcatN','L','_seed','rnd','ri','rf','POOL','txSeq','rawTx','seedMonth','LA','money','AMT','lq','eff','accBal','mTx','mStat','catStat','dayMap','WD','wdOf','monthOf','finTouch','ledgerAdd','ledgerDel','ledgerEdit','LED_RENDER','finMonth','finView','finCalSel','txState','exprVal','qkState','qkAcct','ldMode','ldSel','ldCb','_acctCb','txdId','_delArm','openL2','renderL1','toast','stack','curPage','setPage','scopeForPage','TITLES','navTo','openSheet','$'];
const pre=blocks.slice(0,blocks.length-1).join('\n');
let hits=0;
for(const n of new Set(mine)){
  const rr=new RegExp('(^|[^.\\w$])(let|const|var|function)\\s+'+n+'\\b').exec(pre);
  if(rr){hits++;console.log('CONFLICT',n,'->',rr[0].trim().slice(0,50))}
}
console.log(hits?'HAS CONFLICTS':'no conflicts');
