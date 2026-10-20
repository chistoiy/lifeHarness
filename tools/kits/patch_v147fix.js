/* V1.47 逐屏走查修复批 A1/A2/A3/A5/A6 · 带命中断言与体积校验
 * 用法：node tools/kits/patch_v147fix.js [--dry] */
const fs = require('fs');
const path = require('path');
const FILE = path.resolve('prototype/index-kits.html');
const DRY = process.argv.includes('--dry');
const before = fs.readFileSync(FILE, 'utf8');
let bytes0 = Buffer.byteLength(before);

const EDITS = [
  {
    id: 'A1 尺子取边长回落 innerWidth/outerWidth',
    from: "const longMm=Math.round(Math.max(screen.width,screen.height)/PXMM),shortMm=Math.round(Math.min(screen.width,screen.height)/PXMM);",
    to: "const _ew=screen.width||window.outerWidth||innerWidth,_eh=screen.height||window.outerHeight||innerHeight; /* 走查A1：部分 WebView/桌面壳里 screen.* 恒为 0，回落窗口尺寸 */\n const longMm=Math.round(Math.max(_ew,_eh)/PXMM),shortMm=Math.round(Math.min(_ew,_eh)/PXMM);",
  },
  { id: 'A2-1 拓展设置去 ⚙️', from: '<div class="row-title">⚙️ 拓展设置</div>', to: '<div class="row-title">拓展设置</div>' },
  {
    id: 'A2-2 AI 验证 CORS 说明去 ⚠️',
    from: 'anthropic-version）。⚠️ 浏览器原型环境下',
    to: 'anthropic-version）。浏览器原型环境下',
  },
  { id: 'A2-3 模拟请求去装饰符号', rx: /<div style="color:#94a3b8">.[\uFE0F]?\s?模拟请求中…<\/div>/, to: '<div style="color:#94a3b8">模拟请求中…</div>' },
  { id: 'A3 详情指标口径统一为已用次数', from: '<br>打开次数</div>', to: '<br>已用次数</div>' },
  { id: 'A5 入口文案 11 → 13 个本地工具', from: '11 个本地工具 · 插件拓展', to: '13 个本地工具 · 插件拓展' },
  {
    id: 'A6-1 Base64 留痕体积可读化 + 空文件归因',
    from: '<span class="text-slate-400">${(x.size/1024).toFixed(0)}KB → ${(x.len/1024).toFixed(0)}KB</span>',
    to: '<span class="text-slate-400">${kitKB(x.size)} → ${kitKB(x.len)}${x.size===0?\' · 空文件\':\'\'}</span>',
  },
  {
    id: 'A6-2 图片压缩读数同口径',
    from: 'KIT_SHARE_TXT=`图片压缩 ${im.width}×${im.height} ${(size/1024).toFixed(0)}KB → ${cv.width}×${cv.height} ${(b.size/1024).toFixed(0)}KB · −${pct}%`;',
    to: 'KIT_SHARE_TXT=`图片压缩 ${im.width}×${im.height} ${kitKB(size)} → ${cv.width}×${cv.height} ${kitKB(b.size)} · −${pct}%`;',
  },
  {
    id: 'A6-3 体积格式化原语',
    from: "function b64RecentRender(){const el=$('#b64RecentRow');if(!el)return;const L=KITS.b64Recent||[];",
    to: "function kitKB(n){return n<1024?n+'B':(n/1024).toFixed(n<10240?1:0)+'KB'}\nfunction b64RecentRender(){const el=$('#b64RecentRow');if(!el)return;const L=KITS.b64Recent||[];",
  },
  {
    id: 'A6-4 Base64 空态引导',
    from: "'<div class=\"text-[10px] text-slate-400\">尚无转换记录</div>'}",
    to: "'<div class=\"text-[10px] text-slate-400\">尚无转换记录 · 选图或粘贴文本后即留痕</div>'}",
  },
  {
    id: 'A6-6 Base64 操作记录空态引导',
    from: "${x.ok?'✔':'✖'}</b></div>`).join(''):'尚无记录'}",
    to: "${x.ok?'✔':'✖'}</b></div>`).join(''):'尚无操作记录 · 编码/解码后自动留痕'}",
  },
  {
    id: 'A6-5 随机数空态引导',
    from: "${x.v.join(' · ')}</b></div>`).join(''):'尚无记录'}",
    to: "${x.v.join(' · ')}</b></div>`).join(''):'还没有生成记录 · 点「生成」即留痕'}",
  },
];

const hits = [];
let src = before;
for (const e of EDITS) {
  const n = e.rx ? (src.match(new RegExp(e.rx.source, 'g')) || []).length : src.split(e.from).length - 1;
  if (n !== 1) {
    hits.push(`FAIL ${e.id}  命中 ${n} 次（期望 1）`);
    console.error(`!! ${e.id}: 命中 ${n} 次，中止且零写入`);
    process.exit(1);
  }
  src = e.rx ? src.replace(e.rx, e.to) : src.replace(e.from, e.to);
  hits.push(`PASS ${e.id}`);
}
const bytes1 = Buffer.byteLength(src);
if (bytes1 < bytes0 - 400 || bytes1 > bytes0 + 4000) {
  console.error(`!! 体积异常 ${bytes0} → ${bytes1}，中止且零写入`);
  process.exit(2);
}
console.log(hits.join('\n'));
console.log(`体积 ${bytes0} → ${bytes1}（+${bytes1 - bytes0}）`);
if (!DRY) {
  fs.writeFileSync(FILE, src);
  console.log('已写入 ' + FILE);
} else console.log('dry-run：未写入');
