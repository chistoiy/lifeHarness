/* 「我的」页 · 版式三选落盘脚本（2026-10-12 · 待产品过门）
 *
 * 取代 tools/proto_profile_hero.js（已归档 tmp/pa/proto_profile_hero.js.bak）。
 * 在「批B 四组结构」的干净基线上，一次生成三种可切换版式：
 *   lay-hero     方向一「记录仪表」（默认）：渐变身份卡（连击环＋读数带＋里程碑），隐藏旧顶区 .pf-legacy；下半页常驻圆角卡
 *   lay-chapters 方向二「编辑章节」：显 .pf-legacy（身份行＋去卡读数带）；组标题编号化 01..04＋发丝；卡片去卡→连续卷轴；签名页脚
 *   lay-minimal  方向三「极简卷轴」：显 .pf-legacy；组标题淡小字；卡片去卡去发丝→纯间距；极简页脚
 * 入口＝「设置 › 外观 › 我的页版式」；控制台 setMyLayout('hero'|'chapters'|'minimal')；
 * 持久化＝localStorage lh.myLayout；地址带 ?mylayout= 可强制（不写持久化）。
 *
 * 严格锚点 + 唯一性断言：任一锚点命中数 ≠ 1 即抛错、不落盘（防误伤多线共享面）。
 * 本脚本只做形态覆盖，不改任何既有行的业务逻辑（onclick/id/文本皆原样）。
 *
 * 用法：node tools/proto_profile_layout.js --dry   # 预览替换，不写盘
 *      node tools/proto_profile_layout.js         # 落盘
 */
const fs = require('fs');
const P = 'prototype/index.html';
const DRY = process.argv.includes('--dry');
let html = fs.readFileSync(P, 'utf8');
const before = html;

function sub(anchor, repl, label) {
  const n = html.split(anchor).length - 1;
  if (n !== 1) throw new Error('锚点「' + label + '」命中 ' + n + ' 次（应为 1），拒绝落盘');
  html = html.replace(anchor, repl);
  console.log('OK   ' + label);
}

/* ---------- 0) body 默认版式类（默认＝方向一 hero） ---------- */
sub('<body class="flex items-center justify-center">',
    '<body class="lay-hero flex items-center justify-center">',
    'body 默认版式类 lay-hero');

/* ---------- 1) CSS 三版式段（插在 .safe-pb 之后，仍在 <style> 内） ---------- */
const CSS_ANCHOR = '  .safe-pb{padding-bottom:96px}\n';
const CSS_BLOCK = CSS_ANCHOR +
`  /* ===== 「我的」页·版式三选（2026-10-12 · 待产品过门；定形并落实现后本段整体摘除）=====
     版式：body.lay-hero（默认·记录仪表）｜lay-chapters（编辑章节）｜lay-minimal（极简卷轴）。
     入口＝「设置 › 外观 › 我的页版式」；控制台 setMyLayout('hero'|'chapters'|'minimal')；
     持久化＝localStorage lh.myLayout；地址带 ?mylayout= 可强制（不写持久化）。
     hero＝渐变身份卡 .pf-hero（头像嵌连击环＋读数带＋里程碑），隐藏旧顶区 .pf-legacy；下半页常驻圆角卡。
     chapters＝显 .pf-legacy（身份行＋去卡读数带）；组标题编号化(01..04)＋发丝；卡片去卡→连续卷轴；签名页脚。
     minimal＝显 .pf-legacy；组标题淡小字；卡片去卡去发丝→纯间距；极简页脚。
     全程只做形态覆盖，零业务逻辑改动。 */
  .pf-hero{display:none}
  body.lay-hero .pf-hero{display:block}
  body.lay-hero .pf-legacy{display:none!important}
  .pf-ro b{font-variant-numeric:tabular-nums}

  /* —— 方向二「编辑章节」—— */
  body.lay-chapters #p-profile .pf-gt{display:flex;align-items:center;gap:9px;margin:34px 0 3px;font-size:12px;letter-spacing:.06em}
  body.lay-chapters #p-profile .pf-gt::before{content:attr(data-n);font-variant-numeric:tabular-nums;color:var(--accent);font-weight:800;opacity:.55}
  body.lay-chapters #p-profile .pf-gt::after{content:'';flex:1;height:1px;background:currentColor;opacity:.13}
  body.lay-chapters #p-profile>.card{background:transparent!important;border:0!important;box-shadow:none!important;border-radius:0!important;margin-top:0!important}
  body.lay-chapters #p-profile .pf-legacy .card{background:transparent!important;border:0!important;box-shadow:none!important;padding:0!important}
  body.lay-chapters #p-profile .pf-legacy b{font-size:21px}
  body.lay-chapters #p-profile #pfAbout{margin-top:42px!important;text-align:center;letter-spacing:.05em;background:transparent!important;border:0!important;box-shadow:none!important}
  body.lay-chapters #p-profile #pfAbout>div:first-child{justify-content:center}

  /* —— 方向三「极简卷轴」—— */
  body.lay-minimal #p-profile .pf-gt{margin:42px 0 4px;font-size:11px;letter-spacing:.05em;opacity:.7}
  body.lay-minimal #p-profile>.card{background:transparent!important;border:0!important;box-shadow:none!important;border-radius:0!important;margin-top:0!important}
  body.lay-minimal #p-profile>.card button{border-top:0!important;padding-top:15px;padding-bottom:15px}
  body.lay-minimal #p-profile .pf-legacy .card{background:transparent!important;border:0!important;box-shadow:none!important;padding:0!important}
  body.lay-minimal #p-profile .pf-legacy b{font-size:23px}
  body.lay-minimal #p-profile #pfAbout{margin-top:46px!important;text-align:center;font-size:10.5px;background:transparent!important;border:0!important;box-shadow:none!important}
  body.lay-minimal #p-profile #pfAbout>div:first-child{justify-content:center}
`;
sub(CSS_ANCHOR, CSS_BLOCK, 'CSS 三版式段');

/* ---------- 2) HTML hero 身份卡（紧跟 #p-profile 开标签） ---------- */
const SEC_ANCHOR = '<section id="p-profile" class="page px-5 safe-pb no-scrollbar">\n';
const HERO =
`      <!-- ===== 版式·方向一「记录仪表」身份卡（2026-10-12 · 待产品过门；定形落实现后本块整体摘除）===== -->
      <div class="pf-hero grad rounded-3xl p-5 text-white shadow-lg shadow-indigo-500/20 relative overflow-hidden">
        <div class="absolute -right-8 -top-10 w-36 h-36 rounded-full bg-white/10"></div>
        <div class="absolute -right-2 top-12 w-20 h-20 rounded-full bg-white/10"></div>
        <div class="relative flex items-center gap-4">
          <div id="pfHeroRingWrap" class="relative w-16 h-16 shrink-0" title="连续记录里程碑">
            <svg viewBox="0 0 36 36" class="w-16 h-16 ring-progress">
              <circle cx="18" cy="18" r="16.2" fill="none" stroke="rgba(255,255,255,.28)" stroke-width="2"/>
              <circle id="pfHeroRing" cx="18" cy="18" r="16.2" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" stroke-dasharray="0 100"/>
            </svg>
            <div id="pfHeroAv" class="absolute inset-[5px] rounded-full bg-white/20 flex items-center justify-center text-white text-xl font-extrabold">C</div>
          </div>
          <div class="min-w-0">
            <div id="pfHeroName" class="font-extrabold text-lg tracking-tight">CHIST</div>
            <div id="pfHeroSub" class="text-[11px] opacity-85">本地模式 · 无账号 · 已记录 55 天</div>
          </div>
          <button id="pfHeroEdit" class="ml-auto shrink-0 text-xs font-bold bg-white/20 rounded-full px-3 py-1.5 active:scale-95 transition" onclick="openProfileEdit()">编辑</button>
        </div>
        <div class="pf-ro relative mt-4 grid grid-cols-3 text-center">
          <div class="cursor-pointer active:opacity-70 transition" onclick="navTab('p-todo')" title="待办清单">
            <b id="pfHeroDone" class="block text-2xl font-extrabold">128</b>
            <span class="text-[10px] opacity-80">完成任务</span>
          </div>
          <div class="border-x border-white/20 cursor-pointer active:opacity-70 transition" onclick="navTab('p-records');switchRecord('diary')" title="日记记录">
            <b id="pfHeroStreak" class="block text-2xl font-extrabold">55</b>
            <span class="text-[10px] opacity-80">连续记录天</span>
          </div>
          <div class="cursor-pointer active:opacity-70 transition" onclick="navTab('p-records');switchRecord('book')" title="书架在册">
            <b id="pfHeroBooks" class="block text-2xl font-extrabold">17</b>
            <span class="text-[10px] opacity-80">在册书籍</span>
          </div>
        </div>
        <div class="pf-ro relative mt-3 flex items-center gap-2 text-[11px] bg-white/15 rounded-full px-3 py-1.5 w-fit">
          <span class="w-1.5 h-1.5 rounded-full bg-white/80"></span>
          <span>再记 <b id="pfHeroLeft" class="mx-0.5">45</b> 天达成百日里程碑</span>
        </div>
      </div>
`;
sub(SEC_ANCHOR, SEC_ANCHOR + HERO, 'HTML hero 身份卡');

/* ---------- 3) 旧顶区加 .pf-legacy 类名（只加类，不动内容） ---------- */
sub('      <div class="flex items-center gap-4">\n        <div id="pfAv"',
    '      <div class="pf-legacy flex items-center gap-4">\n        <div id="pfAv"',
    'legacy 身份行');
sub('      <div class="mt-4 grid grid-cols-3 text-center text-[11px]">\n',
    '      <div class="pf-legacy mt-4 grid grid-cols-3 text-center text-[11px]">\n',
    'legacy 统计行');

/* ---------- 4) 四组标题加 .pf-gt 与编号（供方向二 ::before 使用） ---------- */
const GT = [
  ['记录', '01'], ['数据与提醒', '02'], ['外观与交互', '03'], ['系统与维护', '04'],
];
for (const [name, n] of GT) {
  const a = '      <div class="text-xs font-extrabold text-slate-400 mt-4 mb-1.5">' + name + '</div>\n';
  const b = '      <div class="pf-gt text-xs font-extrabold text-slate-400 mt-4 mb-1.5" data-n="' + n + '">' + name + '</div>\n';
  sub(a, b, '组标题 ' + n + ' ' + name);
}

/* ---------- 5) 关于卡加 id（供方向二/三页脚覆盖） ---------- */
sub('      <div class="card mt-4 text-[11px] text-slate-400 leading-6">\n',
    '      <div id="pfAbout" class="card mt-4 text-[11px] text-slate-400 leading-6">\n',
    '关于卡 id=pfAbout');

/* ---------- 6) JS 切换块（插在壳层治理脚本之前） ---------- */
const JS_ANCHOR = '</script>\n<script>/*LH-GOV-START*/';
const JS =
`/* ===== 「我的」页·版式三选（2026-10-12 · 待产品过门；定形并落实现后本块整体摘除）=====
   入口＝「设置 › 外观 › 我的页版式」；控制台 setMyLayout('hero'|'chapters'|'minimal')；
   持久化＝localStorage lh.myLayout；地址带 ?mylayout= 可强制（不写持久化，便于截图/评审）。
   hero 数据＝旧顶区（#pfAv/#pfName/#pfSub/#pfDone/#pfStreak/#pfBooks）保持不动，只被 CSS 隐藏，
   由 renderProfile 跑完后镜像到身份卡同名节点；连击环 #pfHeroRing＝连击进度（100 天里程碑，待产品定）。 */
(function(){
  function q(s){return document.querySelector(s);}
  function seg(on,el){if(el)el.className=(on?'seg-on ':'')+'flex-1 rounded-lg py-1.5'+(on?'':' text-slate-500');}
  var LAYS=['hero','chapters','minimal'];
  var HINT={
    hero:'顶部为渐变身份卡：连击环＋读数带＋里程碑；下半页分组圆角卡。',
    chapters:'顶部为身份行＋读数带；分组标题编号化，卡片去边框连成卷轴，结尾签名页脚。',
    minimal:'顶部为身份行＋读数带；卡片完全去卡，仅靠留白与间距分组，最安静。'};
  window.pfHeroSync=function(){
    var map=[['#pfHeroDone','#pfDone'],['#pfHeroStreak','#pfStreak'],['#pfHeroBooks','#pfBooks'],
             ['#pfHeroName','#pfName'],['#pfHeroSub','#pfSub'],['#pfHeroAv','#pfAv']];
    for(var i=0;i<map.length;i++){var t=q(map[i][0]),s=q(map[i][1]);if(t&&s)t.textContent=s.textContent;}
    var ss=q('#pfStreak'),r=q('#pfHeroRing');
    if(r){var st=parseInt((ss&&ss.textContent)||'0',10)||0;
      var pct=Math.max(0,Math.min(100,st));
      r.setAttribute('stroke-dasharray',pct+' 100');
      var w=q('#pfHeroRingWrap'); if(w)w.setAttribute('title','连续记录 '+st+' 天 · 里程碑 100 天');
      var lf=q('#pfHeroLeft'); if(lf)lf.textContent=String(Math.max(0,100-st));}
  };
  function paint(){
    var cur='hero';
    for(var i=0;i<LAYS.length;i++){ if(document.body.classList.contains('lay-'+LAYS[i])) cur=LAYS[i]; }
    var btn={hero:'layHero',chapters:'layChapters',minimal:'layMinimal'};
    for(var k in btn){ if(document.getElementById(btn[k])) seg(k===cur,document.getElementById(btn[k])); }
    var h=document.getElementById('myLayoutHint'); if(h)h.textContent=HINT[cur];
  }
  window.setMyLayout=function(v,persist){
    if(LAYS.indexOf(v)<0)v='hero';
    for(var i=0;i<LAYS.length;i++)document.body.classList.remove('lay-'+LAYS[i]);
    document.body.classList.add('lay-'+v);
    if(persist!==false){try{localStorage.setItem('lh.myLayout',v)}catch(e){}}
    window.pfHeroSync(); paint();
  };
  var init='hero';
  try{init=localStorage.getItem('lh.myLayout')||'hero'}catch(e){}
  var m=/[?&]mylayout=(hero|chapters|minimal)/.exec(location.search);
  if(m){ window.setMyLayout(m[1],false); } else { window.setMyLayout(init); }
  if(typeof window.renderProfile==='function'){
    var _rp=window.renderProfile;
    window.renderProfile=function(){var r=_rp.apply(this,arguments);window.pfHeroSync();return r;};
  }
  window.pfHeroSync();
})();
`;
sub(JS_ANCHOR, '</script>\n<script>' + JS + '</script>\n<script>/*LH-GOV-START*/', 'JS 版式切换块');

/* ---------- 7) 外观页新增「我的页版式」切换卡（底栏手势卡之后、section 收尾之前） ---------- */
const AP_ANCHOR =
`          <div class="text-[10px] text-slate-400 mt-2">悬浮球保持原位（不随底栏落底）· 预览仅示意线索相对屏幕底部的位置</div>
        </div>
      </div>
    </section>
`;
const AP_REPL =
`          <div class="text-[10px] text-slate-400 mt-2">悬浮球保持原位（不随底栏落底）· 预览仅示意线索相对屏幕底部的位置</div>
        </div>
      </div>

      <!-- ===== 我的页版式切换（2026-10-12 · 待产品过门；定形并落实现后本卡整体摘除）===== -->
      <div class="card mt-4" id="myLayoutCard">
        <div class="flex items-center gap-3">
          <span class="set-ic bg-slate-100 dark:bg-slate-800 !flex items-center justify-center"><svg class="w-[16px] h-[16px]" fill="none" stroke="currentColor" stroke-width="1.8" viewBox="0 0 24 24" stroke-linecap="round" stroke-linejoin="round"><rect x="4.2" y="4.6" width="15.6" height="14.8" rx="2.4"/><path d="M4.2 9.6h15.6M9.6 9.6v9.8"/></svg></span>
          <div class="flex-1"><b class="text-sm">我的页版式</b><div class="text-[11px] text-slate-400">身份区与列表的呈现方式 · 三选一</div></div>
        </div>
        <div class="flex gap-1 bg-slate-200/70 dark:bg-slate-800 rounded-xl p-1 text-xs font-bold mt-3" id="myLayoutSeg">
          <button id="layHero" class="seg-on flex-1 rounded-lg py-1.5" onclick="setMyLayout('hero')">记录仪表</button>
          <button id="layChapters" class="flex-1 rounded-lg py-1.5 text-slate-500" onclick="setMyLayout('chapters')">编辑章节</button>
          <button id="layMinimal" class="flex-1 rounded-lg py-1.5 text-slate-500" onclick="setMyLayout('minimal')">极简卷轴</button>
        </div>
        <div class="text-[11px] text-slate-400 mt-2" id="myLayoutHint">顶部为渐变身份卡：连击环＋读数带＋里程碑；下半页分组圆角卡。</div>
      </div>
    </section>
`;
sub(AP_ANCHOR, AP_REPL, '外观页 我的页版式切换卡');

/* ---------- 落盘 ---------- */
if (DRY) {
  console.log('\n--dry：未写盘。预计新增 ' + (html.length - before.length) + ' 字符。');
  process.exit(0);
}
fs.writeFileSync(P, html);
console.log('\n已写 ' + P + '（新增 ' + (html.length - before.length) + ' 字符）');
