/* 行区间替换工装（改 frag_js.txt 这类大片段用，避免手工 Edit 撞行）
   用法：node tools/bs_proto/splice.js <目标文件> <起始行> <结束行> <新内容文件> [起始行须含子串]
   护栏：起始行内容必须命中校验子串，否则零改动退出；替换后打印前后行数。 */
const fs = require('fs');
const [,, file, a, b, blk, must] = process.argv;
if (!file || !a || !b || !blk) { console.error('用法: splice.js <file> <startLine> <endLine> <blockFile> [mustContain]'); process.exit(2) }
const s0 = +a, s1 = +b;
const lines = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n').split('\n');
if (s0 < 1 || s1 > lines.length || s1 < s0) { console.error('FAIL 行号越界：' + s0 + '-' + s1 + ' / 共 ' + lines.length + ' 行'); process.exit(1) }
if (must && lines[s0 - 1].indexOf(must) < 0) { console.error('FAIL 起始行不含「' + must + '」，实际：' + lines[s0 - 1].slice(0, 90)); process.exit(1) }
if (must && lines[s1 - 1].replace(/\s/g, '') !== '}' && lines[s1 - 1].indexOf('}') < 0) { console.error('FAIL 结束行不像代码块收尾：' + lines[s1 - 1].slice(0, 90)); process.exit(1) }
const add = fs.readFileSync(blk, 'utf8').replace(/\r\n/g, '\n').replace(/\n+$/, '').split('\n');
const out = lines.slice(0, s0 - 1).concat(add, lines.slice(s1));
fs.writeFileSync(file, out.join('\n'), 'utf8');
console.log('  ' + file + '：' + lines.length + ' 行 → ' + out.length + ' 行（替换 ' + (s1 - s0 + 1) + ' 行为 ' + add.length + ' 行）');
