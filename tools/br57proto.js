/* V1.53.4 阅读器选区体验批 · 原型补丁（prototype/index-bookshelf.html）
 * ② AI 解读二选一＋新「解释」任务形态；③ 发送前审阅 System/User 默认折叠（共用弹层）；
 * ④ 长按选择粒度（选字/选句，默认选字）；⑤ 选区工具条排序+显隐（阅读设置内联管理）；
 * ⑥ 系统「打开方式」EPUB：未导入=导入确认弹层，已导入=提醒+跳书架定位高亮。
 * 护栏：快照 tools/attic/ → 锚点命中断言 → 体积校验 → 按 UTF-8/CRLF 写回。
 * 用法：node tools/br57proto.js
 */
const fs = require('fs');
const P = 'prototype/index-bookshelf.html';
const BAK = 'tools/attic/index-bookshelf.bak-20261001-br57.html';
if (!fs.existsSync(BAK)) fs.copyFileSync(P, BAK);
let H = fs.readFileSync(P, 'utf8');
const STOP = Number(process.env.BR57_STOP || 0);
const SIZE0 = H.length;
const C = '\r\n';
let nRep = 0;
function rep(find, sub, expect, label) {
  if (STOP && nRep >= STOP) { console.log('skip ' + label); return; }
  let n = 0, i = 0;
  while ((i = H.indexOf(find, i)) >= 0) { n++; i += find.length || 1; if (!find.length) break; }
  if (n !== (expect == null ? 1 : expect)) { console.error(`锚点命中 ${n} 次≠${expect == null ? 1 : expect}：${label} —— 中止不写回`); process.exit(1); }
  H = H.split(find).join(sub); nRep++;
  console.log('OK ' + label);
}
function repSlice(startMark, endMark, sub, label) {
  if (STOP && nRep >= STOP) { console.log('skip ' + label); return; }
  const s = H.indexOf(startMark);
  if (s < 0) { console.error('起点锚缺失：' + label); process.exit(1); }
  const eRel = H.indexOf(endMark, s + startMark.length);
  if (eRel < 0) { console.error('终点锚缺失：' + label); process.exit(1); }
  const e = eRel + endMark.length;
  H = H.slice(0, s) + sub + H.slice(e); nRep++;
  console.log(`OK ${label}（替换块 ${e - s} 字符）`);
}

/* ================= ④⑤ 设置：默认值 · 行 · 分支 · 管理函数 ================= */
rep(`brMinSecs:30};`,
  `brMinSecs:30,brSelGran:'选字',brSelOps:['复制','划线','写想法','书摘','查询','X-Ray','AI 解读','分享']};`,
  1, 'A1 BS_SET 默认值');

rep(`不记时长也不记会话']]]];`,
  `不记时长也不记会话'],['brSelGran','长按选择粒度','chips',['选字','选句'],'默认 选字 · 长按命中单字，拖手柄扩选；选句 长按命中整句'],['brSelOps','选区工具条工具','opsSel','勾选并调整顺序 · 移除＝不上工具条']]]];`,
  1, 'A2 RS_SEC 两行');

rep(`  if(ty==='go')return`,
  `  if(ty==='opsSel'){const a=BS_SET.brSelOps&&BS_SET.brSelOps.length?BS_SET.brSelOps:(BS_SET.brSelOps=BR_SEL_ALL.slice());` +
  `const on=a.map((o,i)=>'<div class="flex items-center gap-2 text-[12px]"><button class="mini-btn !text-[10px] !px-2" onclick="bpMv('+i+',-1)">↑</button><button class="mini-btn !text-[10px] !px-2" onclick="bpMv('+i+',1)">↓</button><b>'+o+'</b><button class="ml-auto text-[10px] text-rose-500" onclick="bpRm('+i+')">移除</button></div>').join('');` +
  `const off=BR_SEL_ALL.filter(x=>!a.includes(x)).map(x=>'<button class="chip !text-[10px]" onclick="bpAdd(\\''+x+'\\')">＋ '+x+'</button>').join('');` +
  `return '<div class="py-2.5 border-b border-slate-100 dark:border-slate-800 last:border-0">'+head+'<span class="text-[10px] text-slate-400">'+a.length+' 项</span>'+foot+'<div class="mt-1.5 space-y-1.5">'+on+'</div>'+(off?'<div class="mt-2 flex gap-1.5 flex-wrap">'+off+'</div>':'')+'</div>';}` + C +
  `  if(ty==='go')return`,
  1, 'A3 rsRow opsSel 分支');

rep(`function lpAdd(o){BS_SET.longPress.push(o);renderReadSet()}`,
  `function lpAdd(o){BS_SET.longPress.push(o);renderReadSet()}` + C +
  `/* V1.53.4⑤ 选区工具条：排序/显隐管理（配置口径同长按书籍菜单行） */` + C +
  `function bpArr(){return BS_SET.brSelOps&&BS_SET.brSelOps.length?BS_SET.brSelOps:(BS_SET.brSelOps=BR_SEL_ALL.slice())}` + C +
  `function bpMv(i,d){const a=bpArr();if(i<0||i>=a.length)return;const j=i+d;if(j<0||j>=a.length)return;const t=a[i];a[i]=a[j];a[j]=t;renderReadSet();try{brSelActsRender()}catch(e){}}` + C +
  `function bpRm(i){bpArr().splice(i,1);renderReadSet();try{brSelActsRender()}catch(e){}}` + C +
  `function bpAdd(o){bpArr().push(o);renderReadSet();try{brSelActsRender()}catch(e){}}`,
  1, 'A4 bp 管理函数');

/* ================= ⑤ 工具条渲染改配置驱动 ================= */
repSlice(`function brSelActsRender(){const acts=`, `.join('')}`, [
  `/* V1.53.4⑤ 工具条渲染由配置驱动：名称→[svg,动作]，顺序与显隐取 BS_SET.brSelOps */`,
  `const BR_SEL_TOOLS={`,
  ` '复制':['<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 5.5A1.5 1.5 0 0 0 14.5 4H6a2 2 0 0 0-2 2v8.5A1.5 1.5 0 0 0 5.5 16"/>','brCopy()'],`,
  ` '划线':['<path d="M15 4 4 15v5h5L20 9z"/><path d="M13 6l5 5"/>','brColorShow()'],`,
  ` '写想法':['<path d="M4 20l1-4L16 5l3 3L8 19z"/>','brToThink()'],`,
  ` '书摘':['<path d="M5 4h11l3 3v13H5z"/><path d="M8 9h7M8 13h7"/>','brToQuote()'],`,
  ` '查询':['<circle cx="11" cy="11" r="7"/><path d="m20 20-3.2-3.2"/>','brDictOpen()'],`,
  ` 'AI 解读':['<path d="M12 3v3m0 12v3M3 12h3m12 0h3M6 6l2 2m8 8 2 2m0-12-2 2M8 16l-2 2"/><circle cx="12" cy="12" r="3.2"/>','brAiOpen()'],`,
  ` '分享':['<circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="m8.3 10.8 7.4-3.6M8.3 13.2l7.4 3.6"/>','brShare()']};`,
  `const BR_SEL_ALL=['复制','划线','写想法','书摘','查询','听当前','AI 解读','分享'];`,
  `function brSelActsRender(){const ops=(BS_SET.brSelOps&&BS_SET.brSelOps.length?BS_SET.brSelOps:BR_SEL_ALL).filter(n=>BR_SEL_TOOLS[n]);`,
  ` document.getElementById('brSelActs').innerHTML=ops.map(n=>{const a=BR_SEL_TOOLS[n];`,
  `  return '<div class="sdb" onclick="'+a[1]+'"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'+a[0]+'</svg><span>'+n+'</span></div>'}).join('')}`,
].join(C), 'A5 brSelActsRender 配置驱动');

/* ================= ④ 长按粒度：判定函数 + 两处入口 ================= */
rep(`function brLpStart(e,pi){`, [
  `/* V1.53.4④ 长按选择粒度：选字＝命中单字（可拖手柄扩选）；选句＝既有句/词块命中 */`,
  `function brSelGranWord(t,off){if(BS_SET.brSelGran==='选句')return brWordAt(t,off);`,
  ` const a=Math.max(0,Math.min(off||0,(t||'').length-1));return[a,Math.min((t||'').length,a+1)]}`,
  `function brLpStart(e,pi){`,
].join(C), 1, 'A6 brSelGranWord');
rep(`const w=brWordAt(t,p&&p.pi!=null?p.off:0);brSelect(usePi,usePi,w[0],w[1])},520)}`,
  `const w=brSelGranWord(t,p&&p.pi!=null?p.off:0);brSelect(usePi,usePi,w[0],w[1])},520)}`,
  1, 'A7 段内长按走粒度');
rep(`const w=brWordAt(t,q&&q.pi!=null?q.off:0);brSelect(usePi,usePi,w[0],w[1])},520)}`,
  `const w=brSelGranWord(t,q&&q.pi!=null?q.off:0);brSelect(usePi,usePi,w[0],w[1])},520)}`,
  1, 'A8 空隙带长按走粒度');

/* ================= ②③ AI：二选一 → 审阅（默认折叠） → 结果 ================= */
repSlice(`function brAiOpen(){const q=brV.selTxt;`, `},460)}`, [
  `/* V1.53.4②③ AI 解读＝二选一（解释词句/深度解读）→ 发送前审阅（默认折叠·全模块共用形态）→ 结果 */`,
  `let brAiQ='',brAiBook='',brAiMode='insight';`,
  `const BR_AI_TPL={`,
  ` explain:{nm:'阅读 · 词句解释',`,
  `  sys:'你是《{book}》的随行注疏助手。对读者选中的词或句，依次给出：①释义（字词义/句意）②背景（概念出处与作者语境）③简析（一句话说明它在书中论证里的位置）。总计不超过 180 字，直接输出正文，不客套、不整句复述原文。',`,
  `  usr:'书名：{book}\\n选中：{quote}\\n请解释。',`,
  `  chunks:['【释义】锚定：判断时过度依赖最先获得的数值；本句指轮盘随机数成了估计的「锚」。','【背景】出自第 2 章抢答实验，与后文「基础率忽视」互为证据链（Kahneman & Tversky, 1974）。','【简析】先到的数字不是背景噪音，而是被大脑当作起点的证据。<br>']},`,
  ` insight:{nm:'阅读 · 摘录深度解读',`,
  `  sys:'你是读书笔记助手。只输出一个 JSON 对象，禁止输出其他文字或代码块标记。感想要落在使用者自身场景，不空泛吹捧、不引用原文。',`,
  `  usr:'为下面这条摘录写一段可选感想草稿（40~80 字），并给 1~3 个标签：\\n书名：{book}\\n摘录：{quote}\\n输出格式：{\\"insight\\": \\"感想正文\\", \\"tags\\": [\\"标签一\\", \\"标签二\\"]}',`,
  `  chunks:['【要点】这段出自「{ch}」，核心机制可压缩为一句：先理解前提（意识资源有限、联想自动扩散），再看它推出的行为预测。<br>','【背景】它与前文的抢答模型、后文的基础率忽视互为证据链，是同一主张在不同实验材料上的复现。<br>','【追问】如果用于你的工作流：哪一类决策最容易被环境牵着走？可设一个「先写数字再做判断」的对照仪式。<br>']}};`,
  `function brAiFill(t){return t.replace(/\\{book\\}/g,brAiBook).replace(/\\{quote\\}/g,brAiQ).replace(/\\{ch\\}/g,(brLeaves(brV.b)[brV.ci]||''))}`,
  `function brAiOpen(){if(!brV.sel)return;brAiQ=brV.selTxt;brAiBook=(bsBook(brV.b)||{}).n||'';`,
  ` document.getElementById('brChoiceQuote').textContent=brAiQ;brSelHideUI();openSheet('sheetBrAiChoice')}`,
  `function brAiPick(k){brAiMode=k;closeSheet('sheetBrAiChoice');const T=BR_AI_TPL[k];`,
  ` document.getElementById('brRvTask').textContent=T.nm;`,
  ` const sys=brAiFill(T.sys),usr=brAiFill(T.usr);`,
  ` document.getElementById('brRvSysBox').textContent=sys;document.getElementById('brRvUsrBox').textContent=usr;`,
  ` document.getElementById('brRvSysPeek').textContent=sys.split('\\n')[0].slice(0,24)+'…';document.getElementById('brRvUsrPeek').textContent=usr.split('\\n')[0].slice(0,24)+'…';`,
  ` document.getElementById('brRvSysBox').classList.add('hidden');document.getElementById('brRvUsrBox').classList.add('hidden');`,
  ` document.getElementById('brRvSysChev').textContent='∨';document.getElementById('brRvUsrChev').textContent='∨';`,
  ` openSheet('sheetAiReview')}`,
  `function brRvTog(k){const box=document.getElementById('brRv'+k+'Box'),chev=document.getElementById('brRv'+k+'Chev');`,
  ` const hide=box.classList.toggle('hidden');chev.textContent=hide?'∨':'∧'}`,
  `function brAiSend(){closeSheet('sheetAiReview');const T=BR_AI_TPL[brAiMode];`,
  ` document.getElementById('brAiTitle').textContent=brAiMode==='explain'?'AI 解释':'AI 深度解读';`,
  ` document.getElementById('brAiQuote').textContent=brAiQ;`,
  ` document.getElementById('brAiOut').innerHTML='<span class="text-slate-400">正在结合上下文'+(brAiMode==='explain'?'解释…':'解读…')+'</span>';`,
  ` brSelHideUI();openSheet('sheetBrAi');`,
  ` clearInterval(brAiTimer);brAI.text='';let i=0;`,
  ` brAiTimer=setInterval(()=>{if(i>=T.chunks.length){clearInterval(brAiTimer);return}brAI.text+=brAiFill(T.chunks[i]);`,
  `  document.getElementById('brAiOut').innerHTML=brAI.text+'<span class="br-pulse" style="display:inline-block"></span>';i++},460)}`,
].join(C), 'A9 AI 三段流程');

rep(`.value='🤖 AI 解读：'+brAI.text`,
  `.value=(brAiMode==='explain'?'【AI 解释】':'【AI 解读】')+brAI.text`,
  1, 'A10 存感想前缀按模式（emoji 摘除）');

rep(`><b class="text-[15px]">AI 解读</b><span class="text-[9px] text-slate-400">Opt-in · 本地 Key</span></div>`,
  `><b class="text-[15px]" id="brAiTitle">AI 解读</b><span class="text-[9px] text-slate-400">Opt-in · 本地 Key</span></div>`,
  1, 'A11 结果弹层标题挂 id');

/* ================= 新弹层 HTML（打开方式 / 二选一 / 审阅） ================= */
rep(`  <!-- AI 解读 -->`, [
  `  <!-- V1.53.4⑥ 系统「打开方式」接收 EPUB · 未导入=导入确认 / 已导入=提醒+定位（?br57=open|dup） -->`,
  `  <div id="sheetBrOpen" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetBrOpen')">`,
  `    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8" id="brOpenBody"></div>`,
  `  </div>`,
  ``,
  `  <!-- V1.53.4② AI 解读二选一（?br57=choice） -->`,
  `  <div id="sheetBrAiChoice" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetBrAiChoice')">`,
  `    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">`,
  `      <div class="flex items-center justify-between"><b class="text-[15px]">AI 解读</b><span class="text-[9px] text-slate-400">Opt-in · 本地 Key</span></div>`,
  `      <div class="mt-2 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] leading-5 line-clamp-2" id="brChoiceQuote">—</div>`,
  `      <div class="mt-3 space-y-2">`,
  `        <button class="w-full flex items-center gap-2.5 px-3 py-2.5 rounded-xl card !py-2.5 text-left" onclick="brAiPick('explain')">`,
  `          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" class="shrink-0 text-brand-500"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>`,
  `          <span class="flex-1 min-w-0"><b class="text-[13px]">解释词句</b><span class="block text-[10px] text-slate-400 mt-0.5">释义 · 背景 · 简析</span></span><span class="text-slate-300">›</span></button>`,
  `        <button class="w-full flex items-center gap-2.5 px-3 py-2.5 rounded-xl card !py-2.5 text-left" onclick="brAiPick('insight')">`,
  `          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" class="shrink-0 text-brand-500"><path d="M12 3v3m0 12v3M3 12h3m12 0h3M6 6l2 2m8 8 2 2m0-12-2 2M8 16l-2 2"/><circle cx="12" cy="12" r="3.2"/></svg>`,
  `          <span class="flex-1 min-w-0"><b class="text-[13px]">深度解读</b><span class="block text-[10px] text-slate-400 mt-0.5">论证链 · 感想与标签</span></span><span class="text-slate-300">›</span></button>`,
  `      </div>`,
  `    </div>`,
  `  </div>`,
  ``,
  `  <!-- V1.53.4③ 发送前审阅（全模块共用 · System/User 默认折叠）（?br57=review） -->`,
  `  <div id="sheetAiReview" class="sheet hidden fixed md:absolute inset-0 z-[80] bg-black/40 items-end" onclick="if(event.target===this)closeSheet('sheetAiReview')">`,
  `    <div class="sheet-panel w-full bg-white dark:bg-slate-900 rounded-t-3xl p-5 pb-8">`,
  `      <div class="flex items-center justify-between"><b class="text-[15px]">发送前审阅</b><span class="text-[9px] text-slate-400" id="brRvTask">—</span></div>`,
  `      <div class="mt-3 rounded-xl border border-slate-200 dark:border-slate-700">`,
  `        <button class="w-full flex items-center gap-2 px-3 py-2.5 text-left" onclick="brRvTog('Sys')">`,
  `          <b class="text-[12px] shrink-0">System · 发送设定</b><span class="text-[10px] text-slate-400 truncate flex-1" id="brRvSysPeek">…</span><span class="text-[11px] text-slate-400" id="brRvSysChev">∨</span></button>`,
  `        <div class="hidden px-3 pb-3 text-[11px] leading-5 text-slate-500 dark:text-slate-400 whitespace-pre-wrap" id="brRvSysBox"></div>`,
  `      </div>`,
  `      <div class="mt-2 rounded-xl border border-slate-200 dark:border-slate-700">`,
  `        <button class="w-full flex items-center gap-2 px-3 py-2.5 text-left" onclick="brRvTog('Usr')">`,
  `          <b class="text-[12px] shrink-0">User · 本次内容</b><span class="text-[10px] text-slate-400 truncate flex-1" id="brRvUsrPeek">…</span><span class="text-[11px] text-slate-400" id="brRvUsrChev">∨</span></button>`,
  `        <div class="hidden px-3 pb-3 text-[11px] leading-5 text-slate-500 dark:text-slate-400 whitespace-pre-wrap" id="brRvUsrBox"></div>`,
  `      </div>`,
  `      <div class="mt-3 flex gap-2"><button class="flex-1 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet('sheetAiReview')">取消</button>`,
  `        <button class="flex-1 py-2.5 rounded-xl grad text-white text-xs font-bold" onclick="brAiSend()">发送</button></div>`,
  `      <div class="mt-2 text-[9px] text-slate-400 text-center">只发送以上两部分 · 模板可在「提示词管理」逐段修改</div>`,
  `    </div>`,
  `  </div>`,
  ``,
  `  <!-- AI 解读 -->`,
].join(C), 1, 'A12 三个新弹层 HTML');

/* ================= ⑥ 打开方式逻辑 + 书架定位高亮 ================= */
rep(`html.dark #brSelBar,html.dark #brColorPop{color:#cbd5e1}`,
  `html.dark #brSelBar,html.dark #brColorPop{color:#cbd5e1}` + C +
  `    /* V1.53.4⑥ 书架定位闪烁（打开方式已导入 → 跳书架高亮） */` + C +
  `    #shBody .br-flash-loc{box-shadow:0 0 0 3px rgba(99,102,241,.6);border-radius:14px}`,
  1, 'A13 定位高亮 CSS');

rep(`/* ---- 书架接入（包装器 · 不改既有函数体） ---- */`, [
  `/* ---- V1.53.4⑥ 系统「打开方式」接收 EPUB（?br57=open|dup 演示两态） ---- */`,
  `const brOpenSt={file:null,dir:'download',dup:null,meta:null};`,
  `const BR_OPEN_DEMO={'new':'我们仨.epub','dup':'思考快与慢.epub'};`,
  `function brOpenFind(fn){for(const d of ['download','docs']){const f=(BR_FILES[d]||[]).find(x=>x.n===fn);if(f)return{f:f,dir:d}}return null}`,
  `function brOpenEpub(fn){const hit=brOpenFind(fn)||{f:{n:fn,sz:'—',meta:null},dir:'download'};const f=hit.f;`,
  ` const m=f.meta||{t:(f.merge||f.n.replace(/\\.epub$/,'')),a:'未知作者',press:'',pub:'',fmt:'EPUB3',pages:240,intro:''};`,
  ` const dup=BS_BOOKS.find(b=>brNorm(b.n)===brNorm(m.t)||b.n===f.merge);`,
  ` brOpenSt.file=f;brOpenSt.dir=hit.dir;brOpenSt.dup=dup?dup.id:null;brOpenSt.meta=m;`,
  ` const box=document.getElementById('brOpenBody');`,
  ` const btns=(a,b)=>'<div class="mt-3 flex gap-2"><button class="flex-1 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="'+a+'">取消</button><button class="flex-1 py-2.5 rounded-xl grad text-white text-xs font-bold" onclick="'+b+'">'+(dup?'前往书架定位':'加入书架 · 预载')+'</button></div>';`,
  ` if(dup){box.innerHTML='<div class="flex items-center justify-between"><b class="text-[15px]">这本书已在书架</b><span class="text-[9px] text-slate-400">打开方式</span></div>'`,
  `  +'<div class="mt-2 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] leading-5"><b>'+brEsc(dup.n)+'</b>（'+brEsc(dup.a)+'）· '+brEsc(dup.st)+(dup.st==='在读'?' '+dup.p+'%':'')+'<div class="text-slate-400 mt-0.5">来自文件：'+brEsc(f.n)+'</div></div>'`,
  `  +btns("closeSheet('sheetBrOpen')","shLocate('"+dup.id+"')")`,
  `  +'<div class="mt-2 text-[9px] text-slate-400 text-center">同一本书不再重复入库 · 书摘与进度沿用书架记录</div>'}`,
  ` else{box.innerHTML='<div class="flex items-center justify-between"><b class="text-[15px]">导入这本书？</b><span class="text-[9px] text-slate-400">打开方式</span></div>'`,
  `  +'<div class="mt-2 rounded-xl bg-slate-50 dark:bg-slate-800/60 p-2.5 text-[11px] leading-5"><b>'+brEsc(m.t)+'</b>（'+brEsc(m.a)+'）· '+brEsc(f.sz)+'<div class="text-slate-400 mt-0.5">'+brEsc(f.n)+' · 元数据从 EPUB 自动读取</div></div>'`,
  `  +btns("closeSheet('sheetBrOpen')","brOpenConfirm()")`,
  `  +'<div class="mt-2 text-[9px] text-slate-400 text-center">导入后可在核对页修改书名与作者 · 源文件保留原位</div>'}`,
  ` openSheet('sheetBrOpen')}`,
  `function brOpenConfirm(){closeSheet('sheetBrOpen');brImp.file=brOpenSt.file;brImp.dir=brOpenSt.dir;brImp.mergeTo=null;brImp.lostId=null;`,
  ` navTo('p-localImport');brImpGo(3);brImpParse()}`,
  `function shLocate(id){closeSheet('sheetBrOpen');const b=bsBook(id);if(!b)return;`,
  ` try{shSt=b.st}catch(e){}`,
  ` navTo('p-bookshelf');try{renderShelf()}catch(e){}`,
  ` const el=[...document.querySelectorAll('#shBody [onclick]')].find(x=>(x.getAttribute('onclick')||'').indexOf("shOpen('"+id+"')")>=0);`,
  ` if(!el){toast('未在当前视图找到该书');return}`,
  ` el.scrollIntoView({block:'center'});el.classList.add('br-flash-loc');`,
  ` setTimeout(()=>el.classList.remove('br-flash-loc'),1800);toast('已在书架定位《'+b.n+'》')}`,
  ``,
  `/* ---- 书架接入（包装器 · 不改既有函数体） ---- */`,
].join(C), 1, 'A14 打开方式 JS');

/* ================= 深链 ?br57= ================= */
rep(`console.warn('r146',e)}})();`, [`console.warn('r146',e)}})();`,
  `/* V1.53.4 批深链：?br57=gran|sent|bar|choice|review|set|open|dup`,
  `   gran/sent＝长按粒度两态 · bar＝工具条按配置渲染 · choice/review＝AI 二选一与审阅折叠 · set＝新设置行 · open/dup＝打开方式两态 */`,
  `(function br57Boot(){try{`,
  ` const m=(location.search.match(/br57=([a-z]+)/)||[])[1];if(!m)return;`,
  ` if(m==='open'){brOpenEpub(BR_OPEN_DEMO['new']);return}`,
  ` if(m==='dup'){brOpenEpub(BR_OPEN_DEMO.dup);return}`,
  ` if(m==='set'){navTo('p-readset');rsPickTab(RS_SEC.length-1);renderReadSet();return}`,
  ` brOpen('b1');brShowChrome();`,
  ` const el=document.querySelector('#brBody [data-pi="2"]')||document.querySelector('#brBody [data-pi]');`,
  ` if(!el)return;const pi=+el.dataset.pi;const arr=brChText(brV.b,brLeaves(brV.b)[brV.ci]);const t=(arr[pi]&&arr[pi].t)||'';`,
  ` if(m==='gran'){BS_SET.brSelGran='选字';const w=brSelGranWord(t,4);brSelect(pi,pi,w[0],w[1])}`,
  ` else if(m==='sent'){BS_SET.brSelGran='选句';const w=brSelGranWord(t,4);brSelect(pi,pi,w[0],w[1])}`,
  ` else if(m==='bar'){BS_SET.brSelOps=['AI 解读','复制','划线','分享','书摘'];const w=brWordAt(t,4);brSelect(pi,pi,w[0],w[1])}`,
  ` else{const w=brWordAt(t,4);brSelect(pi,pi,w[0],w[1])}`,
  ` brBindHandles();brHandlePlace();`,
  ` if(m==='choice')brAiOpen();`,
  ` if(m==='review'){brAiOpen();brAiPick('explain')}`,
  `}catch(e){console.warn('br57',e)}})();`,
].join(C), 1, 'A15 br57 深链');

/* ================= 写回前总体校验 ================= */
const need = STOP ? [] : ['brSelGranWord', 'sheetBrAiChoice', 'sheetAiReview', 'brOpenEpub', 'shLocate', 'BR_SEL_TOOLS', 'bpMv', "br57Boot"];
for (const k of need) if (!H.includes(k)) { console.error('缺失注入标记：' + k + ' —— 中止'); process.exit(1); }
const d = H.length - SIZE0;
if (!STOP && (d < 4000 || d > 30000)) { console.error(`体积增量异常 ${d} —— 中止`); process.exit(1); }
fs.writeFileSync(P, H, 'utf8');
console.log(`写回完成：替换 ${nRep} 处，体积 ${SIZE0} → ${H.length}（+${d}）`);
