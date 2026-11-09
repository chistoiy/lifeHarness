/* 悬浮胶囊原型批 · 变异三刀自证（2026-10-14）
 * 每刀：快照 → 改源（命中断言）→ 跑 pillcheck 期望红在其位 → 还原 → md5 复原核验。
 * 用法：node tools/pill_mut.js */
const fs = require('fs'), crypto = require('crypto'), { spawnSync } = require('child_process');
const F = 'prototype/index-bookshelf.html';
const CUTS = [
  ['刀1 贴边圆圈节点失联', [['id="pillFab"', 'id="pillFabX"']], 'FAIL P3'],
  ['刀2 秒显降级成只到分', [["return h?h+':'+String(m).padStart(2,'0')+':'+String(x).padStart(2,'0'):m+':'+String(x).padStart(2,'0')", "return m+':'+String(x).padStart(2,'0')"]], 'FAIL P2'],
  ['刀3 C6 案A 直开短路', [['function pillNoteA(){const t=timerTarget||\'\';', 'function pillNoteA(){return;const t=timerTarget||\'\';']], 'FAIL P5'],
];
let fail = 0;
const buf0 = fs.readFileSync(F);
const md5 = b => crypto.createHash('md5').update(b).digest('hex');
for (const [name, reps, want] of CUTS) {
  let src = buf0.toString('utf8'), hit = true;
  for (const [a] of reps) if (!src.includes(a)) { hit = false; break } else src = src.split(a).join(reps.find(r => r[0] === a)[1]);
  if (!hit) { console.log('MUT-MISS ' + name + '（变异锚点没命中＝工装失真）'); fail = 1; continue }
  fs.writeFileSync(F, src);
  const r = spawnSync('node', ['tools/pillcheck.js'], { encoding: 'utf8', timeout: 120000 });
  const out = (r.stdout || '') + (r.stderr || '');
  const red = r.status !== 0 && out.includes(want);
  console.log((red ? 'RED-OK  ' : 'MUT-BAD ') + name + '  期望 ' + want + (red ? '' : '  →  实际 ' + out.split('\n').filter(l => /FAIL|RESULT/.test(l)).join(' | ').slice(0, 200)));
  if (!red) fail = 1;
  fs.writeFileSync(F, buf0); /* 还原 */
}
const same = md5(fs.readFileSync(F)) === md5(buf0);
console.log('RESTORE ' + (same ? 'OK md5 复原' : 'BAD 源文件没还原干净！'));
if (!same) fail = 1;
process.exit(fail ? 1 : 0);
