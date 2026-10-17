function delTaskFromSheet(){const t=D.todos.splice(stIdx,1)[0];t.del='09-19 14:20';D.trash.unshift(t);
  closeSheet('sheetTask');renderTodos();renderQuad();renderTimeline();renderChips();renderTrash();
  toast('已移入垃圾箱 · '+ttKeepTxt())}
/* ================= V1.57 待办垃圾箱（软删 · 保留期与记录管理同源 · 支持批量） ================= */
let ttMode=false,ttSel=new Set(),tpIds=[],ttPressTimer=null;
function ttDaysVal(){const el=document.getElementById('recTrashOpt');const v=el?el.textContent.trim():'30 天';
  return v==='不清理'?0:(parseInt(v,10)||30)}
function ttKeepTxt(){const k=ttDaysVal();return k?'删除 '+k+' 天后自动彻底删除':'不自动清理'}
function ttAgo(t){const md=String(t.del||'').slice(0,5).split('-'); /* 原型今天=09-19 */
  return (9*30+19)-((+md[0]||9)*30+(+md[1]||19))}
function ttLeft(t){const k=ttDaysVal();return k?k-ttAgo(t):null}
function ttLeftTxt(t){const n=ttLeft(t);return n===null?'不清理':(n<=0?'待清理':'剩 '+n+' 天')}
function ttOpen(){ttExitSel();navTo('p-sub-todoTrash');renderTrash()}
function ttSyncKeep(){const k=ttKeepTxt(),m=document.getElementById('todoTrashMeta');
  if(m)m.textContent=D.trash.length+' 项 · '+k;
  const c=document.getElementById('ttCnt');if(c)c.textContent=D.trash.length+' 项';
  const s=document.getElementById('ttKeep');if(s)s.textContent=' · '+k}
function renderTrash(){const el=document.getElementById('ttList');if(!el)return;ttSyncKeep();
  if(!D.trash.length){el.innerHTML='<div class="card !py-10 text-center text-xs text-slate-400">暂无已删除的待办</div>';ttBar();return}
  el.innerHTML=D.trash.map((t,i)=>{const sel=ttSel.has(i),left=ttLeft(t);
    return `<div class="card !py-3 flex items-center gap-3" onmousedown="ttPress(${i})" onmouseup="ttRelease()" onmouseleave="ttRelease()" ontouchstart="ttPress(${i})" ontouchend="ttRelease()" onclick="ttTap(${i})">
      ${ttMode?`<span class="nchk ${sel?'on':''} shrink-0">✓</span>`:`<span class="w-3 h-3 rounded-full ${D.quads[t.q].cls} shrink-0" title="${D.quads[t.q].name}"></span>`}
      <div class="flex-1 min-w-0"><div class="text-sm font-semibold truncate">${t.t}</div>
        <div class="text-[10px] text-slate-400 flex gap-2 mt-0.5 flex-wrap"><span>⏰ ${t.due}</span>${t.tag?`<span>#${t.tag}</span>`:''}<span>删于 ${t.del}</span>
          <span class="${left!==null&&left<=7?'text-rose-500 font-bold':'text-slate-400'}">${ttLeftTxt(t)}</span></div></div>
      ${ttMode?'':`<button class="mini-btn shrink-0" onclick="event.stopPropagation();ttRestore([${i}])">恢复</button>
        <button class="mini-btn shrink-0 !text-rose-500" onclick="event.stopPropagation();tpAsk([${i}])">删除</button>`}</div>`}).join('');
  ttBar();}
function ttPress(i){ttRelease();if(ttMode)return;ttPressTimer=setTimeout(()=>{ttMode=true;ttSel=new Set([i]);renderTrash()},520)}
function ttRelease(){if(ttPressTimer){clearTimeout(ttPressTimer);ttPressTimer=null}}
function ttToggleSel(){if(ttMode){ttExitSel();return}ttMode=true;ttSel.clear();renderTrash()}
function ttExitSel(){ttMode=false;ttSel.clear();renderTrash()}
function ttTap(i){if(!ttMode)return;if(ttSel.has(i))ttSel.delete(i);else ttSel.add(i);
  if(!ttSel.size){ttExitSel();return}renderTrash()}
function ttSelAll(){if(ttSel.size===D.trash.length){ttSel.clear()}else{ttSel=new Set(D.trash.map((_,i)=>i))}
  if(!ttSel.size){ttExitSel();return}renderTrash()}
function ttBar(){const b=document.getElementById('ttSelBar'),all=document.getElementById('ttAllBtn'),pk=document.getElementById('ttPickBtn');
  if(b){b.classList.toggle('hidden',!(ttMode&&ttSel.size));b.classList.toggle('flex',ttMode&&ttSel.size>0)}
  const lbl=document.getElementById('ttSelLbl');if(lbl)lbl.textContent='已选 '+ttSel.size+' 项';
  if(all){all.classList.toggle('hidden',!ttMode);all.textContent=ttSel.size&&ttSel.size===D.trash.length?'取消全选':'全选'}
  if(pk)pk.textContent=ttMode?'取消':'选择'}
function ttRestore(ids){const list=ids.slice().sort((a,b)=>a-b);const back=list.map(i=>D.trash[i]);
  for(let j=list.length-1;j>=0;j--)D.trash.splice(list[j],1);
  back.forEach(t=>{delete t.del;D.todos.push(t)});
  ttSel.clear();if(!ttSel.size)ttMode=false;
  renderTodos();renderQuad();renderTimeline();renderChips();renderTrash();
  toast(list.length===1?'已恢复到「'+D.quads[back[0].q].name+'」':'已恢复 '+list.length+' 项到原象限')}
function ttBatchRestore(){if(!ttSel.size)return;ttRestore([...ttSel])}
function tpAsk(ids){tpIds=ids.slice();const msg=document.getElementById('tpMsg'),lst=document.getElementById('tpList');
  if(msg)msg.textContent='共 '+tpIds.length+' 条 · 删除后不可恢复';
  if(lst)lst.innerHTML=tpIds.map(i=>{const t=D.trash[i];return t?`<div class="rounded-xl bg-slate-100 dark:bg-slate-800 px-3 py-2 flex items-center gap-2"><span class="w-2 h-2 rounded-full ${D.quads[t.q].cls} shrink-0"></span><span class="flex-1 min-w-0 truncate">${t.t}</span><span class="text-slate-400">${ttLeftTxt(t)}</span></div>`:''}).join('');
  openSheet('sheetTrashPurge')}
function ttBatchPurge(){if(!ttSel.size)return;tpAsk([...ttSel].sort((a,b)=>b-a))}
function tpGo(){const n=tpIds.length;tpIds.forEach(i=>D.trash.splice(i,1));tpIds=[];ttSel.clear();ttMode=false;
  closeSheet('sheetTrashPurge');renderTrash();toast('已彻底删除 '+n+' 条')}
/* 记录管理·通用·回收站自动清理 改档后，垃圾箱两处读数同步 */
function recSetChanged(key){if(key==='trash')renderTrash()}
