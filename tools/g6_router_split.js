/* g6_router_split.js · 治理G6：路由按域下沉 features/x/presentation/x_routes.dart
   规则：路由块=注释前导+GoRoute(...) 括号平衡整体搬运；域按 path 前缀表判定；
   app_router 保留 HomeShell/返回语义/AI根栈注释，routes 改为聚合各域函数。
   守护：86 条 path 集合拆前拆后必须全等。 */
const fs = require('fs');
const SRC = 'lib/core/router/app_router.dart';
const src = fs.readFileSync(SRC, 'utf8');
const fail = (m) => { console.error('GUARD-FAIL: ' + m); process.exit(1); };

/* ---- 域判定（有序前缀表） ---- */
const PREFIX2FEAT = [
  ['/read', 'read'], ['/ledger', 'ledger'], ['/care', 'care'], ['/habit', 'habit'],
  ['/days', 'days'], ['/items', 'items'], ['/goals', 'goals'],
  ['/settings', 'settings'], ['/log', 'settings'], ['/sync', 'settings'],
  ['/journal', 'journal'], ['/note', 'journal'],
  ['/todo', 'todo'], ['/pomo', 'todo'],
  ['/calendar', 'calendar'], ['/categories', 'calendar'], ['/time-stats', 'calendar'],
  ['/habits', 'habit'], ['/inbox', 'inbox'], ['/dashboard', 'dashboard'], ['/', 'dashboard'],
];
const featOf = (p) => { for (const [pre, f] of PREFIX2FEAT) if (pre === '/' ? p === '/' : p.startsWith(pre)) return f; return fail('未映射路由 ' + p); };

/* ---- 提取 routes 数组区（两个 region：ShellRoute 内 shell 与外层 page） ---- */
function blocksOf(regionText) {
  const out = [];
  const lines = regionText.split(/\r?\n/);
  let cur = null, depth = 0, q = null;
  for (let li = 0; li < lines.length; li++) {
    const line = lines[li];
    if (!cur && /^\s*(\/\/|\/\/\/)/.test(line)) { (cur = cur || []).push(line); continue; }
    if (/^\s*(\/\/|\/\/\/)/.test(line) && cur) { cur.push(line); continue; }
    if (!cur && !line.trim()) continue;
    const buf = cur ? cur.join('\n') : '';
    if (!cur) cur = [line];
    else cur.push(line);
    // 扫描该行状态（简化：逐字符跟踪 q/depth 跨行累计）
    let i = 0; let localDepth = depth, localQ = q;
    while (i < line.length) {
      const c = line[i], three = line.slice(i, i + 3);
      if (!localQ) {
        if (c === '/' && line[i + 1] === '/') break;
        if (three === "'''") { localQ = "'''"; i += 3; continue; }
        if (c === "'" || c === '"') { localQ = c; i++; continue; }
        if ('([{'.includes(c)) localDepth++;
        else if (')]}'.includes(c)) localDepth--;
        i++; continue;
      }
      if (c === '\\') { i += 2; continue; }
      if (localQ === "'''") { if (three === "'''") { localQ = null; i += 3; continue; } i++; continue; }
      if (c === localQ) { localQ = null; }
      i++;
    }
    depth = localDepth; q = localQ;
    if (depth === 0 && !q) {
      const text = cur.join('\n');
      const pm = text.match(/path:\s*'([^']+)'/);
      if (!pm) { if (text.trim()) fail('块内无 path: ' + text.slice(0, 50)); }
      else out.push({ path: pm[1], text });
      cur = null; depth = 0; q = null;
    }
  }
  if (cur && cur.join('').trim()) fail('region 尾部残留块未闭合');
  return out;
}
const shellStart = src.indexOf('routes: [', src.indexOf('ShellRoute('));
const shellEnd = src.indexOf('\n        ],', shellStart);
const shellText = src.slice(src.indexOf('[', shellStart) + 1, shellEnd);
const pageStart = src.indexOf('\n      ),', shellEnd); // ShellRoute 闭括号后起算，防止外层 region 吞壳块
const pageEnd = src.indexOf('\n    ],', pageStart);
const pageText = src.slice(pageStart + '\n      ),'.length, pageEnd);
const shellBlocks = blocksOf(shellText);
const pageBlocks = blocksOf(pageText);
const all = [...shellBlocks, ...pageBlocks];
console.log('shell blocks=', shellBlocks.length, 'page blocks=', pageBlocks.length);
if (shellBlocks.length !== 13) fail('壳路由数 ' + shellBlocks.length);
const basePaths = all.map(b => b.path).sort();

/* ---- import 归属表（按 feature 分发原 import 行） ---- */
const importLines = (src.match(/^import[^\n]*\n(?:\s+show[^\n]*\n)?|^\/\/[^\n]*\n/gm) || []);
const FEATURE_DIR = f => '../../features/' + f + '/';
const importsFor = (feat, allText) => {
  // 从原 import 块挑出：路径含 /features/<feat>/ 且符号在块文本出现（按文件 basename 猜类名或用原行 show）
  const keep = [];
  const re = /^(import '[^']+'(?:\s+show [\w, ]+)?);/m;
  for (const raw of src.split(/\r?\n/)) {
    const m = raw.match(/^import '(\/?[^']+)'(.*)$/); if (!m) continue;
    const spec = m[1];
    if (!spec.includes('/features/' + feat + '/')) continue;
    keep.push(raw);
  }
  // 精简：只保留被块文本引用到的（basename 的每个词首字母大写组合或原样符号缺失时保守保留全部）
  const used = keep.filter(line => {
    const show = line.match(/show ([\w, ]+)/);
    if (show && show[1].split(',').some(s => allText.includes(s.trim()))) return true;
    const base = line.match(/\/([\w.]+)\.dart/); if (!base) return true;
    const words = base[1].split('_');
    const cls = words.map(w => w[0].toUpperCase() + w.slice(1)).join('');
    return allText.includes(cls);
  }).map(line => line.replace(/import '[^']*\/features\/(\w+)\/presentation\/([^']+)'/,
    (m, f, p) => f === feat ? "import '" + p + "'" : "import 'package:lifeharness/features/" + f + "/presentation/" + p + "'"));
  return used;
};

/* ---- 生成各域 _routes.dart ---- */
const feats = {};
for (const b of shellBlocks) (feats[featOf(b.path)] = feats[featOf(b.path)] || { shell: [], page: [] }).shell.push(b);
for (const b of pageBlocks) (feats[featOf(b.path)] = feats[featOf(b.path)] || { shell: [], page: [] }).page.push(b);
const IND = t => t.split('\n').map((l, k) => k === 0 ? '      ' + l : (l.trim() ? '    ' + l : l)).join('\n');
let newCount = 0;
for (const [feat, g] of Object.entries(feats)) {
  const body = [];
  if (g.shell.length) body.push('/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）\nList<GoRoute> ' + feat + 'ShellRoutes() => [\n' + g.shell.map(b => IND(b.text.replace(/^\s+/, '  ').replace(/,\s*$/, ''))).join(',\n') + '\n];');
  if (g.page.length) body.push('/// 全屏栈路由（治理G6 下沉）\nList<GoRoute> ' + feat + 'PageRoutes() => [\n' + g.page.map(b => IND(b.text.replace(/^\s+/, '  ').replace(/,\s*$/, ''))).join(',\n') + '\n];');
  const allText = g.shell.concat(g.page).map(b => b.text).join('\n');
  newCount += g.shell.length + g.page.length;
  let txt = 'import \'package:flutter/material.dart\';\nimport \'package:go_router/go_router.dart\';\n';
  const extra = importsFor(feat, allText);
  // 类名与文件 basename 不规则的补偿 import（analyze 差集校准得出）
  const SPECIAL = {
    settings: ["import 'ai_page.dart';", "import 'recmg_page.dart';"],
    read: ["import 'shelf/read_lists_page.dart';"],
    care: ["import 'milestone_page.dart';"],
  };
  if (extra.length || SPECIAL[feat]) txt += '\n' + extra.join('\n') + '\n' + (SPECIAL[feat] || []).join('\n') + '\n';
  txt = '// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。\n' + txt + '\n' + body.join('\n\n') + '\n';
  fs.mkdirSync('lib/features/' + feat + '/presentation', { recursive: true });
  fs.writeFileSync('lib/features/' + feat + '/presentation/' + (feat === 'dashboard' ? 'dashboard' : feat) + '_routes.dart', txt);
  console.log(feat + '_routes.dart shell=' + g.shell.length + ' page=' + g.page.length);
}
if (newCount !== all.length) fail('块丢失 ' + newCount + '/' + all.length);

/* ---- 重写 app_router ---- */
const FEAT_ORDER = ['dashboard', 'todo', 'calendar', 'journal', 'habit', 'inbox', 'ledger', 'care', 'days', 'items', 'goals', 'read', 'settings'];
const usedFeats = Object.keys(feats);
let router = src;
// 1) 替换两个 region
const shellCall = FEAT_ORDER.filter(f => feats[f] && feats[f].shell.length).map(f => '          ...' + f + 'ShellRoutes(),').join('\n');
const pageCall = FEAT_ORDER.filter(f => feats[f] && feats[f].page.length).map(f => '      ...' + f + 'PageRoutes(),').join('\n');
router = router.slice(0, shellStart) + 'routes: [\n' + shellCall + '\n        ],' + router.slice(shellEnd + '\n        ],'.length);
// 重新定位 page region（shell 区已缩短）
const ps = router.indexOf('routes: [', router.indexOf('return GoRouter'));
const pe = router.indexOf('\n    ],', ps);
const shellClose = router.indexOf('\n      ),', ps) + '\n      ),'.length; // ShellRoute 元素整体保留到此为止
router = router.slice(0, shellClose) + '\n' + pageCall + router.slice(pe);
// 2) 删除按域分走的 feature import 行（HomeShell 仍用的 journal_providers/dashboard_providers 保留）
const lines = router.split(/\r?\n/);
const keepLines = lines.filter(l => {
  const m = l.match(/^import '(\/?[^']+)'/); if (!m) return true;
  const spec = m[1];
  if (!spec.includes('/features/')) return true;
  if (/[a-z]+_routes\.dart/.test(spec)) return true;
  if (spec.includes('journal_providers.dart') || spec.includes('dashboard_providers.dart')) return true;
  const feat = (spec.match(/\/features\/(\w+)\//) || [])[1];
  const own = feats[feat];
  if (!own) return true;
  const txt = own.shell.concat(own.page).map(b => b.text).join('\n');
  const base = l.match(/\/([\w.]+)\.dart/); if (!base) return true;
  const cls = base[1].split('_').map(w => w[0].toUpperCase() + w.slice(1)).join('');
  return !txt.includes(cls);
});
router = keepLines.join('\n===NL===').replace(/===NL===/g, '\n');
// 3) 头部补 routes import + 悬空注释行清理（随 import 走的单行 // 注释删除）
const routeImports = usedFeats.map(f => "import '../../features/" + f + "/presentation/" + f + "_routes.dart';").join('\n');
router = router.replace("import '../ai/ai_review.dart' show aiRootNavKey;", "import '../../features/dashboard/presentation/dashboard_routes.dart';\n" + routeImports.replace("import '../../features/dashboard/presentation/dashboard_routes.dart';\n", '') + "\nimport '../ai/ai_review.dart' show aiRootNavKey;");
fs.writeFileSync(SRC, router);
// 4) 校验 path 集合
const after = (router.match(/path:\s*'([^']+)'/g) || []).map(s => s.match(/'([^']+)'/)[1]).sort();
const inRoutes = FEAT_ORDER.flatMap(f => { const p = 'lib/features/' + f + '/presentation/' + f + '_routes.dart'; return fs.existsSync(p) ? ((fs.readFileSync(p, 'utf8').match(/path:\s*'([^']+)'/g) || []).map(s => s.match(/'([^']+)'/)[1])) : []; });
const merged = [...new Set([...after, ...inRoutes])].sort();
console.log('paths before=', basePaths.length, 'after(merged)=', merged.length, 'EQUAL=', JSON.stringify(basePaths) === JSON.stringify(merged));
if (JSON.stringify(basePaths) !== JSON.stringify(merged)) {
  const A = new Set(basePaths), B = new Set(merged);
  console.log('missing=', basePaths.filter(x => !B.has(x)), 'extra=', merged.filter(x => !A.has(x)));
}
