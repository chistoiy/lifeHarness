/* 合并单网格后容器只剩 .kgrid，把探针与断言的选择器从 .grid 改到 .kgrid
 * 用法：node tools/kits/patch_kitscheck_r2e.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const JOBS = [
  { f: 'tools/kits/kitscheck.js', from: "g.querySelectorAll('.grid')", to: "g.querySelectorAll('.kgrid')", n: 1 },
  { f: 'tools/kits/gridproof.js', from: "#toolGrid .grid", to: "#toolGrid .kgrid", n: 1 },
];
for (const j of JOBS) {
  const raw = fs.readFileSync(path.resolve(j.f), 'utf8');
  const c = raw.split(j.from).length - 1;
  if (c !== j.n) { console.error('!! ' + j.f + ' 命中 ' + c + '，零写入'); process.exit(1); }
  console.log('PASS ' + j.f + '  ' + j.from + ' → ' + j.to);
  if (!DRY) fs.writeFileSync(path.resolve(j.f), raw.replace(j.from, j.to));
}
if (DRY) console.log('dry-run');
