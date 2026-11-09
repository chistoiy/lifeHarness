#!/usr/bin/env node
/* vm_script_check.js：闸5 工装——现行原型全部内联 <script> 过 new vm.Script() 语法编译。
 * 缘起（2026-10-12 事故）：emoji 批 patch 把宫格 SVG 写成裸标签（丢字符串引号）＝token 级
 * 语法错误，块级 hash 自证（registry/doclint）不查 JS 语法，假绿漏过。本闸补死这个洞。
 * 用法：node tools/vm_script_check.js <原型目录> <文件...>
 * 输出：每处语法错一行 "RED: 闸5 语法错 <文件>#<script序号>: <首行错误>"；末行 "VMSCRIPT ok N scripts"。
 * exit 恒 0（判定权在 protogate.py，避免双重语义）；protogate 以 RED: 行计数入红。
 */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const dir = process.argv[2];
const files = process.argv.slice(3);
let total = 0;

for (const f of files) {
  const p = path.join(dir, f);
  let html;
  try {
    html = fs.readFileSync(p, 'utf8');
  } catch (e) {
    console.log(`RED: 闸5 读失败 ${f}: ${e.message}`);
    continue;
  }
  const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
  let m, i = 0;
  while ((m = re.exec(html))) {
    i++;
    total++;
    try {
      new vm.Script(m[1], { filename: `${f}#script${i}` });
    } catch (e) {
      const first = String(e.message || e).split('\n')[0];
      console.log(`RED: 闸5 语法错 ${f}#script${i}: ${first}`);
    }
  }
}
console.log(`VMSCRIPT ok ${total} scripts`);
