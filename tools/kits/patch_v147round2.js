/* V1.47 验收轮2 · 三条改刀：尺子全屏+滑动游标 / 工具卡紧凑 / 插件入口归位（C5 拍板）
 * 用法：node tools/kits/patch_v147round2.js [--dry]
 * 护栏：逐条断言命中数符合期望（默认 1），任一不符即零写入退出；写后校验体积；EOL 自适应。 */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const K = 'prototype/index-kits.html', M = 'prototype/index.html';
const cache = {}, eol = {};   /* 供边界取值助手使用（断言阶段填充） */

/* ===== CSS：尺子全屏舞台 + 紧凑工具卡原语 ===== */
const CSS_ANCHOR = '#tpStage.tp-led #tpBody{background-image:radial-gradient(circle at center,rgba(0,0,0,.6) 0 28%,transparent 30%);background-size:6px 6px}';
const CSS_ADD = `
  /* ===== 尺子全屏舞台 + 滑动游标（V1.47 验收轮2 · LH-KIT-RULER） ===== */
  #rulerStage{background:#f7f8fb;color:#0f172a;display:none}
  #rulerStage:not(.hidden){display:flex}
  .dark #rulerStage{background:#0b1120;color:#e2e8f0}
  #rsBar{position:absolute;top:0;left:0;right:0;z-index:6;display:flex;align-items:center;gap:6px;flex-wrap:wrap;padding:14px 14px 9px;font-size:10px}
  #rsBar .rs-chip{padding:4px 10px;border-radius:999px;border:1px solid rgba(100,116,139,.35);font-size:10px;font-weight:700;cursor:pointer;background:transparent;color:inherit}
  #rsBar .rs-chip.on{background:var(--accent,#6366f1);border-color:transparent;color:#fff}
  #rsTape{position:absolute;left:0;right:0;top:74px;height:104px;border-top:1px solid rgba(100,116,139,.28);border-bottom:1px solid rgba(100,116,139,.28);background:rgba(255,255,255,.72);overflow:hidden;touch-action:none}
  .dark #rsTape{background:rgba(255,255,255,.06);border-color:rgba(148,163,184,.3)}
  #rsScale{position:absolute;left:0;top:0;height:100%;width:1000px}
  #rsScale i{position:absolute;bottom:0;width:1px;background:currentColor;opacity:.5}
  #rsScale b{position:absolute;bottom:10px;font-size:8.5px;font-weight:700;transform:translateX(3px);opacity:.75}
  #rsZero{position:absolute;top:0;bottom:0;width:2px;background:var(--accent,#6366f1);z-index:3;cursor:ew-resize;touch-action:none}
  #rsZero::before{content:'0';position:absolute;left:-15px;top:50%;transform:translateY(-50%);font-size:9px;font-weight:800;color:var(--accent,#6366f1)}
  #rsCursor{position:absolute;top:0;bottom:0;width:2px;background:#ef4444;z-index:4;cursor:ew-resize;touch-action:none}
  #rsCursor::before{content:'';position:absolute;left:-6px;top:-1px;border-left:7px solid transparent;border-right:7px solid transparent;border-top:9px solid #ef4444}
  #rsCursor::after{content:'';position:absolute;left:-6px;bottom:-1px;border-left:7px solid transparent;border-right:7px solid transparent;border-bottom:9px solid #ef4444}
  #rsRead{position:absolute;left:0;right:0;top:196px;text-align:center;padding:0 14px}
  #rsRead .big{font-size:34px;font-weight:800;letter-spacing:-.5px;font-variant-numeric:tabular-nums;line-height:1.15}
  #rsRead .sub{font-size:11px;opacity:.62;margin-top:3px;font-variant-numeric:tabular-nums}
  #rsGuideTip{position:absolute;top:252px;left:14px;right:14px;text-align:center;font-size:10px;opacity:.5}
  #rsGuide{position:absolute;top:270px;bottom:56px;left:14px;right:14px;border:1.5px dashed rgba(100,116,139,.45);border-radius:18px;pointer-events:none}
  #rsCtl{position:absolute;left:14px;right:14px;bottom:16px;display:flex;align-items:center;gap:8px;font-size:10px}
  #rsCtl input[type=range]{flex:1;min-width:0}
  /* ===== 紧凑工具卡（V1.47 验收轮2：5 列 / 去白卡底） ===== */
  .kit-tile{display:flex;flex-direction:column;align-items:center;gap:4px;cursor:pointer;position:relative;padding:6px 2px 7px;border-radius:14px;transition:transform .12s}
  .kit-tile:active{transform:scale(.95)}
  .kit-tile .kt-ic{width:30px;height:30px;border-radius:9px;background:rgba(148,163,184,.18);display:flex;align-items:center;justify-content:center;font-size:15px;color:inherit}
  .dark .kit-tile .kt-ic{background:rgba(148,163,184,.2)}
  .kit-tile .kt-nm{font-size:9.5px;font-weight:700;line-height:1.2;text-align:center;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .kit-tile .kt-sub{font-size:8px;color:#94a3b8;line-height:1.1}
  .kit-tile .kt-fav{position:absolute;right:3px;top:1px;font-size:8px;color:#fbbf24;line-height:1}
  .kit-tile .kt-tag{position:absolute;right:2px;top:1px;font-size:7px;color:#94a3b8;line-height:1}`;

/* ===== HTML：尺子全屏舞台 ===== */
const HTML_ANCHOR = `      <button class="chip !text-[10px]" onclick="tpClose()">✕ 退出</button></div>
    </div>`;
const HTML_ADD = `
    <!-- ===== 尺子全屏舞台（LH-KIT-RULER · V1.47 验收轮2） ===== -->
    <div id="rulerStage" class="fixed inset-0 z-[90] hidden">
      <div id="rsBar">
        <b class="text-[12px] mr-1">尺子</b>
        <button class="rs-chip" id="rsUcm" onclick="rulerUnit('cm')">cm</button>
        <button class="rs-chip" id="rsUin" onclick="rulerUnit('in')">in</button>
        <span class="flex-1"></span>
        <button class="rs-chip" id="rsDirLong" onclick="rulerDir('long')">长边</button>
        <button class="rs-chip" id="rsDirShort" onclick="rulerDir('short')">短边</button>
        <button class="rs-chip" onclick="rulerBank()">银行卡校准</button>
        <button class="rs-chip" onclick="rulerFsClose()">✕ 退出</button>
      </div>
      <div id="rsTape" onpointerdown="rsTapeDown(event)">
        <div id="rsScale"></div>
        <div id="rsZero" onpointerdown="rsGrab(event,'zero')"></div>
        <div id="rsCursor" onpointerdown="rsGrab(event,'cur')"></div>
      </div>
      <div id="rsRead"><div class="big" id="rsBig">0 mm</div><div class="sub" id="rulerSpan"></div><div class="sub" id="rsZeroPos"></div></div>
      <div id="rsGuideTip">把要量的东西贴着上方尺条 · 按住红线滑到末端即自动读数</div>
      <div id="rsGuide"></div>
      <div id="rsCtl"><span>倍率</span><input type="range" id="rsCal" min="0.85" max="1.15" step="0.002" value="1" oninput="rulerCalSet(this.value)"><b class="font-mono w-14 text-right" id="rsCalV">1.000×</b></div>
    </div>`;

/* ===== 尺子 JS 函数组（插在 rulerApplyBoot 之前） ===== */
const RS_FNS = `/* —— 尺子全屏舞台 + 滑动游标（V1.47 验收轮2） —— */
function rulerFsOpen(){const st=$('#rulerStage');if(!st)return;st.classList.remove('hidden');document.body.classList.add('tp-noscroll');
 if(KITS.rsCur==null)KITS.rsCur=Math.round(rulerTargetMm()*.4);rsClamp();rulerDraw();rsChips()}
function rulerFsClose(){const st=$('#rulerStage');if(!st)return;st.classList.add('hidden');document.body.classList.remove('tp-noscroll')}
function rsChips(){const u=$('#rsUcm');if(!u)return;const cm=(KITS.rulerUnit||'cm')==='cm';
 u.classList.toggle('on',cm);$('#rsUin').classList.toggle('on',!cm);
 $('#rsDirLong').classList.toggle('on',(KITS.rulerDir||'long')==='long');$('#rsDirShort').classList.toggle('on',KITS.rulerDir==='short')}
function rsGeom(){const tp=$('#rsTape');if(!tp)return null;const r=tp.getBoundingClientRect();
 const target=rulerTargetMm(),px=r.width||400;return {left:r.left,px:px,ppmm:px/target,target:target}}
function rsClamp(){const g=rsGeom();if(!g)return;const t=g.target;
 KITS.rsZero=Math.min(Math.max(0,KITS.rsZero||0),t-1);
 if(KITS.rsCur==null)KITS.rsCur=Math.round(t*.4);
 KITS.rsCur=Math.min(Math.max(KITS.rsCur,KITS.rsZero+1),t)}
function rsSetFromX(clientX,which){const g=rsGeom();if(!g)return;
 const mm=Math.round((clientX-g.left)/g.ppmm);
 if(which==='zero')KITS.rsZero=Math.min(Math.max(0,mm),g.target-1);
 else KITS.rsCur=Math.min(Math.max(mm,KITS.rsZero+1),g.target);
 rulerPaintRs()}
function rsGrab(e,which){e.preventDefault();if(e.stopPropagation)e.stopPropagation();rsSetFromX(e.clientX,which);
 const mv=ev=>rsSetFromX(ev.clientX,which);
 const up=()=>{window.removeEventListener('pointermove',mv);window.removeEventListener('pointerup',up);
   toast(which==='zero'?('零点已移到 '+KITS.rsZero+' mm'):('读数 '+(KITS.rsCur-KITS.rsZero)+' mm'))};
 window.addEventListener('pointermove',mv);window.addEventListener('pointerup',up)}
function rsTapeDown(e){if(e.target.closest('#rsCursor,#rsZero'))return;rsGrab(e,'cur')}
function rsKey(e){const st=$('#rulerStage');if(!st||st.classList.contains('hidden'))return;
 if(e.key==='Escape'){rulerFsClose();return}
 if(e.key==='ArrowLeft'||e.key==='ArrowRight'){const d=e.key==='ArrowLeft'?-1:1;
  KITS.rsCur=Math.min(Math.max(KITS.rsCur+d,KITS.rsZero+1),rulerTargetMm());rulerPaintRs();e.preventDefault()}}
function rulerPaintRs(){const g=rsGeom();if(!g)return;
 const cur=$('#rsCursor'),z=$('#rsZero');if(!cur||!z)return;rsClamp();
 cur.style.left=Math.round(KITS.rsCur*g.ppmm)+'px';z.style.left=Math.round(KITS.rsZero*g.ppmm)+'px';
 const mm=KITS.rsCur-KITS.rsZero,dirLbl=(KITS.rulerDir||'long')==='long'?'长边':'短边';
 const big=$('#rsBig');if(big)big.textContent=(RULER_UNIT==='in')?((mm/25.4).toFixed(2)+' in'):(mm+' mm');
 const sp=$('#rulerSpan');if(sp)sp.textContent=dirLbl+' 游标 '+mm+' mm ≈ '+(mm/10).toFixed(1)+' cm';
 const zp=$('#rsZeroPos');if(zp)zp.textContent='零点 '+KITS.rsZero+' mm · 量程 '+g.target+' mm · 方向键微调 1mm';
 KIT_SHARE_TXT='尺子 · 游标读数 '+mm+' mm（'+dirLbl+' · 零点 '+KITS.rsZero+' mm）· 量程 '+g.target+' mm · 校准 '+(+KITS.cal).toFixed(3)+'×'}
function rulerDrawScale(){const host=$('#rsScale');if(!host)return;const g=rsGeom();if(!g)return;
 const target=g.target,cm=(KITS.rulerUnit||'cm')==='cm';let h='';
 if(cm){for(let i=0;i<=target;i++){const px=i*g.ppmm,major=i%10===0,mid=i%5===0;
   h+='<i style="left:'+px.toFixed(1)+'px;height:'+(major?'56px':mid?'34px':'18px')+'"></i>';
   if(major)h+='<b style="left:'+px.toFixed(1)+'px">'+(i/10)+'</b>'}}
 else{const n=Math.round(target/25.4*4);for(let i=0;i<=n;i++){const v=i*25.4/4;if(v>target)break;
   const px=v*g.ppmm,major=i%4===0,mid=i%2===0;
   h+='<i style="left:'+px.toFixed(1)+'px;height:'+(major?'56px':mid?'34px':'18px')+'"></i>';
   if(major)h+='<b style="left:'+px.toFixed(1)+'px">'+(i/4)+'</b>'}}
 host.style.width=(target*g.ppmm)+'px';host.innerHTML=h}

`;

const PROFILE_BLOCK = `        <button onclick="navTo('p-pstore')" class="w-full flex items-center gap-3 p-3.5 text-left border-t border-slate-100 dark:border-slate-800 active:bg-slate-50 dark:active:bg-slate-800/60">
          <span class="set-ic bg-slate-100 dark:bg-slate-800">🧩</span><div class="flex-1"><b class="text-sm">插件中心</b><div class="text-[11px] text-slate-400">大模块按需安装 · 更新 · 回滚</div></div>
          <span class="text-[10px] text-amber-500 font-bold mr-1">1 项可更新</span><span class="text-slate-300">›</span></button>`;

const EDITS = [
  { f: K, id: 'CSS 尺子舞台 + kit-tile', from: CSS_ANCHOR, to: CSS_ANCHOR + CSS_ADD },
  { f: K, id: 'HTML 尺子全屏舞台', from: HTML_ANCHOR, to: HTML_ANCHOR + HTML_ADD },
  { f: K, id: 'JS 尺子函数组插入', from: 'function rulerApplyBoot()', to: RS_FNS + 'function rulerApplyBoot()' },
  { f: K, id: 'JS rulerDraw 整段替换', block: ['function rulerDraw(){const box=', 'KIT_SHARE_TXT='], to: 'PLACEHOLDER_RULER' },
  { f: K, id: 'JS rulerApplyBoot 守卫', from: `function rulerApplyBoot(){if(!KITS.rulerDir)KITS.rulerDir='long';if(!KITS.rulerUnit)KITS.rulerUnit='cm';
 const a=$('#rDirLong'),b=$('#rUcm');if(!a)return;`,
    to: `function rulerApplyBoot(){if(!KITS.rulerDir)KITS.rulerDir='long';if(!KITS.rulerUnit)KITS.rulerUnit='cm';
 rsChips();const b=$('#rUcm');if(!b)return;` },
  { f: K, id: 'JS rulerDir 守卫', from: `function rulerDir(d){KITS.rulerDir=d;kitSave();$('#rDirLong').classList.toggle('on',d==='long');$('#rDirShort').classList.toggle('on',d==='short');`,
    to: `function rulerDir(d){KITS.rulerDir=d;kitSave();rsChips();const _a=$('#rDirLong');if(_a){_a.classList.toggle('on',d==='long');$('#rDirShort').classList.toggle('on',d==='short');}` },
  { f: K, id: 'JS rulerUnit 守卫', from: `function rulerUnit(u){RULER_UNIT=u;KITS.rulerUnit=u;kitSave();$('#rUcm').classList.toggle('on',u==='cm');$('#rUin').classList.toggle('on',u==='in');`,
    to: `function rulerUnit(u){RULER_UNIT=u;KITS.rulerUnit=u;kitSave();const _c=$('#rUcm');if(_c){_c.classList.toggle('on',u==='cm');$('#rUin').classList.toggle('on',u==='in')}rsChips();` },
  { f: K, id: 'JS rulerCalSet 同步舞台', from: `function rulerCalSet(v){KITS.cal=+v;kitSave();const s=$('#rulerCal');if(s)s.value=v;rulerDraw()}`,
    to: `function rulerCalSet(v){KITS.cal=+v;kitSave();const s=$('#rulerCal');if(s)s.value=v;const r=$('#rsCal');if(r)r.value=v;rulerDraw()}` },
  { f: K, id: 'JS rulerBank 同步舞台', from: ` KITS.cal=+v;kitSave();$('#rulerCal').value=v;rulerDraw();`,
    to: ` KITS.cal=+v;kitSave();const _rc=$('#rulerCal');if(_rc)_rc.value=v;const _rs=$('#rsCal');if(_rs)_rs.value=v;rulerDraw();` },
  { f: K, id: '尺子详情页改全屏入口 + 进屏即全屏', from: ` <div class="card !p-3 text-slate-700 dark:text-slate-300 mt-2 overflow-y-auto no-scrollbar" style="height:52vh" id="rulerBox"></div>
 <div class="mt-2 flex gap-2 items-center"><b id="rulerSpan" class="text-xs text-brand-500"></b><span class="ml-auto flex gap-2"><button class="mini-btn" onclick="rulerBank()">银行卡校准</button><button class="mini-btn" onclick="rulerCalSet(1)">重置 1.000</button></span></div>
\`,mount(){rulerApplyBoot();rulerDraw()}},`,
    to: ` <button class="mt-2 w-full py-4 rounded-2xl grad text-white text-[13px] font-extrabold active:scale-[.98] transition" onclick="rulerFsOpen()">全屏尺子 · 按住红线滑动读数 ›</button>
 <div class="card !p-3 text-slate-700 dark:text-slate-300 mt-2 overflow-y-auto no-scrollbar hidden" style="height:52vh" id="rulerBox"></div>
 <div class="mt-2 flex gap-2 items-center"><b class="text-xs text-brand-500">量程 <b id="rulerSpanCard"></b></b><span class="ml-auto flex gap-2"><button class="mini-btn" onclick="rulerBank()">银行卡校准</button><button class="mini-btn" onclick="rulerCalSet(1)">重置 1.000</button></span></div>
\`,mount(){rulerApplyBoot();rulerDraw();rulerFsOpen()}},` },
  { f: K, id: '网格 4 列 → 5 列', from: 'grid grid-cols-4 gap-3', to: 'grid grid-cols-5 gap-1.5', expect: 2 },
  { f: K, id: '工具卡紧凑化', from: `ks.map(k=>{const t=TOOL_REG[k];return \`<button class="card !p-2.5 flex flex-col items-center gap-1.5 active:scale-95 transition relative" onclick="kitOpen('\${k}')" oncontextmenu="event.preventDefault();kitToggleFav('\${k}')"><span class="absolute right-1 top-1 text-[9px] text-amber-400">\${KITS.fav.includes(k)?'★':''}</span><span class="w-9 h-9 rounded-xl bg-slate-100 dark:bg-slate-800 flex items-center justify-center text-lg">\${kitSvg(k)}</span><span class="text-[10px] font-bold">\${t.nm}</span><span class="text-[8px] text-slate-400">\${kitUsage(k)?kitUsage(k)+' 次':'未用过'}</span></button>\`}).join('')`,
    to: `ks.map(k=>{const t=TOOL_REG[k];return \`<button class="kit-tile" onclick="kitOpen('\${k}')" oncontextmenu="event.preventDefault();kitToggleFav('\${k}')"><span class="kt-fav">\${KITS.fav.includes(k)?'★':''}</span><span class="kt-ic">\${kitSvg(k)}</span><span class="kt-nm">\${t.nm}</span><span class="kt-sub">\${kitUsage(k)?kitUsage(k)+' 次':'未用过'}</span></button>\`}).join('')` },
  { f: K, id: '插件卡紧凑化', from: `ps.map(p=>\`<button class="card !p-2.5 flex flex-col items-center gap-1.5 active:scale-95 transition relative" onclick="plgUse('\${p.id}')"><span class="absolute right-1 top-1 vchip !text-[7px]">插件</span><span class="w-9 h-9 rounded-xl bg-slate-100 dark:bg-slate-800 flex items-center justify-center text-lg">\${plgIco(p)}</span><span class="text-[10px] font-bold truncate w-full">\${p.n}</span><span class="text-[8px] text-slate-400">沙箱 · v\${p.ver}</span></button>\`)`,
    to: `ps.map(p=>\`<button class="kit-tile" onclick="plgUse('\${p.id}')"><span class="kt-tag">插件</span><span class="kt-ic">\${plgIco(p)}</span><span class="kt-nm">\${p.n}</span><span class="kt-sub">v\${p.ver}</span></button>\`)` },
  { f: K, id: 'C5 底栏摘除插件栏位', from: `['p-tools','工具',''],['p-pstore','插件',''],`, to: `['p-tools','工具',''],` },
  { f: K, id: 'C5 我的页摘除插件中心行', block: ["<button onclick=\"navTo('p-pstore')\"", '1 项可更新</span><span class="text-slate-300">›</span></button>'], to: '' },
  { f: M, id: 'C5 底栏摘除插件栏位', from: `['p-tools','工具',''],['p-pstore','插件',''],`, to: `['p-tools','工具',''],` },
  { f: M, id: 'C5 我的页摘除插件中心行', block: ["<button onclick=\"navTo('p-pstore')\"", '1 项可更新</span><span class="text-slate-300">›</span></button>'], to: '' },
];

/* ---- 整段替换类锚点：按行边界从原文精确切片（文件混用 CRLF/LF，切片保证逐字节一致） ---- */
function blockByStart(f, startSub, endSub) {
  const raw = cache[f] || fs.readFileSync(path.resolve(f), 'utf8');
  const L = raw.split(/\r\n|\n/);
  const a = L.findIndex(l => l.includes(startSub));
  const b = L.findIndex((l, i) => i >= a && l.includes(endSub));
  if (a < 0 || b < 0 || b <= a) throw new Error('边界未找到：' + startSub + ' / ' + endSub);
  /* 逐行探测其后的行尾序列（兼容文件内 CRLF/LF 混用），原样拼回保证逐字节一致 */
  let acc = 0; const offs = [];
  for (let i = 0; i < L.length; i++) { offs.push(acc); acc += L[i].length; acc += raw.startsWith('\r\n', acc) ? 2 : 1; }
  return raw.slice(offs[a], offs[b] + L[b].length);
}
const RULER_DRAW_NEW = `function rulerEdgeMm(){const PXMM=3.78;
 const _pe=document.getElementById('phone')||document.documentElement,_pr=_pe.getBoundingClientRect(); /* 走查A1：screen.* 在部分 WebView/桌面壳恒为 0，改量手机框实际渲染尺寸 */
 const _ew=Math.round(_pr.width)||innerWidth,_eh=Math.round(_pr.height)||innerHeight;
 return {longMm:Math.round(Math.max(_ew,_eh)/PXMM),shortMm:Math.round(Math.min(_ew,_eh)/PXMM)};}
function rulerTargetMm(){const e=rulerEdgeMm();return (KITS.rulerDir||'long')==='long'?e.longMm:e.shortMm;}
/* 整条量程尺面已迁到全屏舞台（rsTape/rsScale）；页面内不再画 52vh 竖尺。 */
function rulerDraw(){rulerDrawScale();rulerPaintRs();
 const v=$('#rulerCalV');if(v)v.textContent=(+KITS.cal).toFixed(3)+'×';
 const v2=$('#rsCalV');if(v2)v2.textContent=(+KITS.cal).toFixed(3)+'×';
 const card=$('#rulerSpanCard');if(card)card.textContent=rulerTargetMm()+' mm';}`;

/* ---- 断言阶段（EOL 自适应） ---- */
let bad = 0;
for (const e of EDITS) {
  if (!cache[e.f]) { cache[e.f] = fs.readFileSync(path.resolve(e.f), 'utf8'); eol[e.f] = cache[e.f].includes('\r\n') ? '\r\n' : '\n'; }
  if (e.block) {
    e.from = blockByStart(e.f, e.block[0], e.block[1]);
    e._raw = true;
    if (e.to === 'PLACEHOLDER_RULER') e.to = RULER_DRAW_NEW;
  }
  const from = e._raw ? e.from : e.from.replace(/\n/g, eol[e.f]);
  const to = e._raw ? e.to.replace(/\n/g, eol[e.f]) : e.to.replace(/\n/g, eol[e.f]);
  const n = cache[e.f].split(from).length - 1;
  const want = e.expect || 1;
  if (n !== want) { console.error('FAIL ' + e.id + ' [' + e.f + '] 命中 ' + n + '（期望 ' + want + '）'); bad++; }
  else console.log('PASS ' + e.id + '  [' + e.f + ']');
  e._from = from; e._to = to;
}
if (bad) { console.error('!! ' + bad + ' 条不符 → 零写入退出'); process.exit(1); }

const out = {};
for (const e of EDITS) out[e.f] = (out[e.f] || cache[e.f]).split(e._from).join(e._to);
for (const f of Object.keys(out)) {
  const b0 = Buffer.byteLength(cache[f]), b1 = Buffer.byteLength(out[f]);
  if (b1 < b0 - 5000 || b1 > b0 + 60000) { console.error('!! ' + f + ' 体积异常 ' + b0 + ' → ' + b1 + ' → 零写入'); process.exit(2); }
  console.log('体积 ' + f + ' ' + b0 + ' → ' + b1 + '（+' + (b1 - b0) + '）');
}
if (!DRY) { for (const f of Object.keys(out)) fs.writeFileSync(path.resolve(f), out[f]); console.log('已写入：' + Object.keys(out).join(' , ')); }
else console.log('dry-run：未写入');
