/* 内联脚本语法门：提取 <script> 块逐个 vm.Script 编译，报错定位行号 */
const fs = require('fs'), vm = require('vm');
const file = process.argv[2] || 'prototype/index.html';
const s = fs.readFileSync(file, 'utf8');
let m, re = /<script>([\s\S]*?)<\/script>/g, k = 0, bad = 0;
while ((m = re.exec(s))) {
  k++;
  try { new vm.Script(m[1], { filename: 'inline' + k }); }
  catch (e) {
    bad++;
    const pre = s.slice(0, m.index).split('\n').length;
    const lm = /inline\d+:(\d+)/.exec(e.stack);
    console.log('SCRIPT ' + k + ' ERROR ~line ' + (pre + (lm ? Number(lm[1]) - 1 : 0)) + ': ' + e.message);
  }
}
console.log(bad ? 'FAIL scripts=' + k + ' errors=' + bad : 'syntax OK, scripts=' + k);
process.exit(bad ? 1 : 0);
