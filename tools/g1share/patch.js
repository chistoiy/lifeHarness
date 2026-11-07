/* G1 #2 分享长图包 · 原型先行补丁
 * 命中断言式：每处必须命中且只命中 1 次，任一未命中则整批不落盘。
 * 含 `${}` / \' 的块走 txt 载荷文件（命令行拼串会被 shell 吞），用法见 grab_review.js。
 * 改前基线 = 三文件 git 干净态（已提交），回滚用 git checkout -- <file>。
 * 用法：node tools/g1share/patch.js
 */
const fs = require('fs');
const RD = (p) => fs.readFileSync(p, 'utf8');
const P = {
  day: 'prototype/index-day_aim__goods.html',
  ledger: 'prototype/index-ledger.html',
  habit: 'prototype/index_habitcheck.html',
};
const jobs = [];
const J = (file, from, to, tag) => jobs.push({ file, from, to, tag });
const F = (file, fromPath, toPath, tag) => J(file, RD(fromPath), RD(toPath), tag);

/* ---------- A. 日子/物品/目标专版：四站接进同一预览弹层 ---------- */
J(P.day,
  `<button class="mini-btn" onclick="toast('统计卡已生成分享长图（模拟）')">⤴ 分享</button>`,
  `<button class="mini-btn" onclick="scOpen('stats')">⤴ 分享</button>`, 'day·统计卡按钮');
J(P.day,
  `onclick="toast('决算长图已生成（分享卡片 · 模拟）')">⤴ 分享决算卡片`,
  `onclick="scOpen('settle')">⤴ 分享决算卡片`, 'day·决算卡按钮');
J(P.day,
  `onclick="toast('倒数日分享卡已生成（模拟）')">⤴ 分享卡`,
  `onclick="scOpen('day')">⤴ 分享卡`, 'day·倒数日按钮');
F(P.day, 'tools/g1share/day_review_from.txt', 'tools/g1share/day_review_to.txt', 'day·复盘卡按钮');
J(P.day,
  '  <!-- ===== INS 全屏查看 ===== -->\n',
  RD('tools/g1share/day_sheet.html'), 'day·预览弹层');
J(P.day,
  '/* ================= 全局搜索 ================= */\n',
  RD('tools/g1share/day_js.js'), 'day·分享卡 JS');

/* ---------- B. 记账专版：年度分享图有预览与真产物回执 ---------- */
J(P.ledger,
  `onclick="toast('已生成年度分享图（模拟）')">生成分享图`,
  `onclick="yrShareOpen()">生成分享图`, 'ledger·生成分享图');
J(P.ledger,
  '  <!-- ===== INS 全屏查看 ===== -->\n',
  RD('tools/g1share/ledger_sheet.html'), 'ledger·预览弹层');
J(P.ledger,
  '/* ======================= L5 预算中心 ======================= */\n',
  RD('tools/g1share/ledger_js.js') + '/* ======================= L5 预算中心 ======================= */\n', 'ledger·年度长图 JS');

/* ---------- C. 习惯专版：保存图片＝落盘回执（不再是相册模拟） ---------- */
J(P.habit,
  `onclick="toast('已保存到相册（模拟）')">保存图片`,
  `onclick="hbShareSave()">保存图片`, 'habit·保存图片');
J(P.habit,
  ` else toast('当前环境不支持剪贴板 · 请手动截图')}`,
  ` else toast('当前环境不支持剪贴板 · 请手动截图')}
/* 保存图片＝真实落盘回执（Flutter 侧 RepaintBoundary → 应用目录 share/<名>.png·口径同书单长图） */
function hbShareSave(){const dim=hsDim,off=hsOffGet(dim);
 toast('分享长图已保存：share/'+hbBaseTxt(dim,off)+'打卡报告.png')}`, 'habit·落盘回执');

/* ---------- 执行：先全量校验命中数，再统一写盘 ----------
 * 行尾自适应：本仓库 core.autocrlf=true，checkout 出来的工作区是 CRLF，
 * 而载荷 txt/js 文件写的是 LF。读盘后按主导行尾把 from/to 的 \n 归一，避免 0 命中。 */
const src = {};
for (const j of jobs) src[j.file] = src[j.file] || RD(j.file);
const eolOf = (s) => ((s.match(/\r\n/g) || []).length >= (s.match(/(^|[^\r])\n/g) || []).length ? '\r\n' : '\n');
const eol = {};
for (const f of Object.keys(src)) eol[f] = eolOf(src[f]);
const fit = (j, txt) => eol[j.file] === '\r\n' ? txt.replace(/\r?\n/g, '\r\n') : txt;
let bad = 0;
for (const j of jobs) {
  j.from = fit(j, j.from); j.to = fit(j, j.to);
  const n = src[j.file].split(j.from).length - 1;
  if (n !== 1) { console.log('FAIL ' + j.tag + ' 命中 ' + n + ' 次（需恰好 1）· 行尾按 ' + (eol[j.file] === '\r\n' ? 'CRLF' : 'LF') + ' 匹配'); bad++; }
  if (src[j.file].indexOf(j.to) >= 0 && j.from !== j.to) console.log('WARN ' + j.tag + '：目标文本已存在，可能重复打补丁');
}
if (bad) { console.log('== ' + bad + ' 处未命中，整批不落盘 =='); process.exit(1); }
const size0 = {};
for (const f of Object.values(P)) size0[f] = src[f].length;
for (const j of jobs) src[j.file] = src[j.file].replace(j.from, j.to);
for (const f of Object.values(P)) {
  fs.writeFileSync(f, src[f]);
  console.log('OK  ' + f + ' ' + size0[f] + ' → ' + src[f].length + ' 字节（+' + (src[f].length - size0[f]) + '）');
}
console.log('== ' + jobs.length + ' 处补丁全部落盘 ==');
