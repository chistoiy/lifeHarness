const fs = require('fs'), vm = require('vm');
const F = 'prototype/index_habitcheck.html';
let S = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
let fails = 0;
function rep(t, a, b) {
  const i = S.indexOf(a);
  if (i < 0) { console.log('MISS', t); fails++; return }
  if (S.indexOf(a, i + 1) >= 0) { console.log('DUP', t); fails++; return }
  S = S.slice(0, i) + b + S.slice(i + a.length);
}

/* ---- 1) 记量面板快捷值按目标推导 ---- */
rep('q1', "[5,10,20,30,50].filter(v=>v!==s.goal).concat([s.goal])", "hbQuick(+s.goal||10)");
rep('q2', "[10,15,20,30,45,60].filter(v=>v!==h.goal)", "hbQuick(+h.goal||10)");
rep('qf', "function hbLogStep(k,d){",
`function hbQuick(g){
 const out=[...new Set([Math.max(1,Math.round(g/2)),Math.round(g*1.5),g,g*2,g*3].map(Math.round))].filter(v=>v>0).sort((a,b)=>a-b);
 return out.slice(0,6)}
function hbLogStep(k,d){`);

/* ---- 2) 补卡：超出本周的日期用 ex 记录 + 可补记数值 ---- */
rep('bfmark', "function hbHist(h){const out=[];for(let i=0;i<30;i++){out.push(i>=23?(h.w[i-23]||0):((hbHash(h.id+'d'+i)%10)>(h.type==='neg'?6:4)?(h.type==='neg'?0:1):(h.type==='neg'?1:0)))}return out}",
"function hbHist(h){const out=[];for(let i=0;i<30;i++){if(h.ex&&h.ex[29-i]){out.push(1);continue}out.push(i>=23?(h.w[i-23]||0):((hbHash(h.id+'d'+i)%10)>(h.type==='neg'?6:4)?(h.type==='neg'?0:1):(h.type==='neg'?1:0)))}return out}");
rep('bfamt', `      <div class="mt-3 flex items-center justify-between text-xs"><span>补卡计入连续天数</span><span class="toggle" id="bfStreak" onclick="tgl(this)"></span></div>`,
`      <div id="bfAmtRow" class="hidden mt-3 items-center gap-2 text-xs"><span class="font-bold text-slate-500 shrink-0">补记数值</span><input id="bfAmt" class="inp !w-16 !py-1.5 text-center" type="number" min="0" value="0"><span class="text-slate-400" id="bfAmtUnit">次</span><span class="ml-auto text-[9.5px] text-slate-400">仅本周内可补量</span></div>
      <div class="mt-3 flex items-center justify-between text-xs"><span>补卡计入连续天数</span><span class="toggle" id="bfStreak" onclick="tgl(this)"></span></div>`);
rep('bfopen', `function hbBackfillOpen(id){bfH=id||hbCur;const h=HABITS.find(x=>x.id===bfH)||hbH();bfSel=[];
 document.getElementById('bfTitle').textContent='补卡 · '+h.n;
 document.getElementById('bfSub').textContent='点选要补记的日期（近 30 天）· 今天请在卡片上直接打卡';`,
`function hbBackfillOpen(id){bfH=id||hbCur;const h=HABITS.find(x=>x.id===bfH)||hbH();bfSel=[];
 document.getElementById('bfTitle').textContent='补卡 · '+h.n;
 document.getElementById('bfSub').textContent='点选要补记的日期（近 30 天）· 已补日期会保持标记';
 const ar=document.getElementById('bfAmtRow');if(ar){const on=hbHasVal(h);ar.classList.toggle('hidden',!on);ar.classList.toggle('flex',on);
  document.getElementById('bfAmtUnit').textContent=h.group?'项次合计':(h.unit||'次');
  document.getElementById('bfAmt').value=h.group?h.subs.reduce((a,s)=>a+(+s.goal||0),0):(h.goal||0)}
 document.querySelectorAll('#bfGrid .hb-cell').forEach(c=>c.classList.remove('bf-on'));`);
rep('bfsave', ` bfSel.forEach(b=>{if(b===0){h.w[6]=1}else{h.w[Math.max(0,6-b)]=1}});
 h.mDone=(h.mDone||0)+bfSel.length;if(st)h.streak=(h.streak||0)+bfSel.length;`,
` const amt=Math.max(0,+((document.getElementById('bfAmt')||{}).value||0));
 h.ex=h.ex||{};
 bfSel.forEach(b=>{if(b===0)h.w[6]=1;else if(b<=6)h.w[6-b]=1;else h.ex[b]=1;
  if(amt&&hbHasVal(h)&&b<=6){const k=6-b;
   if(h.group){h.sv=h.sv||[[],[],[],[],[],[],[]];const tot=h.subs.reduce((a,s)=>a+(+s.goal||0),0)||1;
    h.sv[k]=h.subs.map(s=>Math.round((+s.goal||0)/tot*amt));h.v[k]=amt}
   else{h.v=h.v||[0,0,0,0,0,0,0];h.v[k]=amt}}});
 h.mDone=(h.mDone||0)+bfSel.length;if(st)h.streak=(h.streak||0)+bfSel.length;`);
rep('bftoast', `toast('已补记 '+bfSel.length+' 天'+(st?' · 已计入连续':' · 未计入连续'))}`,
 `toast('已补记 '+bfSel.length+' 天'+(amt&&hbHasVal(h)?' · 数值 '+amt:'')+(st?' · 已计入连续':' · 未计入连续'))}`);

if (fails) { console.log('FAILS', fails, 'not written'); process.exit(1) }
const ms = [...S.matchAll(/<script>([\s\S]*?)<\/script>/g)];
try { new vm.Script(ms[ms.length - 1][1]); console.log('SYNTAX OK') } catch (e) { console.log('SYNTAX FAIL', e.message); process.exit(1) }
fs.writeFileSync(F, S.replace(/\n/g, '\r\n'));
console.log('PATCHED');
