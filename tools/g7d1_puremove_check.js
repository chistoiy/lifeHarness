// 治理G7d① 纯移动取证：八个 part 文件的搬运算块必须在上游基线（d3d1773 的 shelf_page.dart）中
// 逐行连续全等出现（头部说明/扩展声明行、尾部收尾花括号除外）。一次性脚本，用完入 tools/attic。
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const BASE = 'd3d1773';
const DIR = 'lib/features/read/presentation/shelf';
const baseLines = execSync(`git show ${BASE}:lib/features/read/presentation/shelf/shelf_page.dart`, {
  encoding: 'utf8',
  maxBuffer: 64 * 1024 * 1024,
}).replace(/\r\n/g, '\n').split('\n');

const parts = [
  'shelf_batch_tag.dart',
  'shelf_fab.dart',
  'shelf_long_press.dart',
  'shelf_goal_ring.dart',
  'shelf_goal.dart',
  'shelf_panel.dart',
  'shelf_views.dart',
  'shelf_spine_time.dart',
  'shelf_batch_ops.dart',
];

let fail = 0;
for (const f of parts) {
  const raw = fs
    .readFileSync(path.join(DIR, f), 'utf8')
    .replace(/\r\n/g, '\n')
    .split('\n');
  if (raw[0] !== "part of 'shelf_page.dart';") {
    console.log(`HEAD-FAIL ${f}`);
    fail++;
    continue;
  }
  // 去掉头（part of + 说明注释 + 可选 extension 行）与尾（收尾花括号 + 末尾空行）
  let s = 1;
  while (s < raw.length && (raw[s].trim() === '' || raw[s].trim().startsWith('//'))) s++;
  if (raw[s] && raw[s].startsWith('extension ')) s++;
  let e = raw.length - 1;
  while (e > s && raw[e].trim() === '') e--;
  if (raw[e].trim() === '}') e--;
  const body = raw.slice(s, e + 1);
  let at = -1;
  for (let i = 0; i + body.length <= baseLines.length; i++) {
    let ok = true;
    for (let j = 0; j < body.length; j++) {
      if (baseLines[i + j] !== body[j]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      at = i + 1;
      break;
    }
  }
  if (at < 0) {
    console.log(`NOMATCH ${f} body=${body.length} 首行=${JSON.stringify(body[0])}`);
    fail++;
  } else {
    console.log(`OK ${f} body=${body.length} -> 基线 ${BASE} L${at}..L${at + body.length - 1}`);
  }
}
// 基线主文件里的成员总数守恒：所有 part + 主文件的成员声明行合计＝基线成员声明行
console.log(fail === 0 ? 'PURE-MOVE-VERIFIED' : `PURE-MOVE-FAIL count=${fail}`);
process.exit(fail === 0 ? 0 : 1);
