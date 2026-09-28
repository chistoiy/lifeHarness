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
  // G7d④：同库拆分有两种包装——extension（巨型 State）与 mixin（公开 API 类）；
  // 一个 part 文件可含多个 mixin（如导出群 + 豆瓣缓存群），故按列 0 的声明行切段分别取证。
  const isWrap = (l) => /^(extension|mixin)\s/.test(l);
  const segs = [];
  let seg = null;
  for (let i = s; i < raw.length; i++) {
    if (isWrap(raw[i])) {
      seg = [];
      segs.push(seg);
      continue;
    }
    if (raw[i] === '}') {
      // 包装体收尾：从段尾退掉空行后丢弃该花括号，并结束此段
      if (seg) {
        while (seg.length && seg[seg.length - 1].trim() === '') seg.pop();
        seg = null;
      }
      continue;
    }
    if (seg) seg.push(raw[i]);
  }
  if (!segs.length) segs.push([]);
  const IGN = '// ignore: invalid_use_of_protected_member';
  const useIgn = process.argv.includes('--allow-ignore');
  // --per-member：一个群的成员在原文件里与「留枢纽层的跨域入口」交错，整段必然不连续，
  // 故按成员声明行把段再切成块（注释吸附规则与 g7d4_repo_split.js 一致），逐块找全等区间。
  const PER = process.argv.includes('--per-member');
  const isDeclRaw = (l) => /^  \S/.test(l) && !/^  [});\]]/.test(l) && !l.trim().startsWith('//');
  const absorbUp = (arr, from) => {
    let k = from;
    while (k > 0 && arr[k - 1].trim() !== '' && /^\s*(@\w+|\/\/|\/\*)/.test(arr[k - 1])) k--;
    return k;
  };
  const splitUnits = (body) => {
    if (!PER) return [body];
    const decls = [];
    for (let i = 0; i < body.length; i++) if (isDeclRaw(body[i])) decls.push(i);
    const starts = decls.map((d) => {
      let s2 = absorbUp(body, d);
      if (s2 - 1 >= 0 && body[s2 - 1].trim() === '') {
        const k2 = absorbUp(body, s2 - 1);
        if (k2 < s2 - 1) s2 = k2;
      }
      return s2;
    });
    const units = [];
    for (let j = 0; j < starts.length; j++) {
      let e = j + 1 < starts.length ? starts[j + 1] - 1 : body.length - 1;
      while (e >= starts[j] && body[e].trim() === '') e--;
      if (e >= starts[j]) units.push(body.slice(starts[j], e + 1));
    }
    return units;
  };
  const found = [];
  let ok = true;
  let why = '';
  for (const seg of segs) {
    const body0 = useIgn ? seg.filter((l) => l.trim() !== IGN) : seg;
    for (const body of splitUnits(body0)) {
      while (body.length && body[body.length - 1].trim() === '') body.pop();
      if (!body.length) continue;
      totalBody += body.length;
      totalIgn += useIgn ? body0.length - body.length : 0;
      let at = -1;
      for (let i = 0; i + body.length <= baseLines.length; i++) {
        let m = true;
        for (let j = 0; j < body.length; j++)
          if (baseLines[i + j] !== body[j]) {
            m = false;
            break;
          }
        if (m) {
          at = i + 1;
          break;
        }
      }
      if (at < 0) {
        ok = false;
        why = `块首行=${JSON.stringify(body[0])} 长=${body.length}`;
        break;
      }
      found.push({ lines: body.length, at });
    }
    if (!ok) break;
  }
  if (!ok) {
    console.log(`NO-CONTIG-MATCH ${f} ${why}`);
    fail++;
    continue;
  }
  const span = found.map((x) => `L${x.at}(+${x.lines})`).join(' ');
  const sum = found.reduce((a, x) => a + x.lines, 0);
  console.log(`OK ${f} 块=${found.length} 计${sum}行 ${span}`);
}
console.log(
  `${fail === 0 ? 'PURE-MOVE-VERIFIED' : `PURE-MOVE-FAIL count=${fail}`} 合计行数=${totalBody}·剔除定点 ignore=${totalIgn}`,
);
process.exit(fail === 0 ? 0 : 1);
