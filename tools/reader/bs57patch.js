/* V1.53.2 轮5.2 · 原型补丁（命中断言 + 体积护栏）
   ① 正文去胶囊：删 brBackJump / brBackPos，返回入口收进进度弹层与目录抽屉
   ② 计时自动结算：进书记起始快照（章节/页/百分比/CFI），退出写止点并入会话
   ③ 新设置「短于 N 秒不计入」（默认 30 秒），未达门槛不入账
   ④ 阅读明细行展示 起止章节 · 页 · 百分比
   用：node tools/reader/bs57patch.js */
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

/* ═══  去胶囊 ═══ */
rep('pill-dom',
  '        <button id="brBackJump" class="hidden absolute bottom-40 left-1/2 -translate-x-1/2 z-[73] rounded-full px-3.5 py-2 text-[10px] font-bold" onclick="brBackJumpGo()">‹ 返回上一位置</button>\n' +
  '        <button id="brBackPos" class="hidden absolute bottom-24 left-1/2 -translate-x-1/2 z-[71] br-chrome rounded-full px-3.5 py-2 text-[10px] font-bold" onclick="brGoHome()">‹ 返回原进度</button>\n',
  '        <!-- 轮5.2：正文不再悬浮任何「返回」胶囊，入口见进度弹层与目录抽屉 -->\n');

/* 目录抽屉顶部：跳章后出现「回到刚才在读」横条 */
rep('dr-bar',
  '              <div id="brDrSearchBox" class="hidden px-3.5 pb-2 shrink-0">',
  '              <button id="brDrBack" class="hidden shrink-0 mx-3.5 mb-2 rounded-xl px-3 py-2 text-[11px] font-bold text-left flex items-center gap-1.5" style="background:rgba(99,102,241,.10);color:var(--accent)" onclick="brBackJumpGo()">‹ 回到刚才在读 · <span id="brDrBackLbl" class="font-black truncate max-w-[150px]">—</span></button>\n' +
  '              <div id="brDrSearchBox" class="hidden px-3.5 pb-2 shrink-0">');

/* 进度弹层：加「回到进书位置」按钮 */
rep('prog-home',
  '      <div class="mt-2"><button class="w-full py-2.5 rounded-2xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet(\'sheetBrProg\')">关闭</button></div>',
  '      <div class="mt-2 flex gap-2">\n' +
  '        <button id="brProgHome" class="hidden flex-1 py-2.5 rounded-2xl border text-xs font-bold" style="border-color:rgba(99,102,241,.4);color:var(--accent)" onclick="brGoHome()">回到进书位置</button>\n' +
  '        <button class="flex-1 py-2.5 rounded-2xl border border-slate-200 dark:border-slate-700 text-xs font-bold" onclick="closeSheet(\'sheetBrProg\')">关闭</button>\n' +
  '      </div>');

/* 跳章返回三函数改写到抽屉横条 */
rep('jump-fns',
  'function brShowBackJump(){const b=document.getElementById(\'brBackJump\');if(!b||!_brJumpFrom)return;\n' +
  '  b.classList.remove(\'hidden\');clearTimeout(_brJumpT);_brJumpT=setTimeout(brHideBackJump,3000)}\n' +
  'function brHideBackJump(){clearTimeout(_brJumpT);const b=document.getElementById(\'brBackJump\');if(b)b.classList.add(\'hidden\')}\n' +
  'function brBackJumpGo(){if(!_brJumpFrom)return;const f=_brJumpFrom;_brJumpFrom=null;brHideBackJump();\n' +
  '  brV.ci=f.ci;brV.pg=f.pg;brSavePos();brRenderPage();brFlash(\'已回到上一位置\')}',
  '/* 轮5.2：不再悬浮正文，改为目录抽屉顶部横条（用户主动开抽屉才看得到） */\n' +
  'function brShowBackJump(){const b=document.getElementById(\'brDrBack\');if(!b)return;\n' +
  '  if(!_brJumpFrom){b.classList.add(\'hidden\');return}\n' +
  '  const l=document.getElementById(\'brDrBackLbl\');if(l)l.textContent=brLeaves(brV.b)[_brJumpFrom.ci]||\'—\';\n' +
  '  b.classList.remove(\'hidden\');b.classList.add(\'flex\')}\n' +
  'function brHideBackJump(){const b=document.getElementById(\'brDrBack\');if(b){b.classList.add(\'hidden\');b.classList.remove(\'flex\')}}\n' +
  'function brBackJumpGo(){if(!_brJumpFrom)return;const f=_brJumpFrom;_brJumpFrom=null;brTocClose();brHideBackJump();\n' +
  '  brV.ci=f.ci;brV.pg=f.pg;brSavePos();brRenderPage();brFlash(\'已回到上一位置\')}');

/* 中区点按不再管胶囊 */
rep('tapcenter',
  '  const bj=document.getElementById(\'brBackJump\');if(bj&&!bj.classList.contains(\'hidden\')){brHideBackJump();return}\n',
  '');

/* 进度弹层里的「回到进书位置」按需显示（统一一个同步函数，别在各调用点重复写） */
rep('labels-home',
  "  const h=brV.home,bp=document.getElementById('brBackPos');if(h&&bp)bp.classList.toggle('hidden',h.ci===p.ci&&h.pg===p.pg);",
  '  brProgHomeSync();');
rep('home-fn',
  'function brSeek(v){',
  'function brProgHomeSync(){const h=brV.home,ph=document.getElementById(\'brProgHome\');if(!ph||!h)return;\n' +
  '  const away=h.ci!==brV.ci||h.pg!==brV.pg;\n' +
  '  ph.classList.toggle(\'hidden\',!away);\n' +
  '  if(away)ph.textContent=\'回到进书位置 · \'+(brLeaves(brV.b)[h.ci]||\'\')+\' P\'+(brGPos(brV.b,h.ci,h.pg)+1)}\n' +
  'function brSeek(v){');
rep('prog-sheet',
  "function brProgSheet(){brChromeLabels();",
  "function brProgSheet(){brChromeLabels();brProgHomeSync();");

rep('open-clean',
  "  brV.home={ci:brV.ci,pg:brV.pg};brHidePanels();const _bp=document.getElementById('brBackPos');if(_bp)_bp.classList.add('hidden');",
  '  brV.home={ci:brV.ci,pg:brV.pg};brHidePanels();brHideBackJump();');

/* ═══ ③ 计时自动结算 + 阈值 ═══ */
rep('set-default',
  'dbCookie:\'\',dbCookieStale:false};',
  'dbCookie:\'\',dbCookieStale:false,brMinSecs:30};');

rep('set-row',
  "['brBright','阅读时屏幕常亮','bool','进入阅读器自动生效 · 退出恢复系统策略']]]];",
  "['brBright','阅读时屏幕常亮','bool','进入阅读器自动生效 · 退出恢复系统策略'],\n" +
  "   ['brMinSecs','短于该时长的阅读不计入','chips',[5,10,15,30,60,120,300],'秒 · 默认 30 · 退出阅读器时结算，未达门槛不记时长也不记会话']]]];");

/* 进书：记起始快照 */
rep('sess-from',
  '  brV.home={ci:brV.ci,pg:brV.pg};brHidePanels();brHideBackJump();',
  '  brV.home={ci:brV.ci,pg:brV.pg};brHidePanels();brHideBackJump();\n' +
  '  brV.sessT0=Date.now();brV.sessFrom=brLocSnap();');

/* 结算函数 + 重写 brLeave 入账段 */
rep('leave',
  'function brLeave(){if(curPage!==\'p-readerPage\')return;\n' +
  '  brAutoStop();if(brTtsTimer)brTtsOff(true);brV.t0=0;\n' +
  '  if(!brV.ownT)return;\n' +
  '  const secs=(function(){const t=document.getElementById(\'timerSec\');return t?parseInt(t.textContent)*60+(t.textContent.split(\':\')[1]|0):0})();\n' +
  '  const b=bsBook(brV.b);const pct=brStPct(brV.b);if(b){b.p=Math.max(b.p||0,pct);b.rp=Math.max(b.rp||0,Math.round(pct/100*(b.pg||0)))}\n' +
  '  const mins=Math.max(1,Math.round(secs/60));\n' +
  '  if(b){b.min=(b.min||0)+mins;b.times=(b.times||0)+1;\n' +
  '    if(BS_SESS_CACHE[b.id]&&BS_SESS_CACHE[b.id].length)BS_SESS_CACHE[b.id].unshift({dt:shFmtDate(),from:b.rp||0,to:b.rp,min:mins});\n' +
  '    if(b.st===\'想读\'){b.st=\'在读\';if(!b.start)b.start=shFmtDate()}}\n' +
  '  stopTimerUI();brV.ownT=0;brPersist();renderShelf();try{renderBookDetail()}catch(e){}try{renderRecHub()}catch(e){}\n' +
  '  toast(\'本次约 \'+mins+\' 分钟 · 已计入《\'+(b?b.n:\'\')+\'》时长与进度（联动 L4）\')}',

  '/* 当前位置快照：章节 / 全书页 / 百分比 / CFI（会话起止都记这一份，无需手动填） */\n' +
  'function brLocSnap(){const bid=brV.b;return{pg:brGPos(bid,brV.ci,brV.pg)+1,ch:brLeaves(bid)[brV.ci]||\'\',' +
  'pct:brStPct(bid),cfi:brCfi(bid,brV.ci,brV.pg)}}\n' +
  'function brMinGate(){const v=+(BS_SET.brMinSecs==null?30:BS_SET.brMinSecs);return isNaN(v)?30:v}\n' +
  'function brLeave(){if(curPage!==\'p-readerPage\')return;\n' +
  '  brAutoStop();if(brTtsTimer)brTtsOff(true);\n' +
  '  const t0=brV.sessT0||brV.t0;brV.t0=0;brV.sessT0=0;\n' +
  '  if(!brV.ownT)return;\n' +
  '  const secs=t0?Math.max(0,Math.round((Date.now()-t0)/1000)):0;\n' +
  '  const gate=brMinGate();const b=bsBook(brV.b);const pct=brStPct(brV.b);\n' +
  '  if(b){b.p=Math.max(b.p||0,pct);b.rp=Math.max(b.rp||0,Math.round(pct/100*(b.pg||0)))}\n' +
  '  /* 未达门槛：时长与会话都不入账（明细里不留痕），只更新进度 */\n' +
  '  if(secs<gate){stopTimerUI();brV.ownT=0;brPersist();renderShelf();\n' +
  '    try{renderBookDetail()}catch(e){}\n' +
  '    toast(\'本次 \'+secs+\' 秒 · 短于 \'+gate+\' 秒不计入计时\');return}\n' +
  '  const mins=Math.max(1,Math.round(secs/60));const a=brV.sessFrom||brLocSnap(),z=brLocSnap();\n' +
  '  if(b){b.min=(b.min||0)+mins;b.times=(b.times||0)+1;\n' +
  '    bsSessList(b).unshift({dt:shFmtDate(),min:mins,from:a.pg,to:z.pg,ch0:a.ch,ch1:z.ch,p0:a.pct,p1:z.pct,loc0:a.cfi,loc1:z.cfi});\n' +
  '    if(b.st===\'想读\'){b.st=\'在读\';if(!b.start)b.start=shFmtDate()}}\n' +
  '  stopTimerUI();brV.ownT=0;brPersist();renderShelf();try{renderBookDetail()}catch(e){}try{renderRecHub()}catch(e){}\n' +
  '  toast(\'本次 \'+mins+\' 分钟 · 自动记 \'+(z.ch!==a.ch?a.ch+\'→\'+z.ch:z.ch)+\' P\'+a.pg+\'→P\'+z.pg+\' · \'+a.pct+\'%→\'+z.pct+\'%\')}');

/* ═══  明细行展示起止位置 ═══ */
rep('row',
  '${s.min}<span class="text-[9px] font-bold opacity-85">分钟</span></div></div>',
  '${s.min}<span class="text-[9px] font-bold opacity-85">分钟</span></div>' +
  '<div class="mt-1 text-[9.5px] text-slate-400 truncate">${s.ch1||s.ch0||\'—\'} · P${s.from||\'—\'}→P${s.to||\'—\'}${s.p0!=null?\' · \'+s.p0+\'%→\'+(s.p1!=null?s.p1:s.p0)+\'%\':\'\'}</div></div>');

/* 开抽屉时同步「回到刚才在读」横条的可见性 */
rep('toc-open',
  "function brTocOpen(tab){BR_DR.tab=tab||'toc';BR_DR.rail=false;BR_DR.bot=false;",
  "function brTocOpen(tab){BR_DR.tab=tab||'toc';BR_DR.rail=false;BR_DR.bot=false;brShowBackJump();");

/* brGoHome 旧实现引用已删除的 brBackPos → 点「回到进书位置」必抛 */
rep('gohome',
  "function brGoHome(){const h=brV.home;if(!h)return;brV.ci=h.ci;brV.pg=h.pg;brSavePos();brRenderPage();document.getElementById('brBackPos').classList.add('hidden');brFlash('已返回原进度')}",
  "function brGoHome(){const h=brV.home;if(!h)return;brV.ci=h.ci;brV.pg=h.pg;brSavePos();\n" +
  "  closeSheet('sheetBrProg');brRenderPage();brFlash('已回到进书位置')}");

fs.writeFileSync(F, src);
console.log('hits=' + hits + ' size ' + origLen + ' → ' + src.length);
if (src.length < origLen * 0.9) { console.error('体积异常缩小，疑似覆盖'); process.exit(1); }
