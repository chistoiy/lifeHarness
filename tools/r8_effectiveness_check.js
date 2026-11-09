// R8 守护有效性自检（一次性）：临时给 prompts.json 插一条「未登记能力点」，
// 跑 architecture_test 期望变红，再原样还原并校验字节一致。
const fs = require('fs');
const {execSync} = require('child_process');
const p = 'assets/ai_prompts/prompts.json';
const orig = fs.readFileSync(p);
const bak = Buffer.from(orig);
try {
  const j = JSON.parse(orig.toString('utf8'));
  j.tasks.push({
    id: 'probe.unregistered',
    module: '探针',
    name: '探针能力',
    system: 's',
    user: 'u',
    expect: 'text',
    placeholders: [],
    sample: '',
  });
  fs.writeFileSync(p, JSON.stringify(j, null, 2), 'utf8');
  let red = false;
  try {
    execSync('flutter test test/architecture_test.dart --reporter compact --plain-name "R8"', {stdio: 'pipe'});
  } catch (e) {
    red = true;
    const out = (e.stdout ? e.stdout.toString() : '') + (e.stderr ? e.stderr.toString() : '');
    console.log('R8 注入后变红 =', red);
    console.log(out.split('\n').filter(l => /probe.unregistered|未登记|deadRows|能力矩阵/.test(l)).slice(0, 4).join('\n'));
  }
  if (!red) throw new Error('R8 未咬住注入的未登记能力点＝守护空转');
} finally {
  fs.writeFileSync(p, bak);
  const now = fs.readFileSync(p);
  if (!now.equals(orig)) throw new Error('还原失败：字节不一致');
  console.log('prompts.json 已原样还原（' + now.length + ' 字节）');
}
