/* diag_members.js · G5 调试：打印成员切块结果与深度异常点 */
const src = require('fs').readFileSync('lib/core/database/schema.dart', 'utf8');
const bodyOpen = src.indexOf('{', src.indexOf('const DbSchema._()')) + 1;
const clsEnd = src.lastIndexOf('\n}');
const bodyFull = src.slice(bodyOpen, clsEnd);
const mIdx = bodyFull.search(/\r?\n {2}static [\w<>, ]+\([\w ]*\)\s*\{/);
console.log('methodIdx=', mIdx < 0 ? 'none' : mIdx);
const body = bodyFull.slice(0, mIdx < 0 ? bodyFull.length : mIdx);
let i = 0, depth = 0, q = null, chunk = '', chunks = [];
const SQ = String.fromCharCode(39), BS = String.fromCharCode(92);
while (i < body.length) {
  const c = body[i], three = body.slice(i, i + 3);
  if (!q) {
    if (c === '/' && body[i + 1] === '/') { const e = body.indexOf('\n', i); i = e < 0 ? body.length : e; continue; }
    if (three === SQ + SQ + SQ) { q = SQ + SQ + SQ; chunk += three; i += 3; continue; }
    if (c === SQ || c === '"') { q = c; chunk += c; i++; continue; }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth--;
    if (depth < 0) { console.log('NEG at', i, JSON.stringify(body.slice(i - 40, i + 10))); break; }
    if (c === ';' && depth === 0) { chunks.push(chunk + ';'); chunk = ''; i++; continue; }
    chunk += c; i++; continue;
  }
  if (c === BS) { chunk += body.slice(i, i + 2); i += 2; continue; }
  if (q === SQ + SQ + SQ) { if (three === SQ + SQ + SQ) { chunk += three; q = null; i += 3; continue; } chunk += c; i++; continue; }
  if (c === q) { chunk += c; q = null; i++; continue; }
  chunk += c; i++;
}
console.log('chunks=', chunks.length, 'tail=', JSON.stringify(chunk.slice(0, 60)));
chunks.forEach((t, k) => console.log(k, t.trim().slice(0, 50).replace(/\n/g, '|'), 'len=' + t.length));
