/* V1.53.2 轮5.1 · 用户第二轮反馈原型补丁（命中断言 + 体积护栏）
   ① 首尾手柄精确跟随选区（文本节点定位 · 1 字宽 range）
   ② 底栏 5 图标 → 3 图标（目录 / 进度 / 外观），主题·亮度·字号并入「外观」
   ③ 进度与外观改正常底部弹层（不再内嵌在底栏左侧挤压正文）
   ④ 外观弹层补：亮度、背景色板、自绘取色（不用系统 color 控件）、图片背景 + 淡化
   用：node tools/reader/bs56patch.js */
const fs = require('fs');
const F = 'prototype/index-bookshelf.html';
let src = fs.readFileSync(F, 'utf8');
const origLen = src.length;
const frag = p => fs.readFileSync('tools/reader/' + p, 'utf8');
let hits = 0;
function rep(name, find, replace, count) {
  count = count || 1;
  const n = src.split(find).length - 1;
  if (n !== count) { console.error('MISS[' + name + '] 命中 ' + n + ' 次（期望 ' + count + '）'); process.exit(1); }
  src = src.split(find).join(replace); hits++;
}
function repRange(name, startMark, endMark, replace) {
  const a = src.indexOf(startMark);
  if (a < 0) { console.error('MISS[' + name + '] 起点未找到'); process.exit(1); }
  const b = src.indexOf(endMark, a);
  if (b < 0) { console.error('MISS[' + name + '] 终点未找到'); process.exit(1); }
  src = src.slice(0, a) + replace + src.slice(b); hits++;
}

/* 1 · 手柄跟随 */
repRange('handle',
  'function brHandlePlace(){const s=brV.sel;if(!s){brHandleHide();return}',
  'function brHandleHide(){', frag('bs56_frag_handle.txt') + '\n');

/* 2 · 删三个内嵌面板 */
repRange('panels',
  '          <!-- V1.53 轮3 · 进度面板（参考图1：统计三格 + 进度滑条 + 阅读明细/自动翻页） -->',
  '          <div class="flex items-center gap-2 text-[9px] opacity-60 px-1 pb-0.5 pt-1">', '');

/* 3 · 底栏 5 → 3 图标 */
repRange('icons',
  '          <!-- 五线性图标底栏（目录/主题/进度/亮度/字号 · 参考图1~3） -->',
  '        </div>\n        <!-- 亮度遮罩',
  '          <!-- 轮5.1 · 三图标底栏：目录 / 进度 / 外观（主题+亮度+字号并入外观弹层） -->\n' +
  '          <div class="flex items-center justify-around pt-0.5">\n' +
  '            <button class="br-ibtn" id="brBtnToc" onclick="brTocOpen()" title="目录"><svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h10"/></svg><span>目录</span></button>\n' +
  '            <button class="br-ibtn" id="brBtnProg" onclick="brProgSheet()" title="进度"><svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M3 12h5m8 0h5"/><circle cx="12" cy="12" r="2.6" fill="currentColor" stroke="none"/></svg><span>进度</span></button>\n' +
  '            <button class="br-ibtn" id="brBtnLook" onclick="brLookSheet()" title="外观"><svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8"/><path d="M12 4v16"/><path d="M8.5 8h.01M8.5 12h.01M15.5 8h.01M15.5 12h.01"/></svg><span>外观</span></button>\n' +
  '          </div>\n');

/* 4 · 面板开关 → 弹层入口 */
repRange('toggle',
  "function brHidePanels(){['brPnlProg','brPnlBright','brPnlFont']",
  'function brRenderBrightPanel(){',
  'function brHidePanels(){/* 轮5.1：内嵌面板已并入底部弹层，保留空实现兼容旧调用 */}\n' +
  "function brProgSheet(){brChromeLabels();const c=document.getElementById('brProgCfi');if(c)c.textContent=brCfi(brV.b,brV.ci,brV.pg);openSheet('sheetBrProg')}\n" +
  "function brLookSheet(){openSheet('sheetBrAppearance');brApOpen()}\n");

/* 5 · 删亮度面板三函数（色板/主题改由外观弹层承担） */
repRange('brightfns', 'function brRenderBrightPanel(){', 'function brLumIsDark(){', '');

/* 6 · 进度弹层 */
rep('progsheet', '  <!-- AI 解读 -->', frag('bs56_frag_prog.txt') + '  <!-- AI 解读 -->');

/* 7 · 外观弹层新增分区 */
repRange('look',
  "        <div><div class=\"text-xs font-bold mb-1.5\">主题</div><div class=\"grid grid-cols-3 gap-2\" id=\"brApThemes\"></div></div>",
  '        <div><div class="text-xs font-bold mb-1.5">字体（系统字体 · 可扩展下载，控制包体积）</div>',
  frag('bs56_frag_look.txt') + '\n');

/* 8 · 外观 JS 扩展 + brApCtl 摘掉系统取色控件 */
rep('js', 'function brApOpen(){', frag('bs56_frag_js.txt') + '\nfunction brApOpen(){');
rep('ctl',
  "  document.getElementById('brApBg').value=d.bg;document.getElementById('brApFg').value=d.fg}",
  '  brApCtlExt()}');

/* 9 · 预览卡与正文都吃图片/纹理/淡化 */
rep('prev',
  "function brApPrev(){const d=brDraft;const el=document.getElementById('brApPrev');\n" +
  '  el.style.background=d.theme===\'custom\'?d.bg:BR_THEMES[d.theme].bg;el.style.color=d.theme===\'custom\'?d.fg:BR_THEMES[d.theme].fg;',
  'function brApPrev(){const d=brDraft;const el=document.getElementById(\'brApPrev\');\n' +
  '  const bg=d.theme===\'custom\'?d.bg:BR_THEMES[d.theme].bg;const c=brStageBgCss(d);\n' +
  '  el.style.backgroundColor=bg;el.style.backgroundImage=c.image||\'none\';el.style.backgroundSize=c.size||\'auto\';\n' +
  '  el.style.color=d.theme===\'custom\'?d.fg:BR_THEMES[d.theme].fg;');

/* 10 · 正文渲染走统一背景 */
rep('stage',
  "  const stage=document.getElementById('brStage');stage.style.background=th.bg;stage.style.color=th.fg;",
  "  const stage=document.getElementById('brStage');stage.style.color=th.fg;brApplyStageBg();");

/* 11 · 保存后亮度即时生效 */
rep('save',
  '  brPagCache={};brPersist();closeSheet(\'sheetBrAppearance\');brRenderPage();',
  '  brPagCache={};brPersist();brLumMaskV=d.lum==null?100:d.lum;brBrightSet(brLumMaskV);\n' +
  '  closeSheet(\'sheetBrAppearance\');brRenderPage();');

fs.writeFileSync(F, src);
console.log('hits=' + hits + ' size ' + origLen + ' → ' + src.length);
if (src.length < origLen * 0.9) { console.error('体积异常缩小，疑似覆盖'); process.exit(1); }
