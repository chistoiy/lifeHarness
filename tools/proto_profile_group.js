/* 「我的」页一级屏 · 结构重排（批B · 2026-10-11）
 *
 * 现状（原型 p-profile）：一张 8 行大组卡 + 外观单行卡 + 底栏自定义卡 + 关于卡，
 * 全程无分组小标题，且「维护类」（日志/回收站/图片清理）与「配置类」同卡平铺。
 *
 * 改法（壳内既有分组语言 `text-xs font-extrabold text-slate-400 mt-4 mb-1.5`，
 * 与 p-sub-recmg 的「日记/笔记/阅读/影音游」同一枚样式，零新增样式）：
 *   ① 原 8 行大组卡拆成三段（每组内部序＝原型原序的连续子序列，不打乱相对序）；
 *   ② 每组首行去掉 `border-t`（组内首行上方不该有分隔线）；
 *   ③ 插入四枚分组标题：记录 / 数据与提醒 / 外观与交互 / 系统与维护。
 * 用法：node tools/proto_profile_group.js [--dry]
 */
const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const before = s.length;
const dry = process.argv.includes('--dry');

const START = '      <div class="card mt-4 !p-0 overflow-hidden">\n' +
              '        <button onclick="navTo(\'p-sub-data\')"';
const END = '      <!-- V1.27：主题风格/深色/主题色/字号 收进「外观」二级页 -->';
const ABOUT = '      <div class="card mt-4 text-[11px] text-slate-400 leading-6">';
const LABEL = c => '      <div class="text-xs font-extrabold text-slate-400 mt-4 mb-1.5">' + c + '</div>';
const CARD_OPEN = '      <div class="card !p-0 overflow-hidden">';
const CARD_CLOSE = '      </div>';

const i = s.indexOf(START);
if (i < 0) throw new Error('组卡起点锚点未命中');
if (s.indexOf(START, i + 1) >= 0) throw new Error('组卡起点锚点不唯一');
const j = s.indexOf(END, i);
if (j < 0) throw new Error('外观卡注释锚点未命中');
const k = s.indexOf(ABOUT, j);
if (k < 0) throw new Error('关于卡锚点未命中');

/* ── 切出原组卡段落，按 <button 切行块 ── */
const segLines = s.slice(i, j).split('\n');
if (segLines[0] !== '      <div class="card mt-4 !p-0 overflow-hidden">') throw new Error('段落首行不符：' + segLines[0]);
if (segLines[segLines.length - 1] !== '') throw new Error('段落尾行不符：' + JSON.stringify(segLines[segLines.length - 1]));
const inner = segLines.slice(1, segLines.length - 2); // 去首行卡开、尾行空行与 </div>
if (inner[inner.length - 1] !== CARD_CLOSE) throw new Error('段落未见组卡闭合：' + inner[inner.length - 1]);
const rowsRaw = inner.slice(0, -1);

const blocks = [];
let cur = [];
for (const line of rowsRaw) {
  if (cur.length && line.startsWith('        <button ')) { blocks.push(cur); cur = []; }
  cur.push(line);
}
if (cur.length) blocks.push(cur);

/* ── 断言：8 块，且导航目标与预期一一对应 ── */
const wantTitles = ['数据与同步', '提醒通知', 'AI 增强', '分类管理', '记录管理', '日志管理', '回收站', '图片存储清理'];
if (blocks.length !== wantTitles.length) throw new Error('行块数不符：' + blocks.length);
blocks.forEach((b, n) => {
  const txt = b.join('\n');
  if (!txt.includes('>' + wantTitles[n] + '</b>')) {
    throw new Error('第 ' + (n + 1) + ' 块标题不符（期望 ' + wantTitles[n] + '）：' + txt.slice(0, 120));
  }
});

/* 组内首行去 border-t（组首上方不留分隔线） */
const stripTop = b => {
  const first = b[0].replace('text-left border-t border-slate-100 dark:border-slate-800 active:', 'text-left active:');
  return [first, ...b.slice(1)];
};

const blockOf = t => blocks[wantTitles.indexOf(t)];
const group = (titles) => [CARD_OPEN,
  ...stripTop(blockOf(titles[0])),
  ...titles.slice(1).flatMap(t => blockOf(t)),
  CARD_CLOSE].join('\n');

const newSeg = [
  LABEL('记录'),
  group(['分类管理', '记录管理']),
  '',
  LABEL('数据与提醒'),
  group(['数据与同步', '提醒通知', 'AI 增强']),
  '',
  LABEL('外观与交互'),
  '',            // 其后紧跟原「外观卡」与「底栏自定义卡」
].join('\n');

/* 「系统与维护」组（运行日志/回收站/图片存储清理）插在关于卡之前 */
const sysSeg = [
  LABEL('系统与维护'),
  group(['日志管理', '回收站', '图片存储清理']),
  '',
  '',
].join('\n');

s = s.slice(0, i) + newSeg + '\n' + s.slice(j, k) + sysSeg + s.slice(k);

const after = s.length;
console.log('[proto_profile_group] ' + (dry ? 'DRY ' : '') + 'OK  长度 ' + before + ' → ' + after + '（Δ' + (after - before) + '）');
if (dry) {
  const p = s.indexOf(LABEL('记录'));
  console.log('----- 新段落预览 -----');
  console.log(s.slice(p, p + 1200).split('\n').map(l => l.length > 150 ? l.slice(0, 150) + ' …' : l).join('\n'));
} else {
  fs.writeFileSync(P, s);
}
