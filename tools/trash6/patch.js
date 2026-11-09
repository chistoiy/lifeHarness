/* V1.57 待办垃圾箱 · 原型先行补丁（prototype/index.html 共享面）
 * 命中断言式：每处必须恰好命中 1 次，任一未命中整批不落盘；行尾自适应 CRLF/LF。
 * from/to 载荷由 grab.js + make_to.js 生成，勿手改 *_from.txt。
 * 用法：node tools/trash6/grab.js && node tools/trash6/make_to.js && node tools/trash6/patch.js
 */
const fs = require('fs');
const RD = (p) => fs.readFileSync(p, 'utf8');
const T = (n) => RD('tools/trash6/' + n);
const F = 'prototype/index.html';
const jobs = [];
const J = (from, to, tag) => jobs.push({ from, to, tag });

/* 数据与标题 */
J(T('d_from.txt'), T('d_to.txt'), 'D.trash 种子数据');
J(T('titles_from.txt'), T('titles_to.txt'), 'TITLES 子页标题');
/* 期限设置同源 */
J(T('rec_from.txt'), T('rec_to.txt'), '记录管理·回收站自动清理（补 id·文案纳入待办）');
J(T('cs_from.txt'), T('cs_to.txt'), 'cycleRecSet 改档广播');
/* 清单与导航接线 */
J(T('rt_from.txt'), T('rt_to.txt'), 'renderTodos 刷新入口读数');
J(T('sp_from.txt'), T('sp_to.txt'), 'setPage 离开时收起批量条');
/* 删除语义：硬删 → 进垃圾箱 + 模块 JS */
J(T('del_from.txt'), T('del_to.txt'), 'delTaskFromSheet 改软删 + 垃圾箱模块');
/* 三块 UI 载荷 */
J('    </section>\n\n    <!-- ===== P3 日程/日历 ===== -->\n', T('entry.html'), '待办页垃圾箱入口行');
J('    <!-- ===== P4b 阅读导入向导 ===== -->\n', T('section.html'), 'p-sub-todoTrash 子页');
J('  <!-- V1.29轮13：日记长按批量选择操作条（删除 / 取消·与笔记同款底部简约图标） -->\n', T('bar.html'), '批量操作条');
J('  <!-- ===== INS 全屏查看 ===== -->\n', T('sheet.html'), '彻底删除二次确认弹层');

/* ---------- 执行 ---------- */
let src = RD(F);
const eol = (src.match(/\r\n/g) || []).length >= (src.match(/(^|[^\r])\n/g) || []).length ? '\r\n' : '\n';
const fit = (t) => eol === '\r\n' ? t.replace(/\r?\n/g, '\r\n') : t;
let bad = 0;
for (const j of jobs) {
  j.from = fit(j.from); j.to = fit(j.to);
  const n = src.split(j.from).length - 1;
  if (n !== 1) { console.log('FAIL ' + j.tag + ' 命中 ' + n + ' 次（需恰好 1）'); bad++; }
}
if (bad) { console.log('== ' + bad + ' 处未命中，整批不落盘 =='); process.exit(1); }
const size0 = src.length;
for (const j of jobs) src = src.replace(j.from, j.to);
fs.writeFileSync(F, src);
console.log('OK  ' + F + ' ' + size0 + ' → ' + src.length + ' 字节（+' + (src.length - size0) + '）· ' + jobs.length + ' 处补丁落盘（行尾 ' + (eol === '\r\n' ? 'CRLF' : 'LF') + '）');
