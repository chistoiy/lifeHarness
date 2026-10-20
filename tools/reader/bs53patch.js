/* V1.53 轮3 · 阅读器底栏五图标+三面板+长按选区 原型补丁（带命中断言与体积护栏） */
const fs = require('fs');
const F = 'prototype/index-bookshelf.html';
let src = fs.readFileSync(F, 'utf8');
const origLen = src.length;
const frag = (p) => fs.readFileSync('tools/reader/' + p, 'utf8');
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

/* 1 · CSS 追加 */
rep('css', '    #brSelBar .sdb:active{background:rgba(148,163,184,.18)}\n',
  '    #brSelBar .sdb:active{background:rgba(148,163,184,.18)}\n' + frag('bs53_frag_css.txt'));

/* 2 · 中心热区：加 id 与长按指针 */
rep('zone', '        <div class="br-zone absolute inset-x-[16%] top-[15%] bottom-[15%] z-[9]" onclick="brTapCenter()"></div>',
  '        <div id="brZoneC" class="br-zone absolute inset-x-[16%] top-[15%] bottom-[15%] z-[9]" onpointerdown="brZoneLpStart(event)" onpointerup="brLpEnd()" onpointerleave="brLpCancel()" onpointercancel="brLpCancel()" onclick="brTapCenter()"></div>');

/* 3 · 底栏整块替换（brBottom → brSelBar 前） */
repRange('bottom', '        <div id="brBottom" class="br-chrome hidden absolute bottom-0 inset-x-0 z-[70] px-4 pt-2 pb-3 whitespace-nowrap">',
  '        <div id="brSelBar"', frag('bs53_frag_bottom.txt') + '        ');

/* 4 · 段落改长按 */
rep('para', '  return `<span onclick="event.stopPropagation();brSelect(${pi},${pi})">${inner}</span>`}',
  '  return `<span onpointerdown="brLpStart(event,${pi})" onpointerup="brLpEnd()" onpointerleave="brLpCancel()" onpointercancel="brLpCancel()" onclick="event.stopPropagation();brParaTap(${pi})">${inner}</span>`}');

/* 5 · brChromeLabels：去掉 brThemeBtn 引用、补统计与滑杆回填 */
rep('labels',
  "  const sl=document.getElementById('brProg');sl.max=tot-1;sl.value=gp;\n" +
  "  document.getElementById('brThemeBtn').textContent=BR_THEMES[brSt(bid).theme]?BR_THEMES[brSt(bid).theme].n:'自定义';\n" +
  "  document.getElementById('brModeBtn').textContent=brV.mode==='page'?'滚动':'翻页';\n" +
  "  document.getElementById('brSessChip').textContent=brMS(brSessSecs())}",
  "  const sl=document.getElementById('brProg');sl.max=tot-1;sl.value=gp;\n" +
  "  const mb=document.getElementById('brModeBtn');if(mb)mb.textContent='翻页方式 · '+(brV.mode==='page'?'翻页':'滚动')+' ›';\n" +
  "  const fss=document.getElementById('brFsSl');if(fss)fss.value=brSt(bid).fs;\n" +
  "  const fsn=document.getElementById('brFsNum');if(fsn)fsn.textContent=brSt(bid).fs;\n" +
  "  document.getElementById('brSessChip').textContent=brMS(brSessSecs());\n" +
  "  const pct=brLivePct();const sp=document.getElementById('brStPct');if(sp)sp.textContent=pct;\n" +
  "  const sm=document.getElementById('brStMin');if(sm)sm.textContent=Math.max(1,Math.round(brSessSecs()/60));\n" +
  "  let notes=0;try{notes=bsQ(bid).length}catch(e){}const sn=document.getElementById('brStNote');if(sn)sn.textContent=notes;\n" +
  "  const se=document.getElementById('brStEta');if(se){if(pct>=100)se.textContent='已读完';else{const rem=Math.max(0,tot-gp-1);const hrs=Math.max(1,Math.round(rem*45/3600));se.textContent='约'+hrs+'小时后读完'}}\n" +
  "  const ab=document.getElementById('brBtnAuto');if(ab)ab.textContent=brSt(bid).auto?'暂停自动翻页':'开启自动翻页'}");

/* 6 · brTapCenter：长按后抑制一次点按；收 chrome 同时收面板 */
rep('tap',
  "function brTapCenter(){if(brV.sel){brSelHide();return}brV.chrome=!brV.chrome;\n" +
  "  ['brTop','brBottom'].forEach(id=>{const el=document.getElementById(id);el.classList.toggle('hidden',!brV.chrome);el.classList.toggle('flex',brV.chrome)});\n" +
  "  if(brV.chrome)document.getElementById('brSessChip').textContent=brMS(brSessSecs())}",
  "function brTapCenter(){if(_brLpFired){_brLpFired=false;return}if(brV.sel){brSelHide();return}brV.chrome=!brV.chrome;\n" +
  "  ['brTop','brBottom'].forEach(id=>{const el=document.getElementById(id);el.classList.toggle('hidden',!brV.chrome);el.classList.toggle('flex',brV.chrome)});\n" +
  "  if(!brV.chrome)brHidePanels();\n" +
  "  if(brV.chrome)document.getElementById('brSessChip').textContent=brMS(brSessSecs())}");

/* 7 · brSeek：拖离原进度显「返回原进度」胶囊 */
rep('seek',
  "function brSeek(v){const p=brGPosTo(brV.b,+v);brV.ci=p.ci;brV.pg=p.pg;brSavePos();if(curPage!=='p-readerPage')navTo('p-readerPage');else brRenderPage();\n" +
  "  brV.chrome=true;['brTop','brBottom'].forEach(id=>{document.getElementById(id).classList.remove('hidden');document.getElementById(id).classList.add('flex')})}",
  "function brSeek(v){const p=brGPosTo(brV.b,+v);brV.ci=p.ci;brV.pg=p.pg;brSavePos();if(curPage!=='p-readerPage')navTo('p-readerPage');else brRenderPage();\n" +
  "  const h=brV.home,bp=document.getElementById('brBackPos');if(h&&bp)bp.classList.toggle('hidden',h.ci===p.ci&&h.pg===p.pg);\n" +
  "  brV.chrome=true;['brTop','brBottom'].forEach(id=>{document.getElementById(id).classList.remove('hidden');document.getElementById(id).classList.add('flex')})}");

/* 8 · brOpen：记录原进度、收面板、复位亮度遮罩与缩进 */
rep('open',
  "  const p=brPos[id]||{ci:0,pg:0};brV.ci=Math.min(p.ci,brLeaves(id).length-1);brV.pg=p.pg||0;brV.mode=brSt(id).mode||'page';brV.t0=Date.now();brV.prevSess=0;",
  "  const p=brPos[id]||{ci:0,pg:0};brV.ci=Math.min(p.ci,brLeaves(id).length-1);brV.pg=p.pg||0;brV.mode=brSt(id).mode||'page';brV.t0=Date.now();brV.prevSess=0;\n" +
  "  brV.home={ci:brV.ci,pg:brV.pg};brHidePanels();const _bp=document.getElementById('brBackPos');if(_bp)_bp.classList.add('hidden');\n" +
  "  brBrightSet(brLumMaskV);document.getElementById('brStage').classList.toggle('no-indent',brV.indent===false);");

/* 9 · 新 JS 块（插在「打开/离开」注释前） */
rep('js', '/* ---- 打开 / 离开（计时与进度结算走既有基建） ---- */',
  frag('bs53_frag_js.txt') + '\n/* ---- 打开 / 离开（计时与进度结算走既有基建） ---- */');

/* 10 · 摘抄工具条动作序（参考图4：复制/划线/写想法/书摘/查询/听当前 + AI/分享） */
rep('acts',
  "function brSelActsRender(){const acts=[['复制','<rect x=\"8\" y=\"8\" width=\"12\" height=\"12\" rx=\"2\"/><path d=\"M16 5.5A1.5 1.5 0 0 0 14.5 4H6a2 2 0 0 0-2 2v8.5A1.5 1.5 0 0 0 5.5 16\"/>','brCopy()'],\n" +
  "  ['划线','<path d=\"M15 4 4 15v5h5L20 9z\"/><path d=\"M13 6l5 5\"/>','brColorShow()'],\n" +
  "  ['书摘','<path d=\"M5 4h11l3 3v13H5z\"/><path d=\"M8 9h7M8 13h7\"/>','brToQuote()'],\n" +
  "  ['感想','<path d=\"M4 20l1-4L16 5l3 3L8 19z\"/>','brToThink()'],\n" +
  "  ['AI 解读','<path d=\"M12 3v3m0 12v3M3 12h3m12 0h3M6 6l2 2m8 8 2 2m0-12-2 2M8 16l-2 2\"/><circle cx=\"12\" cy=\"12\" r=\"3.2\"/>','brAiOpen()'],\n" +
  "  ['词典','<rect x=\"4\" y=\"3\" width=\"16\" height=\"18\" rx=\"2\"/><path d=\"M8 8h8M8 12h8M8 16h4\"/>','brDictOpen()'],\n" +
  "  ['分享','<circle cx=\"6\" cy=\"12\" r=\"2.5\"/><circle cx=\"18\" cy=\"6\" r=\"2.5\"/><circle cx=\"18\" cy=\"18\" r=\"2.5\"/><path d=\"m8.3 10.8 7.4-3.6M8.3 13.2l7.4 3.6\"/>','brShare()']];",
  "function brSelActsRender(){const acts=[['复制','<rect x=\"8\" y=\"8\" width=\"12\" height=\"12\" rx=\"2\"/><path d=\"M16 5.5A1.5 1.5 0 0 0 14.5 4H6a2 2 0 0 0-2 2v8.5A1.5 1.5 0 0 0 5.5 16\"/>','brCopy()'],\n" +
  "  ['划线','<path d=\"M15 4 4 15v5h5L20 9z\"/><path d=\"M13 6l5 5\"/>','brColorShow()'],\n" +
  "  ['写想法','<path d=\"M4 20l1-4L16 5l3 3L8 19z\"/>','brToThink()'],\n" +
  "  ['书摘','<path d=\"M5 4h11l3 3v13H5z\"/><path d=\"M8 9h7M8 13h7\"/>','brToQuote()'],\n" +
  "  ['查询','<circle cx=\"11\" cy=\"11\" r=\"7\"/><path d=\"m20 20-3.2-3.2\"/>','brDictOpen()'],\n" +
  "  ['听当前','<path d=\"M4 10v4h4l5 4V6L8 10H4z\"/><path d=\"M17 8a5 5 0 0 1 0 8\"/>','brTtsToggle()'],\n" +
  "  ['AI 解读','<path d=\"M12 3v3m0 12v3M3 12h3m12 0h3M6 6l2 2m8 8 2 2m0-12-2 2M8 16l-2 2\"/><circle cx=\"12\" cy=\"12\" r=\"3.2\"/>','brAiOpen()'],\n" +
  "  ['分享','<circle cx=\"6\" cy=\"12\" r=\"2.5\"/><circle cx=\"18\" cy=\"6\" r=\"2.5\"/><circle cx=\"18\" cy=\"18\" r=\"2.5\"/><path d=\"m8.3 10.8 7.4-3.6M8.3 13.2l7.4 3.6\"/>','brShare()']];");

/* 11 · 深链 ?br53=prog|bright|font|sel（截图与校验用） */
rep('deep', '/* ================= 阅读器（书架专版）结束 ================= */',
  "/* V1.53 轮3 深链：?br53=prog|bright|font|sel → 阅读主屏对应面板/选区态 */\n" +
  "(function br53Boot(){try{\n" +
  "  const m=(location.search.match(/br53=(\\w+)/)||[])[1];if(!m)return;\n" +
  "  brOpen('b1');brShowChrome();\n" +
  "  if(m==='prog'||m==='bright'||m==='font')brTogglePanel(m);\n" +
  "  else if(m==='sel'){const el=document.querySelector('#brBody [data-pi]');if(el)brSelect(+el.dataset.pi,+el.dataset.pi);\n" +
  "    const bp=document.getElementById('brBackPos');if(bp)bp.classList.remove('hidden');}\n" +
  "}catch(e){console.warn('br53',e)}})();\n" +
  '/* ================= 阅读器（书架专版）结束 ================= */');

/* 体积护栏：只允许增长（新增面板+JS），且增幅 < 24KB */
const delta = src.length - origLen;
if (delta < 3000 || delta > 24000) { console.error('体积护栏拦截：delta=' + delta); process.exit(1); }
fs.writeFileSync(F, src, 'utf8');
console.log('OK 命中 ' + hits + '/11 · delta=' + delta + 'B · size=' + src.length);
