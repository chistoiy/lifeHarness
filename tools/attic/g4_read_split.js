/* g4_read_split.js · 治理G4：read presentation 分五子目录（纯移动+import机械重写）
   单遍全量重写：先快照所有 .dart 旧路径，应用移动映射，再对每个 import 以
   「源旧位置解析 → 目标新位置 → 源新位置重述」统一处理（含 moved→unmoved）。
   守护：待移动文件必须齐全；重写计数下限断言；git mv 失败即中止。 */
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const P = 'lib/features/read/presentation';
const MAP = {
  'reader/': ['reader_page.dart', 'reader_pager.dart', 'reader_bg.dart', 'reader_appearance_sheet.dart', 'reader_bottom_sheets.dart', 'reader_search_page.dart', 'reader_toc_drawer.dart', 'epub_state_ui.dart'],
  'shelf/': ['shelf_page.dart', 'book_detail.dart', 'book_form_page.dart', 'book_mgr_page.dart', 'read_lists_page.dart'],
  'biblio/': ['biblio_search_page.dart', 'book_info_page.dart', 'douban_login_page.dart', 'isbn_scan_page.dart'],
  'import/': ['local_import_page.dart', 'read_import_page.dart'],
  'stats/': ['read_stat_page.dart', 'read_log_page.dart', 'read_timer_page.dart', 'quotes_lib_page.dart'],
};
const moves = new Map();
for (const [dir, files] of Object.entries(MAP))
  for (const f of files) {
    const oldR = P + '/' + f;
    if (!fs.existsSync(oldR)) { console.error('MISSING ' + oldR); process.exit(1); }
    moves.set(oldR, P + '/' + dir + f);
  }
if (moves.size !== 23) { console.error('GUARD-FAIL map=' + moves.size); process.exit(1); }

function dartFiles(d, acc = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name).replace(/\\/g, '/');
    if (e.isDirectory()) { if (e.name !== '.dart_tool' && e.name !== 'build') dartFiles(p, acc); }
    else if (e.name.endsWith('.dart')) acc.push(p);
  }
  return acc;
}
const all = [...dartFiles('lib'), ...dartFiles('test')]; // 移动前快照（posix 相对仓库根）
const newPath = f => moves.get(f) || f;

// 1) 重写 import（对磁盘现状=旧布局解析；全部算完后统一落盘）
const re = /^([ \t]*)import\s+'([^']+)'([\s\S]*?);/gm;
let total = 0; const edits = new Map();
for (const file of all) {
  const src = fs.readFileSync(file, 'utf8');
  const out = src.replace(re, (m, ind, spec, tail) => {
    let resolved = null;
    if (spec.startsWith('package:lifeharness/')) resolved = 'lib/' + spec.slice('package:lifeharness/'.length);
    else if (!spec.startsWith('dart:')) resolved = path.posix.normalize(path.posix.join(path.posix.dirname(file), spec));
    if (!resolved || !fs.existsSync(resolved)) return m; // 非本仓文件或不存在：不动
    const targetNew = newPath(resolved);
    const srcNew = newPath(file);
    if (srcNew === file && targetNew === resolved) return m;
    let fixed;
    if (spec.startsWith('package:')) fixed = 'package:lifeharness/' + (targetNew.startsWith('lib/') ? targetNew.slice(4) : targetNew);
    else {
      let rel = path.posix.relative(path.posix.dirname(srcNew), targetNew);
      if (!rel.startsWith('.')) rel = './' + rel;
      fixed = rel;
    }
    if (fixed !== spec) { total++; return ind+"import '" + fixed + "'" + tail + ';'; }
    return m;
  });
  if (out !== src) edits.set(file, out);
}
console.log('planned-rewrites=' + total + ' in files=' + edits.size);
if (total < 80) { console.error('GUARD-FAIL rewrite=' + total + '（预期至少八十余处·未落盘未移动）'); process.exit(1); }
for (const [f, txt] of edits) fs.writeFileSync(f, txt);
for (const [f, txt] of edits) fs.writeFileSync(f, txt);

// 2) git mv
for (const dir of Object.keys(MAP)) fs.mkdirSync(P + '/' + dir, { recursive: true });
for (const [o, n] of moves) execFileSync('git', ['mv', o, n], { stdio: 'pipe' });
console.log('moved=' + moves.size + ' OK');
