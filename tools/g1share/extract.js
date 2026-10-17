/* 把指定原型的第 N 个内联 <script> 提取成临时 .js，交给 node --check 定位真实错行 */
const fs = require('fs');
const file = process.argv[2], idx = Number(process.argv[3] || 1);
const s = fs.readFileSync(file, 'utf8');
const blocks = [];
let m, re = /<script>([\s\S]*?)<\/script>/g;
while ((m = re.exec(s))) blocks.push({ body: m[1], startLine: s.slice(0, m.index).split('\n').length });
const b = blocks[idx - 1];
if (!b) { console.log('无第 ' + idx + ' 段脚本（共 ' + blocks.length + '）'); process.exit(2); }
const out = 'tools/g1share/_tmp_script.js';
/* 前面补空白行，让 node --check 报的就是原型文件里的绝对行号 */
fs.writeFileSync(out, '\n'.repeat(b.startLine) + b.body);
console.log('脚本 ' + idx + ' 起始行 ' + b.startLine + '，长度 ' + b.body.length);
