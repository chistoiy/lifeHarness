/* media_unfreeze_c7.js · 影音游批2 第一刀 A 段：index-media.html 解冻＋violations 按 DOM 实态重建
 * 用法：node tools/media_unfreeze_c7.js [--dry]
 * 护栏：写前快照落 tmp/；命中断言（副本数须 ≥30）；--dry 只报不写。
 */
const fs = require('fs');
const dry = process.argv.includes('--dry');
const REGP = 'prototype/_modules.json', FILE = 'index-media.html';
const reg = JSON.parse(fs.readFileSync(REGP, 'utf8'));
const html = fs.readFileSync('prototype/' + FILE, 'utf8');

/* 1. 与 protogate.ids_in 同口径扫 DOM id */
const ids = new Set();
for (const m of html.matchAll(/<(?:section|div)\b[^>]*\bid="([^"]+)"/g)) {
  const tag = m[0].split(/\s+/)[0];
  if (tag === '<div' && !(m[1].startsWith('sheet') || m[1].startsWith('drawer'))) continue;
  ids.add(m[1]);
}
const byid = {};
for (const s of reg.screens) byid[s.id] = s;
const copies = [];
for (const id of [...ids].sort()) {
  const s = byid[id];
  if (!s) continue;                       // 未登记 id 由 protogate 判红，本刀不管
  if (s.status === 'dropped') continue;   // 下架件走 DROP toast，不是越权副本
  if (s.status === 'collision') continue;
  if (s.home === FILE) continue;
  if ((s.reps || []).includes(FILE)) continue; // 授权副本（联动层）不算越权，与 protogate 同口径
  copies.push({ file: FILE, id, home: s.home });
}
if (copies.length < 30) { console.error('FAIL 副本命中 ' + copies.length + ' 枚（预期 ≥30）——中止'); process.exit(1); }

/* 2. frozen 出表＋violations 重建（media 段整体按实态替换，其余文件条目原样保留） */
const before = { frozen: reg.frozen.length, vio: reg.violations.length };
reg.frozen = (reg.frozen || []).filter(f => f !== FILE);
reg.violations = (reg.violations || []).filter(v => v.file !== FILE).concat(copies);
reg.updated = '2026-10-07';
console.log(JSON.stringify({ copies: copies.length, idsInDom: ids.size,
  frozen: before.frozen + '→' + reg.frozen.length, vio: before.vio + '→' + reg.violations.length }));
if (dry) { console.log('DRY 未写盘'); process.exit(0); }
fs.writeFileSync('tmp/media_unfreeze_snapshot_c7.json', JSON.stringify(JSON.parse(fs.readFileSync(REGP, 'utf8')), null, 1), 'utf8');
fs.writeFileSync(REGP, JSON.stringify(reg, null, 1) + '\n', 'utf8');
console.log('WROTE ' + REGP);
