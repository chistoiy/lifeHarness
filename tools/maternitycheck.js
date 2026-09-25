const fs = require('fs');
const P = 'D:/dev_workplace/flutter_te/lifeHarness/prototype/index-maternity_bady.html';
const h = fs.readFileSync(P, 'utf8');
let errs = [];

// 1) 内联脚本语法检查
const scripts = [...h.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const allJs = scripts.join('\n;\n');
scripts.forEach((s, i) => { try { new Function(s); } catch (e) { errs.push('SYNTAX script#' + i + ': ' + e.message); } });

// 2) id 唯一性抽查（新加的关键 id）
const ids = [...h.matchAll(/id="([\w-]+)"/g)].map(m => m[1]);
const dup = ids.filter((x, i) => ids.indexOf(x) !== i);
const BASE_KNOWN_DUP = ['pIn1']; // 底稿 index.html 既有重复 id，非本批引入
const dupNew = [...new Set(dup)].filter(x => !BASE_KNOWN_DUP.includes(x));
if (dupNew.length) errs.push('DUP-ID: ' + dupNew.join(','));

// 3) onclick/oninput 里调用的函数必须存在（顶层 function 或 const 箭头）；剔除字符串字面量避免误报
const handlersRaw = [...h.matchAll(/\son\w+="([^"]*)"/g)].map(m => m[1]).join('\n');
const handlers = handlersRaw.replace(/'[^']*'/g, "''");
const declared = new Set([...allJs.matchAll(/function\s+([A-Za-z_$][\w$]*)/g)].map(m => m[1])
  .concat([...allJs.matchAll(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/g)].map(m => m[1])));
const BUILTIN = new Set(['if', 'for', 'while', 'switch', 'return', 'String', 'Number', 'Math', 'Date', 'JSON', 'Array', 'Object', 'Boolean', 'parseInt', 'parseFloat', 'isNaN', 'setTimeout', 'setInterval', 'clearInterval', 'clearTimeout', 'alert', 'event', 'this', 'reverse', 'join', 'map', 'forEach', 'slice', 'split', 'stopPropagation', 'preventDefault', 'toggle', 'contains', 'add', 'remove', 'close']);
const calls = new Set([...handlers.matchAll(/(?:^|[^.\w$])([A-Za-z_$][\w$]*)\s*\(/g)].map(m => m[1]));
for (const c of calls) if (!declared.has(c) && !BUILTIN.has(c)) errs.push('MISSING-FN: ' + c);

// 4) 路由与弹层目标存在（含 JS 动态生成的 handler）
const routeSrc = handlersRaw + '\n' + allJs;
for (const m of routeSrc.matchAll(/(?:navTo|setPage)\('([\w-]+)'/g))
  if (!ids.includes(m[1])) errs.push('MISSING-PAGE: ' + m[1]);
for (const m of routeSrc.matchAll(/(?:openSheet|closeSheet)\('([\w-]+)'/g))
  if (!ids.includes(m[1])) errs.push('MISSING-SHEET: ' + m[1]);

// 5) 专版要求：页面与弹层齐备
const need = ['p-care', 'p-baby', 'p-babyStats', 'p-cycleCal', 'p-cycleStats', 'p-symHistory', 'p-careRemind', 'p-babies', 'p-babyDay', 'p-growth', 'p-vaccine',
  'sheetCycleDay', 'sheetBabySwitch', 'sheetAddBaby', 'sheetEventLog', 'sheetVaxAdd', 'sheetBabyMeasure', 'sheetEvPanel', 'sheetDayFilter', 'sheetBsFilter',
  'p-milestones', 'sheetMilestone', 'sheetCarer', 'sheetAllergy', 'sheetCareDate', 'sheetEvManage', 'sheetEvForm'];
for (const n of need) if (!ids.includes(n)) errs.push('ABSENT: ' + n);

// 6) 容器 id 在 JS 中查询的必须在 HTML 存在（仅查静态 $()/getElementById 字面量；dashTip 由 createElement 注入）
for (const m of allJs.matchAll(/\$\('#([\w-]+)'\)/g))
  if (!ids.includes(m[1]) && m[1] !== 'dashTip') errs.push('MISSING-EL: #' + m[1]);

console.log(errs.length ? 'FAIL x' + errs.length + '\n' + errs.join('\n') : 'PASS · scripts=' + scripts.length + ' · handlers=' + calls.size + ' · pages-ok');
