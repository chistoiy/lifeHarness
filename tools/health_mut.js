/* health_mut.js · 批④健康数据层变异自证（单批 ≤3 刀，AGENTS 门禁瘦身三条）
 * 用法：node tools/health_mut.js
 * 每刀＝把决策行改回「修复前形态」，跑受影响测试文件，期望它红；跑完按内存原文复原并校验 md5。
 * 刀1 睡眠跨天 +1440   → health_calc_test 红
 * 刀2 达标度运动门槛制 → health_calc_test 红
 * 刀3 档案级联先删子表 → health_dao_test 红
 */
const fs = require('fs'), path = require('path'), crypto = require('crypto'), { spawnSync } = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const FLUTTER = process.env.FLUTTER_BIN || 'D:/app_workplace/flutter/bin/flutter';
const md5 = s => crypto.createHash('md5').update(s).digest('hex').slice(0, 8);
const files = {
  calc: path.join(ROOT, 'lib/features/health/domain/health_calc.dart'),
  repo: path.join(ROOT, 'lib/features/health/data/health_repository.dart'),
};
const orig = {};
for (const k in files) orig[k] = fs.readFileSync(files[k], 'utf8');
let bad = 0;

function runTest(file) {
  const r = spawnSync(FLUTTER, ['test', '--no-pub', file, '-r', 'compact'],
    { encoding: 'utf8', cwd: ROOT, shell: false });
  const out = (r.stdout || '') + (r.stderr || '');
  const m = out.match(/([+-]\d+)\s*-\s*(\d+)\s*:/) || out.match(/-\s*(\d+):/);
  return { rc: r.status, red: /Some tests failed/.test(out) || r.status !== 0, tail: out.trim().split('\n').slice(-1)[0] || '' };
}
function knife(name, key, from, to, testFile) {
  const src = orig[key];
  const n = src.split(from).length - 1;
  if (n !== 1) { console.log('SKIP ' + name + '：锚点命中 ' + n + ' 处'); bad++; return }
  fs.writeFileSync(files[key], src.replace(from, to), 'utf8');
  const r = runTest(testFile);
  fs.writeFileSync(files[key], src, 'utf8');
  const restored = md5(fs.readFileSync(files[key], 'utf8')) === md5(src);
  console.log((r.red && restored ? 'OK   ' : 'MISS ') + name + ' → ' + (r.red ? '已红' : '仍绿（死闸！）')
    + ' ｜ 复原=' + (restored ? 'md5 一致' : '不一致') + ' ｜ ' + r.tail.slice(0, 90));
  if (!r.red || !restored) bad++;
}

const SLEEP = '  return d <= 0 ? d + 1440 : d;';
knife('刀1 睡眠跨天 +1440', 'calc', SLEEP, '  return d;', 'test/health_calc_test.dart');
knife('刀2 运动改回比例制', 'calc', '  final e = exerciseMin >= exerciseThresholdMin ? 1.0 : 0.0;',
  '  final e = (exerciseMin / (exerciseThresholdMin * 3)).clamp(0.0, 1.0);', 'test/health_calc_test.dart');
const CHILD = `      await txn.rawDelete(
          'DELETE FROM \${h.tHealthDrugLog} WHERE drug_id IN (SELECT id FROM \${h.tHealthDrug} WHERE profile_id=?)',
          [profileId]);`;
knife('刀3 子表不再先删（顺序退回）', 'repo', CHILD, '', 'test/health_dao_test.dart');
console.log(bad ? '== 变异自证未过：' + bad + ' 项 ==' : '== 变异自证全过 ==');
process.exit(bad ? 1 : 0);
