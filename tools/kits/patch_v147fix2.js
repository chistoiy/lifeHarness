/* 二轮修正：A1 改量手机框实际尺寸（#phone）· A6-5 补随机数历史首帧渲染
 * 依赖一轮已落地；用法：node tools/kits/patch_v147fix2.js [--dry] */
const fs = require('fs'), path = require('path');
const FILE = path.resolve('prototype/index-kits.html');
const DRY = process.argv.includes('--dry');
const before = fs.readFileSync(FILE, 'utf8');

const EDITS = [
  {
    id: 'A1(二) 尺面按手机框实测边长换算',
    from: "const _ew=screen.width||window.outerWidth||innerWidth,_eh=screen.height||window.outerHeight||innerHeight; /* 走查A1：部分 WebView/桌面壳里 screen.* 恒为 0，回落窗口尺寸 */\n const longMm=Math.round(Math.max(_ew,_eh)/PXMM),shortMm=Math.round(Math.min(_ew,_eh)/PXMM);",
    to: "const _pe=document.getElementById('phone')||document.documentElement,_pr=_pe.getBoundingClientRect(); /* 走查A1：screen.* 在部分 WebView/桌面壳恒为 0，改量手机框实际渲染尺寸 */\n const _ew=Math.round(_pr.width)||innerWidth,_eh=Math.round(_pr.height)||innerHeight;\n const longMm=Math.round(Math.max(_ew,_eh)/PXMM),shortMm=Math.round(Math.min(_ew,_eh)/PXMM);",
  },
  {
    id: 'A6-5(二) 随机数历史首帧渲染',
    from: " t.mount&&t.mount();if(curPage==='p-toolDetail')$('#pageTitle').textContent=t.nm}",
    to: " if(k==='rand')randHistRender(); /* 走查A6：打开时不渲染，空态引导文案不显示 */\n t.mount&&t.mount();if(curPage==='p-toolDetail')$('#pageTitle').textContent=t.nm}",
  },
];

let src = before;
for (const e of EDITS) {
  const n = src.split(e.from).length - 1;
  if (n !== 1) { console.error(`!! ${e.id}: 命中 ${n} 次，零写入`); process.exit(1); }
  src = src.replace(e.from, e.to);
  console.log('PASS ' + e.id);
}
const b0 = Buffer.byteLength(before), b1 = Buffer.byteLength(src);
if (b1 < b0 - 400 || b1 > b0 + 4000) { console.error(`!! 体积异常 ${b0} → ${b1}，零写入`); process.exit(2); }
console.log(`体积 ${b0} → ${b1}（+${b1 - b0}）`);
if (!DRY) { fs.writeFileSync(FILE, src); console.log('已写入'); } else console.log('dry-run：未写入');
