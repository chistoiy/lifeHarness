/* 首页网格改「全分类合并单网格」：5 枚/行真正成立；分类信息留在筛选 chips 上
 * 用法：node tools/kits/patch_v147round8.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const F = 'prototype/index-kits.html';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';
const L = raw.split(/\r\n|\n/);
const ia = L.findIndex(l => l.includes('function kitRenderHome()'));
const ib = L.findIndex((l, i) => i > ia && l.includes("function ps0(){"));
if (ia < 0 || ib < 0) { console.error('!! 边界未找到', ia, ib); process.exit(1); }
const B = '`';
const NEW = [
  "function kitRenderHome(){if(!$('#kitCatChips'))return;",
  " renderKitHeroSlots();renderKitChips();renderKitFavRow();renderKitRecentStrip();",
  " const q=($('#kitSearch')&&$('#kitSearch').value.trim().toLowerCase())||'';",
  " /* V1.47 验收轮2：全分类合并成单一网格，每行稳定 5 枚；分类归属看筛选 chips */",
  " const items=[];",
  " TOOL_CATS.forEach(c=>{if(KITS.cat&&c[0]!==KITS.cat)return;",
  "  c[1].forEach(k=>{if(KITS.hidden.includes(k))return;",
  "   if(q&&!(kitT(k)+' '+c[0]).toLowerCase().includes(q))return;",
  "   const t=TOOL_REG[k];",
  "   items.push(`<button class=\"kit-tile\" onclick=\"kitOpen('${k}')\" oncontextmenu=\"event.preventDefault();kitToggleFav('${k}')\"><span class=\"kt-fav\">${KITS.fav.includes(k)?'★':''}</span><span class=\"kt-ic\">${kitSvg(k)}</span><span class=\"kt-nm\">${t.nm}</span><span class=\"kt-sub\">${kitUsage(k)?kitUsage(k)+' 次':'未用过'}</span></button>`)});});",
  " const ps=(!KITS.cat||KITS.cat==='拓展')?PLUGINS.filter(p=>p.en).filter(p=>!q||p.n.toLowerCase().includes(q)):[];",
  " ps.forEach(p=>items.push(`<button class=\"kit-tile\" onclick=\"plgUse('${p.id}')\"><span class=\"kt-tag\">插件</span><span class=\"kt-ic\">${plgIco(p)}</span><span class=\"kt-nm\">${p.n}</span><span class=\"kt-sub\">v${p.ver}</span></button>`));",
  " $('#toolGrid').innerHTML=`<div class=\"kgrp text-xs font-extrabold text-slate-500 mb-2\">${KITS.cat||'全部工具'}<span class=\"text-[9px] text-slate-400 ml-1\">${items.length}</span></div><div class=\"kgrid\">`+items.join('')+`</div>`;",
  " const e=$('#kitEmpty');if(e)e.classList.toggle('hidden',items.length>0)}",
];
const out = L.slice(0, ia).concat(NEW.join('\n').split('\n')).concat(L.slice(ib + 1)).join(nl);
const b0 = Buffer.byteLength(raw), b1 = Buffer.byteLength(out);
if (b1 < b0 - 2000 || b1 > b0 + 2000) { console.error('!! 体积异常 ' + b0 + ' → ' + b1 + '，零写入'); process.exit(2); }
console.log('替换第 ' + (ia + 1) + '-' + (ib + 1) + ' 行 · 体积 ' + b0 + ' → ' + b1);
if (!DRY) { fs.writeFileSync(path.resolve(F), out); console.log('已写入 ' + F); } else console.log('dry-run');
