/* V1.53.2 轮5 · 阅读器四项整改原型补丁（带命中断言与体积护栏）
   ① 长按选区改「词/字 + 首尾拖动手柄」（去前扩/后扩）
   ② 目录抽屉增加「全部折叠 / 全部展开」
   ③ 跳章后 3 秒「返回上一位置」悬浮按钮
   ④ 脚注角标 / 注释卡 / 跳回原处（精排示意）
   ⑤ 底栏页码读数改「约第 X/Y 页 · P%」（与 Flutter 轮4 对齐） */
const fs = require('fs');
const F = 'prototype/index-bookshelf.html';
let src = fs.readFileSync(F, 'utf8');
const origLen = src.length;
let hits = 0;
function rep(name, find, replace, count) {
  count = count || 1;
  const n = src.split(find).length - 1;
  if (n !== count) { console.error('MISS[' + name + '] 命中 ' + n + ' 次（期望 ' + count + '）'); process.exit(1); }
  src = src.split(find).join(replace); hits++;
}
function repRange(name, startMark, endMark, replace) {
  const a = src.indexOf(startMark);
  if (a < 0) { console.error('MISS[' + name + '] 起点'); process.exit(1); }
  const b = src.indexOf(endMark, a);
  if (b < 0) { console.error('MISS[' + name + '] 终点'); process.exit(1); }
  src = src.slice(0, a) + replace + src.slice(b); hits++;
}

/* ---------- 1 · CSS：手柄 / 段内子串高亮 / 返回胶囊 / 注释卡 ---------- */
rep('css', '    #brSelBar .sdb:active{background:rgba(148,163,184,.18)}\n',
  '    #brSelBar .sdb:active{background:rgba(148,163,184,.18)}\n' +
  '    .br-selpart{background:rgba(99,102,241,.30);border-radius:2px}\n' +
  '    .br-h{position:absolute;width:11px;height:11px;border-radius:50%;background:#6366F1;border:2px solid #fff;box-shadow:0 1px 4px rgba(15,23,42,.4);z-index:74;display:none;cursor:grab;touch-action:none}\n' +
  '    .br-h::after{content:"";position:absolute;left:50%;top:-14px;transform:translateX(-50%);width:2px;height:15px;background:#6366F1;border-radius:2px}\n' +
  '    .br-h.br-hend::after{top:auto;bottom:-14px}\n' +
  '    #brBackJump{background:rgba(15,23,42,.9);color:#fff;box-shadow:0 6px 18px rgba(15,23,42,.3)}\n' +
  '    #brNoteCard{box-shadow:0 10px 30px rgba(15,23,42,.28)}\n' +
  '    .br-sup{color:#6366F1;font-size:.72em;vertical-align:super;cursor:pointer;padding:0 1px}\n');

/* ---------- 2 · DOM：返回上一位置胶囊 + 两个手柄 ---------- */
rep('handles',
  '        <button id="brBackPos" class="hidden absolute bottom-24 left-1/2 -translate-x-1/2 z-[71] br-chrome rounded-full px-3.5 py-2 text-[10px] font-bold" onclick="brGoHome()">‹ 返回原进度</button>',
  '        <button id="brBackJump" class="hidden absolute bottom-40 left-1/2 -translate-x-1/2 z-[73] rounded-full px-3.5 py-2 text-[10px] font-bold" onclick="brBackJumpGo()">‹ 返回上一位置</button>\n' +
  '        <button id="brBackPos" class="hidden absolute bottom-24 left-1/2 -translate-x-1/2 z-[71] br-chrome rounded-full px-3.5 py-2 text-[10px] font-bold" onclick="brGoHome()">‹ 返回原进度</button>\n' +
  '        <i id="brHStart" class="br-h"></i><i id="brHEnd" class="br-h br-hend"></i>');

/* ---------- 3 · 选区 JS：字符级选区 + 手柄定位/拖拽 ---------- */
repRange('select-js',
  'function brSelect(p0,p1){if(p1==null)p1=p0;brV.sel={ci:brV.ci,p0,p1};',
  'function brSelActsRender(){',
  [
    'function brSelArr(){return brChText(brV.b,brLeaves(brV.b)[brV.sel?brV.sel.ci:brV.ci])}',
    'function brSelect(p0,p1,o0,o1){if(p1==null)p1=p0;const arr=brChText(brV.b,brLeaves(brV.b)[brV.ci]);',
    '  const L=(arr[p0]&&arr[p0].t.length)||0, L1=(arr[p1]&&arr[p1].t.length)||0;',
    '  brV.sel={ci:brV.ci,p0,p1,o0:o0==null?0:Math.max(0,Math.min(o0,L)),o1:o1==null?L1:Math.max(0,Math.min(o1,L1))};',
    '  brSelRefresh()}',
    'function brSelTextCompute(){const s=brV.sel,arr=brChText(brV.b,brLeaves(brV.b)[s.ci]);const out=[];',
    '  for(let i=s.p0;i<=s.p1;i++){const t=(arr[i]&&arr[i].t)||"";',
    '    out.push(i===s.p0&&i===s.p1?t.slice(s.o0,s.o1):i===s.p0?t.slice(s.o0):i===s.p1?t.slice(0,s.o1):t)}',
    '  brV.selTxt=out.join("\\n")}',
    '/* 选区变化＝整页重绘（子串高亮在 brParaInner 里算），再把工具条与手柄放回去 */',
    'function brSelRefresh(){if(!brV.sel)return;brSelTextCompute();brRenderPage();',
    '  const bar=document.getElementById("brSelBar");if(bar&&!bar.classList.contains("hidden")){brSelBarPlace();brHandlePlace()}}',
    'function brSelBarPlace(){const first=document.querySelector(`#brBody [data-pi="${brV.sel.p0}"]`);',
    '  const stage=document.getElementById("brStage").getBoundingClientRect();let top=120;',
    '  if(first){const r=first.getBoundingClientRect();top=Math.max(54,r.top-stage.top-46)}',
    '  const bar=document.getElementById("brSelBar");bar.style.left="50%";bar.style.transform="translateX(-50%)";bar.style.top=top+"px"}',
    '/* 屏幕坐标 → (段序, 段内字符偏移)：优先原生 caret，回落按行均分估算 */',
    'function brPtFromXY(cx,cy){',
    '  if(document.caretRangeFromPoint){const r=document.caretRangeFromPoint(cx,cy);',
    '    if(r){const n=r.startContainer;const el=(n.nodeType===3?n.parentElement:n).closest?n.closest("[data-pi]")||(n.parentElement?n.parentElement.closest("[data-pi]"):null):null;',
    '      if(el&&el.closest("#brBody"))return{pi:+el.dataset.pi,off:r.startOffset}}}',
    '  const els=[...document.querySelectorAll("#brBody [data-pi]")];',
    '  for(const el of els){const r=el.getBoundingClientRect();',
    '    if(cx>=r.left&&cx<=r.right&&cy>=r.top&&cy<=r.bottom){const txt=el.textContent||"";',
    '      const lh=parseFloat(getComputedStyle(el).lineHeight)||parseFloat(getComputedStyle(el).fontSize)*1.6;',
    '      const lines=Math.max(1,Math.round(r.height/lh));const per=Math.max(1,Math.floor(txt.length/lines));',
    '      const ln=Math.min(lines-1,Math.max(0,Math.floor((cy-r.top)/lh)));',
    '      return{pi:+el.dataset.pi,off:Math.min(txt.length,ln*per+Math.round((cx-r.left)/Math.max(1,r.width)*per))}}}',
    '  const last=els.length-1;return last<0?null:{pi:+els[last].dataset.pi,off:(els[last].textContent||"").length}}',
    'function brHandlePlace(){const s=brV.sel;if(!s){brHandleHide();return}',
    '  const stage=document.getElementById("brStage").getBoundingClientRect();',
    '  const put=(id,pi,off,end)=>{const el=document.querySelector(`#brBody [data-pi="${pi}"]`);const h=document.getElementById(id);',
    '    if(!el||!h||!el.firstChild){return}',
    '    const rg=document.createRange();rg.selectNodeContents(el);',
    '    let node=el.firstChild,rest=Math.max(0,Math.min(off,node.textContent||"").length);',
    '    rg.setStart(node,rest);rg.collapse(true);',
    '    const rs=rg.getClientRects();const r=(end?rs[rs.length-1]||rs[0]:rs[0])||el.getBoundingClientRect();',
    '    if(!r)return;h.style.display="block";',
    '    h.style.left=(r.left-stage.left+(end?2:-2))+"px";h.style.top=(r.top-stage.top+(end?r.height:-r.height*0.15))+"px"};',
    '  put("brHStart",s.p0,s.o0,false);put("brHEnd",s.p1,s.o1,true)}',
    'function brHandleHide(){["brHStart","brHEnd"].forEach(i=>{const e=document.getElementById(i);if(e)e.style.display="none"})}',
    'function brHandleDrag(which,e){const s=brV.sel;if(!s)return;const p=brPtFromXY(e.clientX,e.clientY);if(!p)return;',
    '  const arr=brChText(brV.b,brLeaves(brV.b)[s.ci]);const len=(arr[p.pi]&&arr[p.pi].t.length)||0;',
    '  const off=Math.max(0,Math.min(p.off,len));',
    '  if(which==="s"){if(p.pi>s.p1||(p.pi===s.p1&&off<s.o1))return;s.p0=p.pi;s.o0=off}',
    '  else{if(p.pi<s.p0||(p.pi===s.p0&&off>s.o0))return;s.p1=p.pi;s.o1=off}',
    '  brSelRefresh()}',
    'function brBindHandles(){["brHStart","brHEnd"].forEach((id,i)=>{const h=document.getElementById(id);if(!h||h.dataset.b)return;h.dataset.b="1";',
    '  const w=i===0?"s":"e";',
    '  h.addEventListener("pointerdown",ev=>{ev.stopPropagation();ev.preventDefault();h._drag=1;try{h.setPointerCapture(ev.pointerId)}catch(e){}});',
    '  h.addEventListener("pointermove",ev=>{if(h._drag){ev.stopPropagation();brHandleDrag(w,ev)}});',
    '  h.addEventListener("pointerup",ev=>{if(!h._drag)return;h._drag=0;try{h.releasePointerCapture(ev.pointerId)}catch(e){}})})}',
    '',
  ].join('\n') + '\n');

/* ---------- 4 · 工具条：去掉「前扩/后扩」两个胶囊按钮 ---------- */
rep('acts',
  '  document.getElementById(\'brSelActs\').innerHTML=`<div class="sdb text-brand-300" onclick="brGrow(-1)"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m14 6-6 6 6 6"/></svg><span>前扩</span></div>`+\n' +
  '   acts.map(a=>`<div class="sdb" onclick="${a[2]}"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${a[1]}</svg><span>${a[0]}</span></div>`).join(\'\')+\n' +
  '   `<div class="sdb text-brand-300" onclick="brGrow(1)"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m10 6 6 6-6 6"/></svg><span>后扩</span></div>`}',
  '  document.getElementById(\'brSelActs\').innerHTML=\n' +
  '   acts.map(a=>`<div class="sdb" onclick="${a[2]}"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${a[1]}</svg><span>${a[0]}</span></div>`).join(\'\')}');

/* ---------- 5 · brGrow 删除（手柄取代） ---------- */
repRange('grow', 'function brGrow(d){if(!brV.sel)return;', 'function brSelHideUI(){', '');

/* ---------- 6 · 收选区时一并收手柄 ---------- */
rep('hideui',
  'function brSelHideUI(){document.getElementById(\'brSelBar\').classList.add(\'hidden\');document.getElementById(\'brColorPop\').classList.add(\'hidden\')}',
  'function brSelHideUI(){document.getElementById(\'brSelBar\').classList.add(\'hidden\');document.getElementById(\'brColorPop\').classList.add(\'hidden\');brHandleHide()}');

/* ---------- 7 · 段内子串高亮（渲染层按 o0/o1 切三段） ---------- */
rep('inner',
  '  return `<span onpointerdown="brLpStart(event,${pi})" onpointerup="brLpEnd()" onpointerleave="brLpCancel()" onpointercancel="brLpCancel()" onclick="event.stopPropagation();brParaTap(${pi})">${inner}</span>`}',
  '  const sel=brV.sel;\n' +
  '  if(sel&&sel.ci===ci&&pi>=sel.p0&&pi<=sel.p1&&x.k!==\'img\'){\n' +
  '    const t=x.t,lo=(pi===sel.p0?sel.o0:0),hi=(pi===sel.p1?sel.o1:t.length);\n' +
  '    inner=brEsc(t.slice(0,lo))+`<span class="br-selpart">${brEsc(t.slice(lo,hi))}</span>`+brEsc(t.slice(hi));\n' +
  '  }\n' +
  '  return `<span onpointerdown="brLpStart(event,${pi})" onpointerup="brLpEnd()" onpointerleave="brLpCancel()" onpointercancel="brLpCancel()" onclick="event.stopPropagation();brParaTap(${pi})">${inner}</span>`}');

/* ---------- 8 · 长按落点 → 词边界（不再整段吞） ---------- */
rep('lp',
  'function brLpStart(e,pi){_brLpFired=false;clearTimeout(_brLpT);_brLpT=setTimeout(()=>{_brLpFired=true;brSelect(pi,pi)},520)}',
  'const BR_WORD_STOP="\\u3002\\uff01\\uff1f\\uff1b\\uff0c\\u3001\\uff1a\\n ,.!?;:";\n' +
  'function brWordAt(t,pos){if(!t)return[0,0];const c=i=>t[i]!==undefined&&BR_WORD_STOP.indexOf(t[i])>=0;\n' +
  '  let a=Math.max(0,Math.min(pos,t.length-1));while(a>0&&c(a))a--;\n' +
  '  let b=a;while(b<t.length&&!c(b))b++;if(b<t.length)b++;\n' +
  '  if(b-a<1)b=Math.min(t.length,a+1);return[a,b]}\n' +
  'function brLpStart(e,pi){_brLpFired=false;clearTimeout(_brLpT);const cx=e.clientX,cy=e.clientY;\n' +
  '  _brLpT=setTimeout(()=>{_brLpFired=true;const p=brPtFromXY(cx,cy);const arr=brChText(brV.b,brLeaves(brV.b)[brV.ci]);\n' +
  '    const usePi=p&&p.pi!=null?p.pi:pi;const t=(arr[usePi]&&arr[usePi].t)||\'\';\n' +
  '    const w=brWordAt(t,p&&p.pi!=null?p.off:0);brSelect(usePi,usePi,w[0],w[1])},520)}');
rep('lpzone',
  '    const p=el&&el.closest?el.closest(\'[data-pi]\'):null;if(p)brSelect(+p.dataset.pi,+p.dataset.pi)},520)}',
  '    const q=brPtFromXY(cx,cy);const arr=brChText(brV.b,brLeaves(brV.b)[brV.ci]);\n' +
  '    const usePi=q&&q.pi!=null?q.pi:(el&&el.closest?+el.closest(\'[data-pi]\').dataset.pi:null);if(usePi==null)return;\n' +
  '    const t=(arr[usePi]&&arr[usePi].t)||\'\';const w=brWordAt(t,q&&q.pi!=null?q.off:0);brSelect(usePi,usePi,w[0],w[1])},520)}');

/* ---------- 9 · 手柄事件绑定（长按抬起后挂上） ---------- */
rep('hbind', 'function brLpEnd(){clearTimeout(_brLpT)}',
  'function brLpEnd(){clearTimeout(_brLpT);brBindHandles()}');

/* ---------- 10 · 目录抽屉：全部折叠 / 全部展开 ---------- */
rep('foldall',
  '                <button onclick="brDrCollapse()" title="折叠到边栏"',
  '                <button onclick="brDrFoldAll()" id="brDrFoldAll" title="全部折叠" class="w-7 h-7 shrink-0 rounded-lg flex items-center justify-center text-slate-400"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 8.5 12 4l5 4.5M7 15.5 12 20l5-4.5"/></svg></button>\n' +
  '                <button onclick="brDrCollapse()" title="折叠到边栏"');
rep('foldallfn',
  'function brDrFold(gi){BR_DR.fold[gi]=!BR_DR.fold[gi];brTocRender()}',
  'function brDrFold(gi){BR_DR.fold[gi]=!BR_DR.fold[gi];brTocRender()}\n' +
  'function brDrFoldAll(){const n=Math.max(1,(BS_TOC[brV.b]||[]).length);\n' +
  '  const allF=Object.keys(BR_DR.fold).filter(k=>BR_DR.fold[k]).length>=n;\n' +
  '  BR_DR.fold={};if(!allF)for(let i=0;i<n;i++)BR_DR.fold[i]=true;brTocRender();\n' +
  '  const b=document.getElementById(\'brDrFoldAll\');if(b)b.title=allF?\'全部折叠\':\'全部展开\';\n' +
  '  toast(allF?\'已展开全部分组\':\'已折叠全部分组\')}');

/* ---------- 11 · 跳章留痕 + 3 秒「返回上一位置」+ 注释卡 ---------- */
rep('jump',
  'function brGotoCh(ci){brV.ci=ci;brV.pg=0;brSavePos();brTocClose();if(curPage!==\'p-readerPage\')navTo(\'p-readerPage\');brRenderPage(true);brFlash(brLeaves(brV.b)[ci])}',
  'let _brJumpFrom=null,_brJumpT=null;\n' +
  'function brGotoCh(ci){_brJumpFrom={ci:brV.ci,pg:brV.pg};brV.ci=ci;brV.pg=0;brSavePos();brTocClose();if(curPage!==\'p-readerPage\')navTo(\'p-readerPage\');brRenderPage(true);brFlash(brLeaves(brV.b)[ci]);brShowBackJump()}\n' +
  'function brShowBackJump(){const b=document.getElementById(\'brBackJump\');if(!b||!_brJumpFrom)return;\n' +
  '  b.classList.remove(\'hidden\');clearTimeout(_brJumpT);_brJumpT=setTimeout(brHideBackJump,3000)}\n' +
  'function brHideBackJump(){clearTimeout(_brJumpT);const b=document.getElementById(\'brBackJump\');if(b)b.classList.add(\'hidden\')}\n' +
  'function brBackJumpGo(){if(!_brJumpFrom)return;const f=_brJumpFrom;_brJumpFrom=null;brHideBackJump();\n' +
  '  brV.ci=f.ci;brV.pg=f.pg;brSavePos();brRenderPage();brFlash(\'已回到上一位置\')}\n' +
  'function brNoteShow(txt,backCi,backPi){const old=document.getElementById(\'brNoteCard\');if(old)old.remove();\n' +
  '  const c=document.createElement(\'div\');c.id=\'brNoteCard\';\n' +
  '  c.className=\'absolute left-4 right-4 bottom-28 z-[76] rounded-2xl p-3.5 text-[12px] leading-relaxed\';\n' +
  '  c.style.cssText=\'background:rgba(15,23,42,.94);color:#E2E8F0\';\n' +
  '  c.innerHTML=`<div class="text-[10px] font-bold mb-1" style="color:#A5B4FC">注释</div><div>${brEsc(txt)}</div>`+\n' +
  '   `<div class="flex gap-2 mt-3"><button class="flex-1 rounded-lg py-1.5 text-[11px] font-bold" style="background:rgba(148,163,184,.22)" onclick="this.parentNode.parentNode.remove()">关闭</button>`+\n' +
  '   `<button class="flex-1 rounded-lg py-1.5 text-[11px] font-bold" style="background:#6366F1;color:#fff" onclick="this.parentNode.parentNode.remove();brNoteBack(${backCi},${backPi})">跳回原处</button></div>`;\n' +
  '  document.getElementById(\'brStage\').appendChild(c)}\n' +
  'function brNoteBack(ci,pi){brV.ci=ci;brV.pg=0;brSavePos();brRenderPage();\n' +
  '  const el=document.querySelector(`#brBody [data-pi="${pi}"]`);if(el)el.scrollIntoView({block:\'center\'});brFlash(\'已跳回原处\')}');

/* ---------- 12 · 中区点按：先收注释卡与返回胶囊 ---------- */
rep('tapcenter',
  'function brTapCenter(){if(_brLpFired){_brLpFired=false;return}if(brV.sel){brSelHide();return}',
  'function brTapCenter(){if(_brLpFired){_brLpFired=false;return}\n' +
  '  const nc=document.getElementById(\'brNoteCard\');if(nc){nc.remove();return}\n' +
  '  const bj=document.getElementById(\'brBackJump\');if(bj&&!bj.classList.contains(\'hidden\')){brHideBackJump();return}\n' +
  '  if(brV.sel){brSelHide();return}');

/* ---------- 13 · 脚注角标（精排示意：上标编号 → 注释卡） ---------- */
rep('foot-note',
  '  if(bid===\'b1\'&&ch===\'4 联想思维\'&&pi===8)inner=',
  '  if(bid===\'b1\'&&ch===\'4 联想思维\'&&pi===2)inner+=\'<span class="br-sup" onclick="event.stopPropagation();brNoteShow(\\\'锚定：启发式之一，判断受最先取得的信息支配，见附录「启发式与偏差清单」。\\\',brV.ci,2)">1</span>\';\n' +
  '  if(bid===\'b1\'&&ch===\'4 联想思维\'&&pi===8)inner=');

/* ---------- 14 · 底栏读数与 Flutter 轮4 对齐 ---------- */
rep('pglbl',
  '  document.getElementById(\'brPgLbl\').textContent=`${brV.pg+1}/${pages.length} 页 · 第 ${gp+1}/${tot} 页 · ${brLivePct()}%`;',
  '  document.getElementById(\'brPgLbl\').textContent=`${brV.pg+1}/${pages.length} 页 · 约第 ${gp+1}/${tot} 页 · ${brLivePct()}%`;');

/* ---------- 15 · 重绘后手柄隐藏（brSelRefresh 会再放回来） ---------- */
rep('repage', '  brChromeLabels();brSelHideUI()}', '  brChromeLabels();brSelHideUI();brHandleHide()}');

/* ---------- 16 · 进书清跳章/注释状态 ---------- */
rep('open-clean',
  "  const p=brPos[id]||{ci:0,pg:0};brV.ci=Math.min(p.ci,brLeaves(id).length-1);brV.pg=p.pg||0;",
  "  _brJumpFrom=null;brHideBackJump();const _nc=document.getElementById('brNoteCard');if(_nc)_nc.remove();\n" +
  "  const p=brPos[id]||{ci:0,pg:0};brV.ci=Math.min(p.ci,brLeaves(id).length-1);brV.pg=p.pg||0;");

fs.writeFileSync(F, src);
const nowLen = src.length;
console.log('hits=' + hits + ' size ' + origLen + ' → ' + nowLen);
if (nowLen < origLen * 0.9) { console.error('体积异常缩小，疑似覆盖'); process.exit(1); }
