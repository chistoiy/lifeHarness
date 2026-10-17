/* 批0-3：kits 接线四处共享文件
 *   app_router  · import + shell/page 两条 spread
 *   nav_module  · 底栏栏目池加「工具」
 *   dashboard   · 宫格占位改真实路由
 *   settings    · 「敬请期待」toast 改真实跳转
 * 护栏：每处命中数必须为 1（按各文件实际行尾还原 \n），任一处不符即整体零写入 */
const fs = require('fs');
const NL_OF = f => (fs.readFileSync(f, 'utf8').includes('\r\n') ? '\r\n' : '\n');
const JOBS = [
  {
    f: 'lib/core/router/app_router.dart',
    edits: [
      ["import '../../features/habit/presentation/habit_routes.dart';",
       "import '../../features/habit/presentation/habit_routes.dart';\nimport '../../features/kits/presentation/kit_routes.dart';"],
      ["          ...habitShellRoutes(),",
       "          ...habitShellRoutes(),\n          ...kitShellRoutes(),"],
      ["      ...habitPageRoutes(),",
       "      ...habitPageRoutes(),\n      ...kitPageRoutes(),"],
    ],
  },
  {
    f: 'lib/core/nav/nav_module.dart',
    edits: [
      ["  settings('settings', '我的', Icons.person_outline, Icons.person, '/settings');",
       "  // V1.47 模块14：小工具合集（原型 NAV_MODS「工具」栏同位 · 底栏栏目池可挂载）。\n  kits('kits', '工具', Icons.grid_view_outlined, Icons.grid_view, '/kits'),\n  settings('settings', '我的', Icons.person_outline, Icons.person, '/settings');"],
    ],
  },
  {
    f: 'lib/features/dashboard/presentation/dashboard_page.dart',
    edits: [
      ["    ('🧰', '小工具', null, 'V1.x'),", "    ('🧰', '小工具', '/kits', null),"],
    ],
  },
  {
    f: 'lib/features/settings/presentation/settings_page.dart',
    edits: [
      ["                    onTap: () => _toast(context, '小工具合集 · 敬请期待'))",
       "                    onTap: () => context.go('/kits'))"],
    ],
  },
];
const staged = [];
for (const job of JOBS) {
  const nl = NL_OF(job.f);
  let raw = fs.readFileSync(job.f, 'utf8');
  for (const [a, b] of job.edits) {
    const oldS = a.replace(/\n/g, nl), newS = b.replace(/\n/g, nl);
    const hits = raw.split(oldS).length - 1;
    if (hits !== 1) {
      console.error(`!! ${job.f} 命中 ${hits}（期望 1）：${JSON.stringify(a).slice(0, 60)}`);
      process.exit(1);
    }
    raw = raw.replace(oldS, newS);
  }
  staged.push([job.f, raw]);
}
for (const [f, raw] of staged) { fs.writeFileSync(f, raw); console.log('PASS ' + f); }
