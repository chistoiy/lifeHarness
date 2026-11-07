/* R3-3 批C · 把 r3_3_block.txt 原样插到 xraycheck.js 的锚点行之后。
   护栏：前置「与 HEAD 一致」校验（避免在被写坏过的文件上再叠一遍）、
   锚点唯一命中、尾部逐字保留、体积只增、行数增量大等于块行数。 */
const fs = require('fs');
const { execSync } = require('child_process');

const REPO = 'D:/dev_workplace/flutter_te/lifeHarness';
const TARGET = 'tools/xraycheck.js';
const BLOCK = 'tools/reader/r3_3_block.txt';
const ANCHOR =
  "  (r.resume && /断点在第 5 批/.test(r.toast) && /继续/.test(r.txt)) ? ok('批4 暂停留断点、原地可续跑', r.toast) : bad('批4 暂停续跑', JSON.stringify(r));";

const tp = REPO + '/' + TARGET;
const cur = fs.readFileSync(tp, 'utf8');
const head = execSync('git show HEAD:' + TARGET, { cwd: REPO, maxBuffer: 1 << 26 }).toString();
const CR = String.fromCharCode(13), LF = String.fromCharCode(10);
const flat = (t) => t.split(CR + LF).join(LF);
if (flat(cur) !== flat(head)) throw new Error('目标文件与 HEAD 不一致（行尾归一后仍不同）：先还原再打补丁');

const block = fs.readFileSync(REPO + '/' + BLOCK, 'utf8').replace(/\r\n/g, '\n').replace(/\n$/, '');
const nl = cur.includes('\r\n') ? '\r\n' : '\n';
const lines = block.split('\n').map((l) => l + nl).join('');

const i = cur.indexOf(ANCHOR);
if (i < 0) throw new Error('ANCHOR MISS');
if (cur.indexOf(ANCHOR, i + ANCHOR.length) >= 0) throw new Error('ANCHOR AMBIGUOUS');
const eol = cur.indexOf(nl, i);
const out = cur.slice(0, eol) + nl + lines + cur.slice(eol + nl.length);

const tail = cur.slice(eol + nl.length);
if (!out.endsWith(tail)) throw new Error('TAIL LOST');
const a = Buffer.byteLength(cur, 'utf8'), b = Buffer.byteLength(out, 'utf8');
if (b <= a) throw new Error('体积没长大，可疑');
const addLines = block.split('\n').length;
const grew = out.split(nl).length - cur.split(nl).length;
if (grew !== addLines) throw new Error('行数增量 ' + grew + ' ≠ 块行数 ' + addLines);

fs.writeFileSync(tp, out, 'utf8');
console.log('bytes', a, '->', b, '· lines +' + grew, '· hits=1');
