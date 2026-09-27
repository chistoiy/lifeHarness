/* rdpatch.js · 一次性：修正阅读器片段 + 将片段合入 prototype/index-reader.html
   锚点唯一性强校验；重复执行会被守卫拦截。 */
const fs=require('fs'),P=require('path');
const FRAG=P.join(__dirname,'rd_frag_');
const HTML='prototype/index-reader.html';
function rd(name){return fs.readFileSync(P.join(__dirname,name),'utf8').replace(/\r\n/g,'\n')}

/* ---------- 第 0 步：片段自身修正 ---------- */
let js=rd('rd_frag_js.txt');
if(js.includes('function rdDelOpen')){console.log('[0/3] 片段已是修正版，跳过修正')}else{
function fix(name,from,to,count){ // count=期望替换次数
  const n=js.split(from).length-1;
  if(n!==(count||1)){console.error('片段修正锚点异常 ['+name+'] 命中 '+n+' 次，期望 '+(count||1));process.exit(1)}
  js=js.split(from).join(to)}

fix('esc-quote',"function rdEsc(s){return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}",
  "function rdEsc(s){return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\"/g,'&quot;')}\nfunction rdRx(s){return (s||'').replace(/[.*+?^${}()|[\\]\\\\]/g,'\\\\$&')}");
fix('para-hl-broken',
  "  const wrap=c?`<span class=\"rdhl\" style=\"background:${RD_HLC[c][0]}${RD_THEMES[rdSt(b).theme]?c4a:''}\" onclick=\"event.stopPropagation();rdSelect(${pi},${pi})\">${inner}</span>`:`<span onclick=\"event.stopPropagation();rdSelect(${pi},${pi})\">${inner}</span>`;\n  return {inner:wrap,c,an}}\nconst c4a='55';",
  "  const wrap=`<span onclick=\"event.stopPropagation();rdSelect(${pi},${pi})\">${inner}</span>`;\n  return {inner:wrap,c,an}}");
fix('hit-regexp-para',"if(RD_V.hit&&RD_V.hit.b===b&&RD_V.hit.ch===ch&&RD_V.hitPi===pi)inner=inner.replace(new RegExp(rdEsc(RD_V.hit.q),'g'),m=>`<span class=\"rd-cur\">${m}</span>`);",
  "if(RD_V.hit&&RD_V.hit.b===b&&RD_V.hit.ch===ch&&RD_V.hitPi===pi&&RD_V.hit.q)inner=inner.replace(new RegExp(rdRx(rdEsc(RD_V.hit.q)),'g'),m=>`<span class=\"rd-cur\">${m}</span>`);");
fix('img-figure',"  const mk=(x,pi)=>{const r=rdParaHtml(b,ch,x,pi);const sty=x.k==='h'?'class=\"rdp rdp-h\"':x.k==='q'?'class=\"rdp rdp-q\"':'class=\"rdp\"';",
  "  const mk=(x,pi)=>{if(x.k==='img')return `<div class=\"rdp-i\" data-pi=\"${pi}\" onclick=\"event.stopPropagation();rdImgOpen('${rdEsc(x.t)}')\">${rdFigSvg()}<figcaption>${rdEsc(x.t)} · 点击放大 / 保存</figcaption></div>`;const r=rdParaHtml(b,ch,x,pi);const sty=x.k==='h'?'class=\"rdp rdp-h\"':x.k==='q'?'class=\"rdp rdp-q\"':'class=\"rdp\"';");
fix('renderpage-junk',
  "    const last=pages.length-1;const extra=RD_TOC[b].length&&ch===RD_LEAVES(b)[last===-1?0:RD_LEAVES(b).length-1]&&RD_V.pg>=pages.length-1;\n    let body=","    let body=");
fix('animclass','    wrap.innerHTML=body+(anim?\'\':\'\');if(anim)wrap.classList.add(\'rd-swig\');','    wrap.innerHTML=body;if(anim)wrap.classList.add(\'rd-swig\');');
fix('theme-btn-label',"  $('#rdThemeBtn').textContent=RD_THEMES[st.theme]?RD_THEMES[st.theme].n==='夜间'?'夜间':'浅色'/*keep*/&&RD_THEMES[st.theme].n:'自定义';",
  "  $('#rdThemeBtn').textContent=RD_THEMES[st.theme]?RD_THEMES[st.theme].n:'自定义';");
fix('flip-donemark',"    RD_V.ch=lv[ci+1];RD_V.pg=0;rdSavePos();rdRenderPage(true);flash('第 '+(ci+2)+' 章 · '+rdChName(b,RD_V.ch));RD_V.doneMark&&RD_V.doneMark(ci);return}",
  "    RD_V.ch=lv[ci+1];RD_V.pg=0;rdSavePos();rdRenderPage(true);flash('第 '+(ci+2)+' 章 · '+rdChName(b,RD_V.ch));return}");
fix('selgrow',
"function rdSelGrow(d){if(!RD_V.sel)return;const n=rdChText(RD_V.b,RD_V.ch).length;\n  RD_V.sel.p0=Math.max(0,RD_V.sel.p0+(d<0?1:-1)*0);RD_V.sel.p1=Math.min(n-1,RD_V.sel.p1+(d>0?1:-1)*0);\n  if(d<0)RD_V.sel.p0=Math.max(0,RD_V.sel.p0-1);\n  rdSelect(RD_V.sel.p0,RD_V.sel.p1)}",
"function rdSelGrow(d){if(!RD_V.sel)return;const n=rdChText(RD_V.b,RD_V.ch).length;\n  if(d>0)RD_V.sel.p1=Math.min(n-1,RD_V.sel.p1+1);else RD_V.sel.p0=Math.max(0,RD_V.sel.p0-1);\n  rdSelect(RD_V.sel.p0,RD_V.sel.p1)}");
fix('ansave-junk',"    RD_HL.some(h=>h.b===RD_V.b&&h.ch===RD_V.sel.ch)||rdCfg.autoHl;\n","");
fix('ansave-review',
"  if(rdAnEditing){const a=RD_AN.find(x=>x.id===rdAnEditing);a.note=txt;rdSyncNote('an',a.id,true);toast('批注已更新 · 笔记库同步')}\n  else{if(!RD_V.sel){closeSheet('sheetRtAnnot');return}",
"  if(rdAnEditing){const a=RD_AN.find(x=>x.id===rdAnEditing);a.note=txt;rdSyncNote('an',a.id,true);toast('批注已更新 · 笔记库同步')}\n  else if(RD_V.sel&&RD_V.sel.ch===null){const bk=rdBook(rdCurBook);const t='> 评分 '+(bk.rate||'—')+' 星\\n\\n'+txt+'\\n\\n——《'+bk.t+'》读后感 '+(rdAnSync? '': '')+rdMM(new Date());\n    D.notes.unshift({t:`《${bk.t}》读后感 · ${txt.slice(0,12)}…`,txt:t,folder:'关联阅读',words:txt.length,time:rdMM(new Date()),cre:rdMM(new Date()),pin:0,md:0});\n    try{renderNotes()}catch(e){}toast('读后感已写入读书笔记（联动 L18）');rdAnSelClear()}\n  else{if(!RD_V.sel){closeSheet('sheetRtAnnot');return}");
fix('selnull-fix',"  if(curPage==='p-readerNotes')rdRenderNotes()}\nfunction rdReviewSave(id){/* 读后感走 rdAnSave 分支：quote 为评分行 */}",
"  if(curPage==='p-readerNotes')rdRenderNotes()}\nfunction rdAnSelClear(){RD_V.sel=null}");
fix('openbook-clamp',"RD_V.pg=pos?Math.min(pos.pg,Math.max(0,rdPagesOf(id,RD_LEAVES(id)[0]).length-1)):0;",
"RD_V.pg=pos?Math.min(pos.pg,Math.max(0,rdPagesOf(id,pos.ch).length-1)):0;");
fix('gotoc-simplify',"function rdGotoCh(ch,pg){if(!RD_LEAVES(RD_V.b).includes(ch)){const c0=RD_TOC[RD_V.b].find(x=>x.i===ch&&x.lv===2);if(!c0)return;ch=c0.i}\n  RD_V.ch=ch;RD_V.pg=pg||0;",
"function rdGotoCh(ch,pg){if(!RD_LEAVES(RD_V.b).includes(ch))return;\n  RD_V.ch=ch;RD_V.pg=pg||0;");
fix('jumpc-sheet-close',"  if(curPage!=='p-readerPage')navTo('p-readerPage');else closeSheet('sheetRtNotes');","  if(curPage!=='p-readerPage')navTo('p-readerPage');");
fix('hitjump-regexp',"arr.forEach((x,pi)=>{if(x.t&&x.t.includes(q))hits.push({ch,pi,t:x.t})});\n  $('#rdSInfo')","arr.forEach((x,pi)=>{if(x.t&&x.t.includes(q))hits.push({ch,pi,t:x.t})});\n  $('#rdSInfo')");
fix('hitrender-regexp',"${rdEsc(h.t).replace(new RegExp(rdEsc(q),'g'),m=>`<mark class=\"bg-amber-200 dark:bg-amber-500/30 rounded px-0.5\">${m}</mark>`)}",
  "${rdEsc(h.t).replace(new RegExp(rdRx(rdEsc(q)),'g'),m=>`<mark class=\"bg-amber-200 dark:bg-amber-500/30 rounded px-0.5\">${m}</mark>`)}");
fix('seek-nav',"function rdSeek(v){const b=RD_V.b;const p=rdGPosTo(b,+v);RD_V.ch=p.ch;RD_V.pg=p.pg;rdSavePos();rdRenderPage();RD_V.chrome=true;$('#rdTop').classList.remove('hidden');$('#rdBottom').classList.remove('hidden')}",
"function rdSeek(v){const b=RD_V.b;const p=rdGPosTo(b,+v);RD_V.ch=p.ch;RD_V.pg=p.pg;rdSavePos();if(curPage!=='p-readerPage')navTo('p-readerPage');else rdRenderPage();RD_V.chrome=true;$('#rdTop').classList.remove('hidden');$('#rdTop').classList.add('flex');$('#rdBottom').classList.remove('hidden');$('#rdBottom').classList.add('flex')}");
fix('pv-set-book',"function rdPvRender(b){const tp=rdTotalPages(b);","function rdPvRender(b){RD_V.b=b;const tp=rdTotalPages(b);");
fix('fig-cache',"function rdFigSvg(){return ",
"let rdFigCache=null;\nfunction rdFigSvg(){if(rdFigCache)return rdFigCache;return rdFigCache=");
fix('figsvg-usage',"function rdImgOpen(cap){const fig=$('#rdFigSvg').value||'';openSheet('sheetRtImg');","function rdImgOpen(cap){const fig=rdFigSvg();openSheet('sheetRtImg');");
fix('boot-holder',"  /* 图片浮层注入图源 */\n  const holder=document.createElement('div');holder.id='rdFigSvgHolder';holder.style.display='none';holder.innerHTML='<textarea id=\"rdFigSvg\">'+rdFigSvg().replace(/<\\/textarea/g,'')+'</textarea>';document.body.appendChild(holder)}",
"  rdFigSvg()}");
fix('share-guard',"function rdShareSel(){const txt=rdSelText()+'\\n\\n——《'+rdBook(RD_V.b).t+'》'+rdChName(RD_V.b,RD_V.sel?RD_V.sel.ch:RD_V.ch)+' · '+rdCfi(RD_V.b,RD_V.sel?RD_V.sel.ch:RD_V.ch,RD_V.sel?RD_V.sel.p0:RD_V.pg);",
"function rdShareSel(){if(!RD_V.sel)return;const txt=rdSelText()+'\\n\\n——《'+rdBook(RD_V.b).t+'》'+rdChName(RD_V.b,RD_V.sel.ch)+' · '+rdCfi(RD_V.b,RD_V.sel.ch,RD_V.sel.p0);");
fix('note-guard-sel',
"function rdSelToNote(){const bk=rdBook(RD_V.b);const s=RD_V.sel;\n  const cite=rdCfi(bk.id,s.ch,s.p0);const txt='> '+RD_V.selTxt+'\\n\\n——《'+bk.t+'》'+rdChName(bk.id,s.ch)+' · '+cite;",
"function rdSelToNote(){const bk=rdBook(RD_V.b);const s=RD_V.sel||{ch:RD_V.ch,p0:RD_V.pg};const sq=RD_V.selTxt||((rdChText(bk.id,s.ch)[s.p0]||{t:''}).t);\n  const cite=rdCfi(bk.id,s.ch,s.p0);const txt='> '+sq+'\\n\\n——《'+bk.t+'》'+rdChName(bk.id,s.ch)+' · '+cite;");
fix('note-guard-2',"D.notes.unshift({t:`《${bk.t}》摘录 · ${RD_V.selTxt.slice(0,10)}…`,txt,folder:'关联阅读',words:RD_V.selTxt.length,","D.notes.unshift({t:`《${bk.t}》摘录 · ${sq.slice(0,10)}…`,txt,folder:'关联阅读',words:sq.length,");
fix('ai-note-guard',"function rdAiToNote(){const bk=rdBook(RD_V.b);const txt=RD_AI.text;\n  D.notes.unshift({t:`《${bk.t}》AI 解读 · ${rdChName(RD_V.b,RD_V.ch).slice(0,10)}`,txt:'> '+RD_V.selTxt+'\\n\\n'+txt",
"function rdAiToNote(){const bk=rdBook(RD_V.b);const txt=RD_AI.text;const sq=RD_V.selTxt||'';\n  D.notes.unshift({t:`《${bk.t}》AI 解读 · ${rdChName(RD_V.b,RD_V.ch).slice(0,10)}`,txt:'> '+sq+'\\n\\n'+txt");
fix('ap-open-bid',"function rdApOpen(scope){rdApScopeK=scope;rdDraft=JSON.parse(JSON.stringify(scope==='book'?rdSt(RD_V.b!=null?RD_V.b:rdCurBook):rdCfg));\n  if(scope==='book'&&RD_V.b!=null)rdDraft=JSON.parse(JSON.stringify(Object.assign({},rdCfg,rdBooksCfg[RD_V.b]||{})));",
"let rdApBookK=0;\nfunction rdApOpen(scope,bid){rdApScopeK=scope;rdApBookK=(bid!=null?bid:(RD_V.b!=null?RD_V.b:rdCurBook));\n  rdDraft=JSON.parse(JSON.stringify(scope==='book'?Object.assign({},rdCfg,rdBooksCfg[rdApBookK]||{}):rdCfg));");
fix('ap-save-bid',"  if(rdApScopeK==='book'&&RD_V.b!=null)rdBooksCfg[RD_V.b]=Object.assign(rdBooksCfg[RD_V.b]||{},d);else rdCfg=Object.assign(rdCfg,d);",
"  if(rdApScopeK==='book')rdBooksCfg[rdApBookK]=Object.assign(rdBooksCfg[rdApBookK]||{},d);else rdCfg=Object.assign(rdCfg,d);");
fix('ap-scope-reopen',"onclick=\"rdApScopeK='${k}';rdApOpen(rdApScopeK)\"","onclick=\"rdApOpen('${k}')\"");
fix('del-missing',"\nfunction rdReviewPrompt(id){",
`\nlet rdDelId=0,rdDelOpt='cache';
function rdDelOpen(id){rdDelId=id;rdDelOpt='cache';const bk=rdBook(id);$('#rdDelName').textContent=bk.t;rdDelRender();openSheet('sheetRtDelete')}
function rdDelRender(){$('#rdDelOpts').innerHTML=[['cache','仅删除阅读数据','进度 · 外观记忆 · 分页缓存清除 · 保留 EPUB 源文件'],['src','连同源文件一起删除','经系统授权移除 '+'.epub 文件本体（模拟 SAF）']].map(([k,l,s])=>\`<button class="w-full card !py-2.5 text-left flex items-start gap-2.5" onclick="rdDelOpt='\${k}';rdDelRender()"><span class="mt-0.5 w-4 h-4 rounded-full border-2 \${rdDelOpt===k?'border-brand-500 bg-brand-500':'border-slate-300 dark:border-slate-600'} flex items-center justify-center text-[9px] text-white">\${rdDelOpt===k?'✓':''}</span><span><b>\${l}</b><div class="text-[10px] text-slate-400 mt-0.5">\${s}</div></span></button>\`).join('')}
function rdDeleteCommit(){const i=RD_BOOKS.findIndex(b=>b.id===rdDelId);if(i<0)return closeSheet('sheetRtDelete');
  const bk=RD_BOOKS[i];RD_BOOKS.splice(i,1);delete RD_POS[bk.id];delete rdBooksCfg[bk.id];delete RD_TOC[bk.id];rdPagCache={};
  closeSheet('sheetRtDelete');rdPersist();
  if(curPage==='p-readerBook')goBack();rdRenderShelf();
  toast(\`已删除《\${bk.t}》\${rdDelOpt==='src'?'（含源文件）':'（仅阅读数据 · 源文件保留）'} · 批注笔记保留在笔记库\`)}
function rdReviewPrompt(id){`);
fs.writeFileSync(P.join(__dirname,'rd_frag_js.txt'),js);
console.log('[1/3] 片段修正完成');}

/* ---------- 第 1 步：片段内小修 ---------- */
let scr=rd('rd_frag_screens.txt').replace('w-9 h-13','w-9 h-12');
let sh=rd('rd_frag_sheets.txt')
  .replace('inset-0 z-60','inset-0 z-[60]')
  .replace(`onclick="rdApTgl('auto',this)"`,`onclick="rdApTgl('auto',this)"`)
  .replace(`onclick="openSheet('sheetRtExport')"`,`onclick="openSheet('sheetRtExport');rdEx.scope=rdNotesBook<0?'all':'book';if(rdNotesBook>=0)rdCurBook=rdNotesBook;rdExRender()"`);
/* sheetRtMore 两个 toggle 去掉双重 tgl */
sh=sh.replace(`onclick="tgl(this);rdApTgl('bright',this,true)"`,`onclick="rdApTgl('bright',this,true)"`)
     .replace(`onclick="tgl(this);rdTtsFromMore(this)"`,`onclick="rdTtsFromMore(this)"`);

/* ---------- 第 2 步：合入 index-reader.html ---------- */
let html=fs.readFileSync(HTML,'utf8').replace(/\r\n/g,'\n');
if(html.includes('p-readerShelf')){console.error('守卫：index-reader.html 已包含阅读器模块，勿重复执行');process.exit(1)}
function one(name,from,to){const n=html.split(from).length-1;
  if(n!==1){console.error('锚点异常 ['+name+'] 命中 '+n+' 次');process.exit(1)}
  html=html.split(from).join(to)}

one('imm',"const _imm=p==='p-noteEdit'||p==='p-diaryEdit';","const _imm=p==='p-noteEdit'||p==='p-diaryEdit'||p==='p-readerPage';");
one('titles',"'p-sub-aiPromptEdit':['编辑提示词','System / User 模板']};",
  "'p-sub-aiPromptEdit':['编辑提示词','System / User 模板'],'p-readerShelf':['阅读器 · 书架','本地 EPUB · 批注同步笔记库（L18）'],'p-readerImport':['导入 EPUB','Android 13+ 隐私适配 · 本地解析'],'p-readerBook':['书籍资料',''],'p-readerPage':['',''],'p-readerSearch':['全书检索',''],'p-readerNotes':['批注与高亮',''],'p-readerStats':['阅读统计',''],'p-readerSettings':['阅读器设置','外观 · 翻页 · 朗读 · 同步']};");
one('fab',"'p-health':{ico:'💧',act:()=>{water(1);toast('💧 快捷 +1 杯（FAB 随上下文变化）')}}",
  "'p-health':{ico:'💧',act:()=>{water(1);toast('💧 快捷 +1 杯（FAB 随上下文变化）')}},\n /* 阅读器书架：FAB=导入 EPUB */ 'p-readerShelf':{ico:'＋',act:()=>navTo('p-readerImport')}");
one('rectab',`      <div class="mt-3 space-y-3" id="bookList"></div>`,
  `      <div class="mt-3 space-y-3" id="bookList"></div>
        <button onclick="navTo('p-readerShelf')" class="mt-3 w-full card !py-3 flex items-center gap-3 text-left active:scale-[.99] transition">
          <span class="w-9 h-9 rounded-xl bg-brand-50 dark:bg-brand-500/15 flex items-center justify-center text-brand-500"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5V5a2 2 0 0 1 2-2h13v16.5H6a2 2 0 0 0-2 2z"/><path d="M4 19.5A2 2 0 0 1 6 18h13v4H6a2 2 0 0 1-2-2.5z"/></svg></span>
          <div class="flex-1"><div class="text-sm font-bold">打开阅读器 · 本地 EPUB 精读</div><div class="text-[11px] text-slate-400" id="rdShelfSub">划词高亮 / 批注同步笔记库（联动 L18）</div></div>
          <span class="text-slate-300">›</span></button>`);
one('bookdetail',`          <div class="flex gap-2 mt-2">
            <button class="mini-btn" onclick="toast('进度 +1% （模拟）')">读到 62%</button>`,
  `          <div class="flex gap-2 mt-2">
            <button class="mini-btn grad text-white" onclick="rdOpenBook(0)">阅读器打开</button>
            <button class="mini-btn" onclick="toast('进度 +1% （模拟）')">读到 62%</button>`);
one('main','  </main>',scr+'\n  </main>');
one('sheets','  <!-- ===== Toast ===== -->',sh+'\n  <!-- ===== Toast ===== -->');
one('js','renderPwBar();\n</script>','renderPwBar();\n'+js+'\n</script>');
fs.writeFileSync(HTML,html);
console.log('[2/2] index-reader.html 合入完成 · 字节数',html.length);
