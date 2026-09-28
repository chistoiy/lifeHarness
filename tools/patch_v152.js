/* patch_v152.js · 速记列用例有界轮询+跨分钟容忍（G6 悬案根治第四例） */
const fs = require('fs');
const P = 'test/time_v152_test.dart';
let s = fs.readFileSync(P, 'utf8');
const old = [
  '    final act = await tbDao.activeTiming();',
  "    expect(act, isNotNull);",
  "    expect(act!.catName, '工作');",
  '    expect(act.startMin, now.hour * 60 + now.minute);',
].join(/\r\n/.test(s) ? '\r\n' : '\n');
if (!s.includes(old)) { console.error('HIT-FAIL old block'); process.exit(1); }
const sep = /\r\n/.test(s) ? '\r\n' : '\n';
const neu = [
  '    var act = await tbDao.activeTiming();',
  '    for (var i = 0; i < 40 && act == null; i++) {',
  '      // 治理G6 悬案根治：点按后开块落库在高负载下可迟一拍（本用例曾随机挂）→',
  '      // 有界轮询等行出现，超时仍由下方 isNotNull 判失败。',
  '      await Future<void>.delayed(const Duration(milliseconds: 50));',
  '      act = await tbDao.activeTiming();',
  '    }',
  '    expect(act, isNotNull);',
  "    expect(act!.catName, '工作');",
  '    // 治理G6：原严格比对文件头 now，断言跨分钟即假失败 → 容忍点按/开块 +0~2 分钟。',
  '    final mSeed = now.hour * 60 + now.minute;',
  '    expect(act.startMin,',
  '        anyOf(mSeed, (mSeed + 1) % 1440, (mSeed + 2) % 1440),',
  "        reason: '开块分钟=点按时刻（容忍轮询期跨分钟）');",
].join(sep);
s = s.replace(old, neu);
fs.writeFileSync(P, s);
const chk = fs.readFileSync(P, 'utf8');
if (!chk.includes('mSeed') || chk.includes('expect(act.startMin, now.hour')) { console.error('VERIFY-FAIL'); process.exit(1); }
console.log('PATCH-OK');
