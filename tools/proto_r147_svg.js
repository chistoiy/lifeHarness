// R14-7 原型先行：设置区去 emoji（入口行图标换线性 SVG，标题/按钮装饰 emoji 前缀摘除）。
// 口径：UI 装饰 emoji 一律「简约线性 SVG 或纯文字」；用户数据自带图标（习惯/待办条目、
//       分类色点）与 ✓ ● 类文本符号不动。
// 用法：node tools/proto_r147_svg.js [--dry]   命中不足或体积异常缩水即拒绝写盘。
const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const before = s.length;
const dry = process.argv.includes('--dry');

// 24×24 · stroke 1.8 · currentColor · 与既有「日记天气」样板（!flex items-center justify-center）同构
const I = {
  cloud: '<path d="M7.2 18.5h9.3a3.6 3.6 0 0 0 .5-7.16 5.2 5.2 0 0 0-9.9-1.4 3.9 3.9 0 0 0 .1 8.56Z"/><path d="M12 15.4V9.2m0 0-2.1 2.1M12 9.2l2.1 2.1"/>',
  bell: '<path d="M6.6 16.2v-5.1a5.4 5.4 0 0 1 10.8 0v5.1l1.4 2H5.2l1.4-2Z"/><path d="M10.2 20.4a1.9 1.9 0 0 0 3.6 0"/>',
  chip: '<rect x="7.4" y="7.4" width="9.2" height="9.2" rx="2.2"/><path d="M10.4 3.8v3.6m3.2-3.6v3.6M10.4 16.6v3.6m3.2-3.6v3.6M3.8 10.4h3.6m-3.6 3.2h3.6M16.6 10.4h3.6m-3.6 3.2h3.6"/>',
  tag: '<path d="M4.6 11.6 11.6 4.6h7.8v7.8l-7 7a1.6 1.6 0 0 1-2.2 0l-5.6-5.6a1.6 1.6 0 0 1 0-2.2Z"/><circle cx="16" cy="8" r="1.2"/>',
  book: '<rect x="6.4" y="4" width="12.6" height="16" rx="2"/><path d="M9.8 4v16M6.4 8.6h3.4m-3.4 3.5h3.4m-3.4 3.5h3.4"/>',
  tools: '<path d="M14.8 4.4a4.2 4.2 0 0 0-5.2 5.4l-5 5a1.8 1.8 0 1 0 2.6 2.6l5-5a4.2 4.2 0 0 0 5.4-5.2l-2.5 2.5-2.3-.7-.7-2.3 2.7-2.3Z"/>',
  plugin: '<rect x="4.4" y="4.4" width="6.6" height="6.6" rx="1.6"/><rect x="13" y="4.4" width="6.6" height="6.6" rx="1.6"/><rect x="4.4" y="13" width="6.6" height="6.6" rx="1.6"/><path d="M16.3 13v6.6M13 16.3h6.6"/>',
  clipboard: '<rect x="5.6" y="5" width="12.8" height="15" rx="2"/><path d="M9.4 5V3.6h5.2V5M9.4 10.4h5.2m-5.2 3.4h5.2m-5.2 3.4h3.4"/>',
  palette: '<path d="M12 3.8c-4.5 0-8.2 3.5-8.2 7.9 0 4.3 3.3 7.5 7.4 7.5 1.3 0 2-.8 2-1.7 0-.6-.3-1-.7-1.4-.4-.4-.7-.8-.7-1.4 0-.9.8-1.6 1.8-1.6h1.5c2.5 0 4.4-1.9 4.4-4.3 0-3.3-3.4-5-7.5-5Z"/><circle cx="8.4" cy="10.6" r="1.1"/><circle cx="12" cy="8.2" r="1.1"/><circle cx="15.6" cy="10.6" r="1.1"/>',
  moon: '<path d="M20 14.6A8.6 8.6 0 0 1 9.4 4 8.6 8.6 0 1 0 20 14.6Z"/>',
  drop: '<path d="M12 3.8c3 4 5.4 6.3 5.4 9.3a5.4 5.4 0 0 1-10.8 0c0-3 2.4-5.3 5.4-9.3Z"/>',
};
const svg = (k) =>
  '<svg class="w-[16px] h-[16px]" fill="none" stroke="currentColor" stroke-width="1.8" ' +
  'viewBox="0 0 24 24" stroke-linecap="round" stroke-linejoin="round">' +
  I[k] +
  '</svg>';
const CENTER = ' !flex items-center justify-center';

let hits = 0;
const misses = [];
function sub(one, many) {
  const n = s.split(one).length - 1;
  if (n === 0) {
    misses.push(one.slice(0, 60));
    return;
  }
  s = s.split(one).join(many);
  hits += n;
}

// 1) 入口行四枚独特色底 chip
sub(
  'bg-emerald-100 dark:bg-emerald-500/15">☁️<',
  'bg-emerald-100 dark:bg-emerald-500/15' + CENTER + '">' + svg('cloud') + '<',
);
sub(
  'bg-brand-50 dark:bg-brand-500/15">🔔<',
  'bg-brand-50 dark:bg-brand-500/15' + CENTER + '">' + svg('bell') + '<',
);
sub(
  'bg-violet-50 dark:bg-violet-500/15">🤖<',
  'bg-violet-50 dark:bg-violet-500/15' + CENTER + '">' + svg('chip') + '<',
);
sub(
  'bg-orange-50 dark:bg-orange-500/15">🏷<',
  'bg-orange-50 dark:bg-orange-500/15' + CENTER + '">' + svg('tag') + '<',
);

// 2) slate 底色的入口行（按标题唯一定位）
for (const [em, title, key] of [
  ['📔', '记录管理', 'book'],
  ['🧰', '小工具合集', 'tools'],
  ['🧩', '插件中心', 'plugin'],
  ['🌙', '深色模式', 'moon'],
  ['🎨', '主题色', 'drop'],
]) {
  const a = `<span class="set-ic bg-slate-100 dark:bg-slate-800">${em}</span>`;
  const b = `<span class="set-ic bg-slate-100 dark:bg-slate-800${CENTER}">${svg(key)}</span>`;
  // 同串可能多行，连标题一起匹配保证唯一
  const withTitle = s.split(a).length - 1;
  const anchored = a + `<div class="flex-1"><b class="text-sm">${title}</b>`;
  const anchoredAlt = a + `<div class="flex-1"><b>${title}</b>`;
  if (s.includes(anchored)) sub(anchored, b + `<div class="flex-1"><b class="text-sm">${title}</b>`);
  else if (s.includes(anchoredAlt)) sub(anchoredAlt, b + `<div class="flex-1"><b>${title}</b>`);
  else misses.push('row:' + title + '(共 ' + withTitle + ' 处同串)');
}

// 3) 带副标题色板的入口行
for (const [em, title, key, cls] of [
  ['📋', '日志管理', 'clipboard', 'bg-purple-50 dark:bg-purple-500/15'],
  ['🎨', '外观', 'palette', 'bg-indigo-50 dark:bg-indigo-500/15'],
]) {
  const a = `<span class="set-ic ${cls}">${em}</span><div class="flex-1"><b class="text-sm">${title}</b>`;
  const b = `<span class="set-ic ${cls}${CENTER}">${svg(key)}</span><div class="flex-1"><b class="text-sm">${title}</b>`;
  sub(a, b);
}

// 4) 标题/按钮装饰 emoji 前缀 → 纯文字
for (const t of [
  '🧭 底部导航栏自定义', '🔄 WebDAV 配置', '💾 本地备份', '🔐 加密设置',
  '🕘 同步历史', '📅 日程与任务提醒', '📔 日记复盘', '⚡ 收集箱清理',
  '🔁 习惯提醒', '⛔ 免打扰时段', '🧩 服务商管理', '🔑 Key 配置',
  '🤖 AI 总开关', '📊 AI 使用记录', '🧪 提示词管理', '🎨 主题风格',
  '🧩 主页编排直达（或长按卡片）›', '🔑 修改备份口令', '⚙️ 通用',
]) {
  const plain = t.replace(/^[^\s]+\s/, '');
  if (s.includes('>' + t)) sub('>' + t, '>' + plain);
  else if (s.includes(t)) sub(t, plain);
  else misses.push('strip:' + t);
}

console.log('命中处数 =', hits, '| 未命中 =', misses.length ? misses.join(' || ') : '无');
console.log('体积：', before, '→', s.length, '（Δ', s.length - before, '）');
if (misses.length) { console.error('有未命中项，拒绝写出'); process.exit(1); }
if (s.length < before * 0.9) { console.error('体积异常缩水，拒绝写出'); process.exit(1); }
if (dry) { console.error('--dry 未写盘'); process.exit(1); }
fs.writeFileSync(P, s);
console.log('已写', P);
