/* 批三 R3-2 原型门·四件套补丁（交棒话术 §3A）— CRLF 安全：锚点与插入均用 \r\n
 * 用法：node tools/r32style_patch.js   （改前快照已落 tmp/index-bookshelf.before-b3proto-20261003.html）
 * 护栏：每处替换断言命中 1 次；写回后体积增量校验（+200~+6000 字符）；不一致 exit 1 不落盘。 */
const fs = require('fs');
const P = 'prototype/index-bookshelf.html';
const NL = '\r\n';
let s = fs.readFileSync(P, 'utf8');
const before = s.length;
const reps = [];

function rep(name, anchor, out) {
  reps.push([name, anchor, out]);
}

/* 1) 角色→样式表 CSS（值直取通鉴 style0001.css；.br-bt/.br-nm 撞外观层按钮类，全部收进 .brp- 命名空间） */
rep('css',
  '    .br-just .brp{text-align:justify}',
  '    .br-just .brp{text-align:justify}' + NL +
  '    /* 批三 R3-2 原书样式保真·角色样式（值直取《資治通鑑》特殊標點版 style0001.css；brp- 前缀避让外观层 .br-bt 按钮类；仅「跟随原书样式」开时由 mk() 挂上） */' + NL +
  '    .brp-cmt{color:navy}' + NL +
  '    .brp-note{color:DarkGreen;font-size:.75em;margin-inline-start:.5em;margin-inline-end:.5em}' + NL +
  '    .brp-corr{color:Purple;font-size:.75em}' + NL +
  '    .brp-reign{color:SaddleBrown;font-weight:700}' + NL +
  '    .brp-gray{color:DimGray;font-size:.88em}' + NL +
  '    .brp-tag{background:DimGray;color:#fff;border:2px double #fff}' + NL +
  '    .brp-nm{border-left:.12em solid}' + NL +
  '    .brp-nm1{border:.1em solid}' + NL +
  '    .brp-bt{text-decoration:underline wavy}');

/* 2) BR_DEF 默认开 orig */
rep('brdef',
  "s2t:'orig',ind:'auto'};",
  "s2t:'orig',ind:'auto',orig:true};");

/* 3) b13 书目加 unsupported（提示行数据驱动，不许静默） */
rep('book',
  "note:'注释体/简繁演示样本',fin:''}];",
  "note:'注释体/简繁演示样本',unsupported:['vertical'],fin:''}];");

/* 4) 样本段角色字段 */
rep('gray',
  " {k:'p',own:1,t:'起著雍攝提格，盡戊申，凡一年有奇。'},",
  " {k:'p',own:1,r:'gray',t:'起著雍攝提格，盡戊申，凡一年有奇。'},");
rep('reign',
  " {k:'p',t:'初，智宣子將以瑤為後。",
  " {k:'p',r:'reign',nm:['智宣子','智果'],t:'初，智宣子將以瑤為後。");
rep('corr',
  "fn:'智果，別族也。賢五，謂五事勝人；甚一，謂不仁過於人。'},",
  "fn:'智果，別族也。賢五，謂五事勝人；甚一，謂不仁過於人。'}," + NL +
  " {k:'p',r:'corr',t:'「美鬢長大則賢」，「鬢」舊本訛作「鬣」，覆宋本正作「鬢」，今從之。'},");
rep('bt',
  "fn:'溫公書成，奏進曰：專取關國家之盛衰、系生民之休戚者。'},",
  "fn:'溫公書成，奏進曰：專取關國家之盛衰、系生民之休戚者。'}," + NL +
  " {k:'p',bt:['資治通鑑','外紀','長編'],t:'光與劉恕、范祖禹同修，書成奏進，帝賜名曰資治通鑑，恕別作外紀，祖禹有長編。'},");
rep('nm-h',
  " {k:'p',t:'司馬光編年，上起三家分晉，",
  " {k:'p',nm:['司馬光'],nm1:['三家分晉'],t:'司馬光編年，上起三家分晉，");
rep('note',
  " {k:'fn',t:'胡三省注：作，謂能創制；",
  " {k:'fn',r:'note',t:'胡三省注：作，謂能創制；");
rep('tag',
  " {k:'h',lv:2,t:'臣光曰'},",
  " {k:'p',r:'tag',t:'臣光曰'},");
rep('cmt',
  " {k:'p',t:'臣聞天子之職莫大於禮，",
  " {k:'p',r:'cmt',t:'臣聞天子之職莫大於禮，");

/* 5) mk()：开态挂角色 class，关态＝现状 R3-2 止血口径 */
rep('mk',
  "const sty=x.k==='h'?'class=\"brp brp-h'",
  "let sty=(st.orig&&x.r)?'class=\"brp brp-'+x.r+(x.r==='note'?' brp-fn':'')+(x.own?' brp-own':'')+'\"':(x.k==='h'?'class=\"brp brp-h'");
rep('mk-tail',
  "'class=\"brp brp-fn\"':x.own?'class=\"brp brp-own\"':'class=\"brp\"';",
  "'class=\"brp brp-fn\"':x.own?'class=\"brp brp-own\"':'class=\"brp\"');");

/* 6) brParaInner：nm/nm1/bt 内联连线（仅开态） */
rep('inner',
  "function brParaInner(bid,ci,x,pi){let inner=brEsc(brConv(bid,x.t));",
  "function brParaInner(bid,ci,x,pi){let inner=brEsc(brConv(bid,x.t));/* 批三 R3-2：专名线/书名线内联（nm/nm1/bt 字段驱动·跟随原书样式开时才挂） */\r\n  if(brSt(bid).orig){['nm','nm1','bt'].forEach(function(f){(x[f]||[]).forEach(function(w){var re=new RegExp(brRx(w),'g');inner=inner.replace(re,function(m){return '<span class=\"brp-'+f+'\">'+m+'</span>'})})});}");

/* 7) 外观弹层：开关行＋不支持项提示行（两端对齐旁） */
rep('sheet',
  '<div class="flex items-center justify-between text-xs"><span>两端对齐</span><span class="toggle" id="brApJustTgl" onclick="brApTgl(\'just\',this)"></span></div>',
  '<div class="flex items-center justify-between text-xs"><span>两端对齐</span><span class="toggle" id="brApJustTgl" onclick="brApTgl(\'just\',this)"></span></div>' + NL +
  '          <div class="flex items-center justify-between text-xs"><span>跟随原书样式</span><span class="toggle" id="brApOrigTgl" onclick="brApTgl(\'orig\',this)"></span></div>' + NL +
  '          <div class="text-[9px] text-slate-400 leading-4 -mt-1.5 hidden" id="brApOrigWarn">本书含竖排排版，当前按横排单栏显示</div>');

/* 8) brApCtl：开关态＋提示行显隐（数据驱动） */
rep('ctl',
  "  document.getElementById('brApJustTgl').classList.toggle('on',!!d.just);",
  "  document.getElementById('brApJustTgl').classList.toggle('on',!!d.just);" + NL +
  "  document.getElementById('brApOrigTgl').classList.toggle('on',!!d.orig);" + NL +
  "  document.getElementById('brApOrigWarn').classList.toggle('hidden',!(bsBook(brV.b)&&bsBook(brV.b).unsupported&&bsBook(brV.b).unsupported.indexOf('vertical')>=0));");

/* 9) 深链 st1/st0/stn */
rep('dlc',
  "  else if(m==='ap'){brOpen('b13');brShowChrome();openSheet('sheetBrAppearance');brApOpen()}}",
  "  else if(m==='ap'){brOpen('b13');brShowChrome();openSheet('sheetBrAppearance');brApOpen()}" + NL +
  "  else if(m==='st1'||m==='st0'){brBooksCfg.b13=Object.assign(brBooksCfg.b13||{},{orig:m==='st1'});brOpen('b13');brShowChrome();brPagCache={};brRenderPage()}" + NL +
  "  else if(m==='stn'){brOpen('b13');brShowChrome();openSheet('sheetBrAppearance');brApOpen()}}");
rep('dlcomment',
  "/* V1.54 真机轮3 R3-2/R3-6 深链：?r32=anc → 古籍注释体样本 · ?r32=s → 同屏简体态 · ?r32=ap → 外观弹层（两端对齐/简繁两行） */",
  "/* V1.54 真机轮3 R3-2/R3-6 深链：?r32=anc → 古籍注释体样本 · ?r32=s → 同屏简体态 · ?r32=ap → 外观弹层（两端对齐/简繁两行） */" + NL +
  "/* 批三 R3-2 原书样式保真深链：?r32=st1 → 跟随原书样式开（五层色+专名线） · ?r32=st0 → 关态对照（现状止血） · ?r32=stn → 外观弹层含不支持项提示行 */");

/* —— 执行 —— */
const errs = [];
for (const [name, a, b] of reps) {
  const n = s.split(a).length - 1;
  if (n !== 1) { errs.push(name + ' 命中 ' + n + ' 次（应为 1）：' + a.slice(0, 40)); continue; }
  s = s.replace(a, () => b);
}
if (errs.length) { console.log('ABORT 未落盘：\n' + errs.join('\n')); process.exit(1); }
const delta = s.length - before;
if (delta < 200 || delta > 6000) { console.log('ABORT 体积增量异常：' + delta); process.exit(1); }
fs.writeFileSync(P, s, 'utf8');
console.log('OK 已落盘，字符增量 +' + delta + '（' + before + '→' + s.length + '）');
