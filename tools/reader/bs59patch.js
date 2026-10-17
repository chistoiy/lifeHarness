/* V1.53.2 轮5.4 · 阅读器 UI 统一（命中断言 + 体积护栏）
   ① 进阅读器隐藏全局「阅读计时」悬浮条（阅读器顶栏已有本次时长胶囊，
      且退出即自动结算，再挂一条既重复又压正文）
   ② 顶栏/底栏不再固定深色：随当前阅读主题（含自定义底色/图片）取色，
      浅底→浅栏深字 + 细描边，深底→深栏浅字
   用：node tools/reader/bs59patch.js */
const fs = require('fs');
const F = 'prototype/index-bookshelf.html';
let src = fs.readFileSync(F, 'utf8');
const origLen = src.length;
let hits = 0;
function rep(name, find, replace) {
  const n = src.split(find).length - 1;
  if (n !== 1) { console.error('MISS[' + name + '] 命中 ' + n + ' 次（期望 1）'); process.exit(1); }
  src = src.split(find).join(replace); hits++;
}

/* 1 · 计时条在阅读器页隐藏 */
rep('timerbar',
  "  const _tb=$('#timerBar');if(_tb&&typeof timer!=='undefined'&&timer){_tb.classList.toggle('hidden',p==='p-readtimer');_tb.classList.toggle('flex',p!=='p-readtimer')}",
  "  /* 轮5.4：阅读器内不挂全局计时条（顶栏已有时长胶囊 · 退出自动结算） */\n" +
  "  const _tb=$('#timerBar');if(_tb&&typeof timer!=='undefined'&&timer){const off=p==='p-readtimer'||p==='p-readerPage';_tb.classList.toggle('hidden',off);_tb.classList.toggle('flex',!off)}");

/* 2 · 主题化条样式 */
rep('css',
  '    .br-chrome{background:rgba(15,23,42,.86);backdrop-filter:blur(8px);color:#e2e8f0}',
  '    .br-chrome{background:rgba(15,23,42,.86);backdrop-filter:blur(8px);color:#e2e8f0}\n' +
  '    #p-readerPage{--brBarBg:rgba(15,23,42,.86);--brBarFg:#e2e8f0;--brBarLine:rgba(255,255,255,.08);--brBarChip:rgba(255,255,255,.10)}\n' +
  '    .br-bar{background:var(--brBarBg);color:var(--brBarFg);backdrop-filter:blur(10px);transition:background .18s,color .18s}\n' +
  '    .br-bar-top{border-bottom:1px solid var(--brBarLine)}\n' +
  '    .br-bar-bot{border-top:1px solid var(--brBarLine)}\n' +
  '    .br-bar .br-chipbg{background:var(--brBarChip)}');

/* 3 · 顶栏/底栏挂主题类，内部半透明底改用 --brBarChip */
rep('topbar',
  '        <div id="brTop" class="br-chrome hidden absolute top-0 inset-x-0 z-[70] px-3 pt-3 pb-2.5">',
  '        <div id="brTop" class="br-bar br-bar-top hidden absolute top-0 inset-x-0 z-[70] px-3 pt-3 pb-2.5">');
rep('botbar',
  '        <div id="brBottom" class="br-chrome hidden absolute bottom-0 inset-x-0 z-[70] px-3 pt-1.5 pb-2">',
  '        <div id="brBottom" class="br-bar br-bar-bot hidden absolute bottom-0 inset-x-0 z-[70] px-3 pt-1.5 pb-2">');

/* 3b · 条内半透明小胶囊改吃主题变量（浅底栏上白底会看不见） */
rep('chip-sess',
  '<span id="brSessChip" class="text-[9px] rounded-full px-1.5 py-0.5 bg-white/10 tabular-nums">00:00</span>',
  '<span id="brSessChip" class="br-chipbg text-[9px] rounded-full px-1.5 py-0.5 tabular-nums">00:00</span>');
rep('chip-hits',
  '<button class="px-2 py-1 rounded-lg bg-white/10" onclick="brHitGo(-1)">上一处</button><button class="px-2 py-1 rounded-lg bg-white/10" onclick="brHitGo(1)">下一处</button><button class="text-white/60 px-1" onclick="brClearHit()">✕</button>',
  '<button class="br-chipbg px-2 py-1 rounded-lg" onclick="brHitGo(-1)">上一处</button><button class="br-chipbg px-2 py-1 rounded-lg" onclick="brHitGo(1)">下一处</button><button class="opacity-60 px-1" onclick="brClearHit()">✕</button>');
rep('chip-tts',
  '<button class="px-1.5 py-1 rounded-lg bg-white/10" onclick="brTtsRate()" id="brTtsRate">1.0x</button>',
  '<button class="br-chipbg px-1.5 py-1 rounded-lg" onclick="brTtsRate()" id="brTtsRate">1.0x</button>');

/* 4 · 取色与同步函数 */
rep('js',
  'function brApplyStageBg(){',
  '/* CSS 颜色（hex/rgb/hsl/关键字）→ [r,g,b]，交给浏览器解析，避免手写公式 */\n' +
  'function brRgb(css){const d=document.createElement(\'div\');d.style.color=css||\'#faf6ee\';d.style.display=\'none\';\n' +
  '  document.body.appendChild(d);const c=getComputedStyle(d).color;d.remove();\n' +
  '  const m=c.match(/(\\d+(?:\\.\\d+)?)[,\\s]+(\\d+(?:\\.\\d+)?)[,\\s]+(\\d+(?:\\.\\d+)?)/);\n' +
  '  return m?[+m[1],+m[2],+m[3]]:[250,246,238]}\n' +
  '/* 顶栏/底栏跟随阅读主题：浅底用浅栏深字，深底用深栏浅字（不再固定黑底） */\n' +
  'function brBarTheme(){if(!brV.b)return;const el=document.getElementById(\'p-readerPage\');if(!el)return;\n' +
  '  const st=brSt(brV.b),th=st.theme===\'custom\'?{bg:st.bg,fg:st.fg}:(BR_THEMES[st.theme]||BR_THEMES.day);\n' +
  '  const rgb=brRgb(th.bg),L=0.299*rgb[0]+0.587*rgb[1]+0.114*rgb[2];\n' +
  '  const s=el.style,light=L>150;\n' +
  '  if(light){s.setProperty(\'--brBarBg\',\'rgba(\'+rgb[0]+\',\'+rgb[1]+\',\'+rgb[2]+\',.94)\');\n' +
  '    s.setProperty(\'--brBarFg\',th.fg||\'#3b3630\');s.setProperty(\'--brBarLine\',\'rgba(0,0,0,.10)\');\n' +
  '    s.setProperty(\'--brBarChip\',\'rgba(0,0,0,.06)\')}\n' +
  '  else{s.setProperty(\'--brBarBg\',\'rgba(15,23,42,.92)\');s.setProperty(\'--brBarFg\',\'#e2e8f0\');\n' +
  '    s.setProperty(\'--brBarLine\',\'rgba(255,255,255,.10)\');s.setProperty(\'--brBarChip\',\'rgba(255,255,255,.12)\')}\n' +
  '  /* 图片/纹理背景时正文可读性靠淡化层，条上再加一档模糊 */\n' +
  '  el.classList.toggle(\'br-bar-blurmore\',!!(st.bgImg||st.bgTex))}\n' +
  'function brApplyStageBg(){');

/* 5 · 正文重绘时同步条色 */
rep('sync',
  '  const stage=document.getElementById(\'brStage\');stage.style.color=th.fg;brApplyStageBg();',
  '  const stage=document.getElementById(\'brStage\');stage.style.color=th.fg;brApplyStageBg();brBarTheme();');

/* 6 · 修轮5.1 引入的底色回归：brApplyStageBg 直接用合并态 d.bg，
      切回内置主题时正文仍是上一次的自定义底色，而字色跟主题 → 深底深字看不清 */
rep('stagebg',
  'function brApplyStageBg(){if(!brV.b)return;const stg=document.getElementById(\'brStage\');if(!stg)return;\n' +
  '  const d=brSt(brV.b),c=brStageBgCss(d);\n' +
  "  stg.style.backgroundColor=d.bg||'#faf6ee';",
  'function brApplyStageBg(){if(!brV.b)return;const stg=document.getElementById(\'brStage\');if(!stg)return;\n' +
  '  const d=brSt(brV.b),c=brStageBgCss(d);\n' +
  '  const th=BR_THEMES[d.theme]||BR_THEMES.day;\n' +
  "  stg.style.backgroundColor=d.theme==='custom'?(d.bg||th.bg):th.bg;");

fs.writeFileSync(F, src);
console.log('hits=' + hits + ' size ' + origLen + ' → ' + src.length);
if (src.length < origLen * 0.9) { console.error('体积异常缩小，疑似覆盖'); process.exit(1); }
