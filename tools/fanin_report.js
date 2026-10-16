// import 扇入报数（⑲ 判据③ 口径重定 · 2026-10-16）
//
// 用途：判据③ 口径从「模块总行数」改为「单文件行数 ＋ 单模块 import 扇入」后，
// 扇入这一维需要一个可复跑的读数工具。只读·纯扫·不改任何代码，不判红闸
// （产品 2026-10-16 22:06 拍板「先只报数不设闸」）。
//
// 为什么量扇入而不量总量：上下文按**文件**加载，不按模块加载。改一个功能时，
// 要打开的是「符号定位命中到的几个文件」，不是整个模块。总行数高但拆得细，
// 单次触碰量反而小（⑲ 工单 §1.1 实测：3.0%~9.0%）。
//
// 用法：
//   node tools/fanin_report.js             # 全仓清单 + 分布统计
//   node tools/fanin_report.js --top 20    # 只看 import 数最多的 N 件（默认 20）
//   node tools/fanin_report.js --json      # 机器可读输出（供文档引用）
//
// 口径说明：
//   · 「扇入」＝该文件 import 语句的条数（依赖广度），不是被引用的次数（扇出）。
//   · 统计对象＝lib/**/*.dart 里至少有 1 条 import 的文件。
//   · `main.dart` / `core/router/app_router.dart` 属入口与路由的结构性集中，
//     高扇入是设计使然，不是病态；报数里单独标注（STRUCTURAL）便于与真该治区分。

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const LIB = path.join(ROOT, 'lib');
const LINE_BUDGET = 1200; // 与 test/size_budget_test.dart 的 lineBudget 同口径

// 结构集中：高扇入属设计使然，不计入「待治」
const STRUCTURAL = new Set(['main.dart', 'core/router/app_router.dart']);

const argv = process.argv.slice(2);
const TOP_N = (() => {
  const i = argv.indexOf('--top');
  return i >= 0 ? parseInt(argv[i + 1], 10) || 20 : 20;
})();
const AS_JSON = argv.includes('--json');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

function rel(f) {
  return path.relative(ROOT, f).split(path.sep).join('/');
}

// 单个 dart 文件的 import 条数（只数真正的 import 语句，不含 export/part）
function faninOf(file) {
  const src = fs.readFileSync(file, 'utf8');
  const m = src.match(/^import\s+['"][^'"]+['"]/gm);
  return m ? m.length : 0;
}

function linesOf(file) {
  return fs.readFileSync(file, 'utf8').split('\n').length;
}

const files = walk(LIB);
const rows = [];
for (const f of files) {
  const n = faninOf(f);
  if (n === 0) continue;
  const r = rel(f);
  rows.push({
    path: r,
    fanin: n,
    lines: linesOf(f),
    structural: STRUCTURAL.has(r.replace(/^lib\//, '')),
    overLineBudget: linesOf(f) > LINE_BUDGET,
  });
}

rows.sort((a, b) => b.fanin - a.fanin || a.path.localeCompare(b.path));
const vals = rows.map((r) => r.fanin).sort((a, b) => a - b);
const pick = (q) => vals[Math.min(vals.length - 1, Math.floor(vals.length * q))];

const symptomatic = rows.filter((r) => !r.structural && r.fanin > 30);
const overLine = rows.filter((r) => r.overLineBudget);

if (AS_JSON) {
  process.stdout.write(
    JSON.stringify(
      {
        total: rows.length,
        stats: {
          median: pick(0.5),
          mean: +(vals.reduce((a, b) => a + b, 0) / vals.length).toFixed(1),
          p90: pick(0.9),
          p99: pick(0.99),
          max: vals[vals.length - 1],
        },
        over30: symptomatic.map((r) => `${r.path}(${r.fanin})`),
        structural: rows.filter((r) => r.structural).map((r) => `${r.path}(${r.fanin})`),
        overLineBudget: overLine.map((r) => `${r.path}(${r.lines})`),
        top: rows.slice(0, TOP_N).map((r) => `${r.path}(${r.fanin})`),
      },
      null,
      2
    ) + '\n'
  );
  process.exit(0);
}

const pad = (s, n) => {
  // 中文按 2 列宽算，表格才不会歪
  let w = 0;
  for (const ch of s) w += /[一-龥　-〿＀-￯]/.test(ch) ? 2 : 1;
  return s + ' '.repeat(Math.max(1, n - w));
};

console.log(`import 扇入报数 · 口径＝单文件 import 语句条数 · 行线 ${LINE_BUDGET}（与 size_budget_test 同口径）`);
console.log(`统计对象：lib/**/*.dart 中有 import 的文件 ${rows.length} 个\n`);

console.log('分布：');
console.log(`  中位 ${pick(0.5)}  平均 ${(vals.reduce((a, b) => a + b, 0) / vals.length).toFixed(1)}  P90 ${pick(0.9)}  P99 ${pick(0.99)}  最大 ${vals[vals.length - 1]}`);
for (const t of [20, 30, 40, 50]) {
  console.log(`  扇入 > ${String(t).padStart(2)} 的文件：${rows.filter((r) => r.fanin > t).length} 个`);
}

console.log(`\n扇入 TOP ${TOP_N}：`);
for (const r of rows.slice(0, TOP_N)) {
  const tags = [r.structural ? 'STRUCTURAL' : '', r.overLineBudget ? `超行线${r.lines}` : '']
    .filter(Boolean)
    .join(' ');
  console.log(`  ${pad(String(r.fanin), 4)} ${pad(r.path, 62)} ${tags}`);
}

console.log('\n结构性集中（高扇入属设计使然，不计待治）：');
for (const r of rows.filter((r) => r.structural)) console.log(`  ${pad(String(r.fanin), 4)} ${r.path}`);

console.log('\n待治（非结构性且扇入 > 30）：');
if (symptomatic.length === 0) console.log('  无');
else for (const r of symptomatic) console.log(`  ${pad(String(r.fanin), 4)} ${r.path}（${r.lines} 行）`);

console.log(`\n超 ${LINE_BUDGET} 行线的文件：${overLine.length} 个`);
for (const r of overLine) console.log(`  ${pad(String(r.lines), 5)} ${r.path}（扇入 ${r.fanin}）`);
console.log('\n注：本报数只读不判红。阈值与是否设闸属产品决策（⑲ 工单 §2.1）。');
