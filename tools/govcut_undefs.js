// undefs.js · 迭代零引用顶层函数清除：node tmp/undefs.js <文件名> [--dry]
// 判据：名字在整份文本出现恰 1 次（即只有定义行本身）→ 删定义整段（function 体括号配平 / 单行 const 箭头到行尾）。
// 循环至不动点。护栏：checkinline 语法由调用方复跑；--dry 只报告。
const fs = require('fs');
const f = process.argv[2];
const dry = process.argv.includes('--dry');
const F = 'prototype/' + f;
let h = fs.readFileSync(F, 'utf8');
// 只清"因本批删除而失去引用"的函数：删前快照中引用数须 >1（删前已死＝存量债，出本批范围）
const PRE = 'tmp/snap-cut/' + f + '.before';
const pre = fs.existsSync(PRE) ? fs.readFileSync(PRE, 'utf8') : null;
if (!pre) console.log('!! 无 .before 快照，退化为全量零引用清除');
const cntIn = (text, n) => (text.match(new RegExp('(?<![\\w$.])' + n.replace(/\$/g, '\\$') + '(?![\\w$])', 'g')) || []).length;
const log = [];
let iter = 0, removed = 0;
function findDef(name, text) {
  // function 声明
  let m = text.match(new RegExp('(?:^|\\n)(function\\s+' + name + '\\s*\\()', 'g'));
  const fd = new RegExp('function\\s+' + name + '\\s*\\(').exec(text);
  if (fd && (!m || m.length === 1)) {
    const start = text.indexOf('function', fd.index);
    let p = text.indexOf('(', start + 9), dp = 0, k = p;
    for (; k < text.length; k++) { const c = text[k]; if (c === '(') dp++; else if (c === ')') { dp--; if (!dp) break; } }
    let s = text.indexOf('{', k);
    if (s < 0 || s - k > 30) return null;
    let depth = 0; let j = s;
    for (; j < text.length; j++) { const c = text[j]; if (c === '{') depth++; else if (c === '}') { depth--; if (!depth) break; } }
    // 含行尾分号（若有）
    let end = j + 1;
    if (text[end] === ';') end++;
    return { start, end };
  }
  return null;
}
while (iter++ < 12) {
  const names = [...h.matchAll(/(?:^|\n)\s*function\s+([A-Za-z_$][\w$]*)\s*\(/g)].map(m => m[1]);
  let changed = false;
  for (const n of [...new Set(names)]) {
    const cnt = cntIn(h, n);
    if (cnt !== 1) continue;
    if (pre && cntIn(pre, n) <= 1) continue;
    const d = findDef(n, h);
    if (!d) continue;
    // 保险：定义段内不得再含其他 function 定义起点判断失误（粗查段落内 'function ' 个数==1）
    const seg = h.slice(d.start, d.end);
    if ((seg.match(/\bfunction\b/g) || []).length > 1) continue;
    h = h.slice(0, d.start) + h.slice(d.end);
    log.push(n); removed++; changed = true;
  }
  if (!changed) break;
}
console.log(f, '清除', removed, '个零引用函数：', log.join(' '));
if (!dry && removed) fs.writeFileSync(F, h);
else if (dry) console.log('DRY');
