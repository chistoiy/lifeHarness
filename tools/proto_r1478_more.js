// R14-7 补刀 + R14-8 原型先行：设置区剩余装饰 emoji 前缀摘除、交互教学文案清理。
// 用法：node tools/proto_r1478_more.js [--dry]
const fs = require('fs');
const P = 'prototype/index.html';
let s = fs.readFileSync(P, 'utf8');
const before = s.length;
const dry = process.argv.includes('--dry');
let hits = 0;
const misses = [];
function sub(one, many) {
  const n = s.split(one).length - 1;
  if (n === 0) { misses.push(one.slice(0, 46)); return; }
  s = s.split(one).join(many);
  hits += n;
}

// 1) 交互教学文案（与 R14-8 同族：点按/拖拽怎么用 = 靠自发探索，不写说明）
sub(
  '<div class="text-[10px] text-slate-400">🖐 长按拖拽 = 调整顺序 / 拖入其他父级换组 · 分类供 轴/块/日/周 四视图与时间账本共用</div>\n',
  '',
);
// 2) 块视图顶栏：状态读数保留，前缀 emoji 已在上一脚本处理；此处兜底断言无残留
if (/🖐 滑选/.test(s)) misses.push('块视图教学串残留');

// 3) 装饰 emoji 前缀 → 纯文字（按钮/链接/能力矩阵行/状态文案）
for (const [one, many] of [
  ['本地模式 · 无账号 🔒 · 已记录 55 天', '本地模式 · 无账号 · 已记录 55 天'],
  ['🔌 重新验证 / 测试新 Key', '重新验证 / 测试新 Key'],
  ['🛍 更多主题 ›', '更多主题 ›'],
  ['✅ 待办：自然语言速记 + AI 判象限', '待办：自然语言速记 + AI 判象限'],
  ['📔 日记：复盘生成 / KPT 草稿', '日记：复盘生成 / KPT 草稿'],
  ['📚 阅读：总结深化 / 目录 AI 补全', '阅读：总结深化 / 目录 AI 补全'],
  ['⚡ 收集箱：智能分流建议', '收集箱：智能分流建议'],
  ['📊 周报 AI 点评（只发聚合数据）', '周报 AI 点评（只发聚合数据）'],
  ['🤰 呵护：周期趋势解读', '呵护：周期趋势解读'],
  ['💰📦 记账/物品智能归类（V2）', '记账/物品智能归类（V2）'],
]) sub(one, many);

console.log('命中 =', hits, '| 未命中 =', misses.length ? misses.join(' || ') : '无');
console.log('体积：', before, '→', s.length, '（Δ', s.length - before, '）');
if (misses.length) { console.error('有未命中项，拒绝写出'); process.exit(1); }
if (s.length < before * 0.9) { console.error('体积异常缩水，拒绝写出'); process.exit(1); }
if (dry) { console.error('--dry 未写盘'); process.exit(1); }
fs.writeFileSync(P, s);
console.log('已写', P);
