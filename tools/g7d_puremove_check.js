// 治理G7d 通用纯移动取证：part 文件的搬运算块必须在上游基线主文件中逐行连续全等出现
// （头部 part of / 说明注释 / extension 声明行、尾部收尾花括号除外）。
// 用法：node tools/g7d_puremove_check.js --base d3d1773 --main shelf_page.dart \
//          --dir lib/features/read/presentation/shelf --parts a.dart,b.dart
// 一次性脚本，用完入 tools/attic。
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const arg = (k, d) => {
  const i = process.argv.indexOf('--' + k);
  return i >= 0 ? process.argv[i + 1] : d;
};
const BASE = arg('base');
const MAIN = arg('main');
const DIR = arg('dir');
const parts = arg('parts', '').split(',').filter(Boolean);
// --allow-ignore：比对前剔除 G7c/G7d 式定点 `// ignore: invalid_use_of_protected_member`
// （extension 内 setState 所需的行为零改动注释），其余行仍要求逐行连续全等。
const ALLOW_IGNORE = process.argv.includes('--allow-ignore');
const SRC_REL = `${DIR}/${MAIN}`;
if (!BASE || !MAIN || !DIR || !parts.length) {
  console.error('USAGE: --base <ref> --main <file.dart> --dir <dir> --parts a.dart,b.dart');
  process.exit(1);
}

const norm = (s) => s.replace(/\r\n/g, '\n');
const baseLines = norm(
  execSync(`git show ${BASE}:${SRC_REL}`, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }),
).split('\n');

let fail = 0;
let totalBody = 0;
let totalIgn = 0;
for (const f of parts) {
  const raw = norm(fs.readFileSync(path.join(DIR, f), 'utf8')).split('\n');
  if (raw[0] !== `part of '${MAIN}';`) {
    console.log(`HEAD-FAIL ${f}`);
    fail++;
    continue;
  }
  let s = 1;
  while (s < raw.length && (raw[s].trim() === '' || raw[s].trim().startsWith('//'))) s++;
  if (raw[s] && raw[s].startsWith('extension ')) s++;
  let e = raw.length - 1;
  while (e > s && raw[e].trim() === '') e--;
  if (raw[e].trim() === '}') e--;
  const rawBody = raw.slice(s, e + 1);
  // --allow-ignore：setState 定点 ignore 注释属治理批的机械插入，比对前剔除
  const IGN = '// ignore: invalid_use_of_protected_member';
  const useIgn = process.argv.includes('--allow-ignore');
  const body = useIgn ? rawBody.filter((l) => l.trim() !== IGN) : rawBody;
  totalBody += body.length;
  totalIgn += useIgn ? rawBody.length - body.length : 0;
  let at = -1;
  for (let i = 0; i + body.length <= baseLines.length; i++) {
    let ok = true;
    for (let j = 0; j < body.length; j++)
      if (baseLines[i + j] !== body[j]) {
        ok = false;
        break;
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
console.log(
  `${fail === 0 ? 'PURE-MOVE-VERIFIED' : `PURE-MOVE-FAIL count=${fail}`} 合计行数=${totalBody}·剔除定点 ignore=${totalIgn}`,
);
process.exit(fail === 0 ? 0 : 1);
