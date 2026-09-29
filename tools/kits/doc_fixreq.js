/* 需求清单 V1.47 两条记录同步：引用改 §七 + 补验收轮2 结果
 * 用法：node tools/kits/doc_fixreq.js */
const fs = require('fs'), path = require('path');
const F = 'docs/需求清单.md';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';
const EDITS = [
  { from: '变更单-小工具专版共享面-20260927.md` §五。', to: '变更单-小工具专版共享面-20260927.md` §七。' },
  { from: '- **走查后仍挂**：A4 专版「全部功能」宫格待主原型 R14 系列定稿后回灌。**C5 已拍板并落地**（2026-09-29 验收轮2：底栏摘除「插件」栏位，插件入口只留小工具页拓展卡设置位）。不阻塞 Flutter 侧开工（写区已在变更单登记）。',
    to: '- **验收轮2（2026-09-29 · 用户截图三条）已落地**：B1 尺子改**全屏舞台 + 可滑动游标**（红色游标/紫色零点双把手，读数=游标−零点，1mm 吸附，进屏即全屏）；B2 工具卡改紧凑原语 `.kit-tile` 且首页改**全分类合并单网格**（实测每行 5 枚 · 单枚 94px）；B3 底栏栏目池摘除「插件」、插件中心入口只留小工具页拓展卡设置位（不进「我的」）。回归升至 **83/83**，明细见变更单 §八。\n- **走查后仍挂**：A4 专版「全部功能」宫格待主原型 R14 系列定稿后回灌。不阻塞 Flutter 侧开工（写区已在变更单登记）。' },
];
let src = raw;
for (const e of EDITS) {
  const from = e.from.replace(/\n/g, nl), to = e.to.replace(/\n/g, nl);
  const n = src.split(from).length - 1;
  if (n !== 1) { console.error('!! 命中 ' + n + '：' + e.from.slice(0, 40)); process.exit(1); }
  src = src.replace(from, to); console.log('PASS ' + e.from.slice(0, 28));
}
fs.writeFileSync(path.resolve(F), src);
console.log('已写入 ' + F);
