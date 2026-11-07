// 校验原型内联 <script> 语法：抽出每段脚本交给 vm.Script 编译（不执行 DOM）。
const fs = require('fs');
const vm = require('vm');
const path = process.argv[2] || 'prototype/index-bookshelf.html';
const html = fs.readFileSync(path, 'utf8');
const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
let m, i = 0, bad = 0;
while ((m = re.exec(html))) {
  i++;
  const body = m[1];
  const line = html.slice(0, m.index).split('\n').length;
  try {
    new vm.Script(body, { filename: `${path}#script${i}@line${line}` });
  } catch (e) {
    bad++;
    console.log(`FAIL script#${i} (html line ${line}): ${e.message}`);
    const le = /:(\d+):/.exec(e.stack || '');
    if (le) {
      const bl = body.split('\n');
      const n = Math.min(bl.length, +le[1]);
      for (let k = Math.max(1, n - 2); k <= Math.min(bl.length, n + 1); k++)
        console.log(`   ${k === n ? '>>' : '  '} ${k}: ${bl[k - 1].slice(0, 160)}`);
    }
  }
}
console.log(`${path}: scripts=${i} bad=${bad}`);
process.exit(bad ? 1 : 0);
