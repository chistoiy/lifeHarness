#!/usr/bin/env node
/* 出包预检闸（真机反馈轮4 拍板 2026-10-04）：构建**前**核版本三件套，避免构建完 aapt 才发现不对二次构建。
 * 用法：node tools/prebuild_check.js --code 6051 [--name 0.2.10] [--split] [--dir <构建目录=worktree>]
 * 检查项：
 *  1) pubspec version 的 versionName 与 --name（缺省取 pubspec 现值）一致；
 *  2) android/local.properties 钉版行：存在 flutter.versionCode/versionName 时必须与期望值一致
 *     （本机教训：pubspec 改了还要核 local.properties 钉版）；
 *  3) --split（--split-per-abi）：2026-10-05 拍板后为合法形态——复测包与机上包统一 arm64 分包。
 *     传 --split 时 --code＝**装机期望编号**（60xx），实测 arm64 产物＝base+2000，构建 base＝code-2000；
 *     local.properties 钉版与 --build-number 都必须用 base。期望值低于偏移会判「误传 base」红。
 *     不带 --split＝universal（机上仍是 universal 期间照旧），形态必须与机上包一致。
 * 通过后打印「构建后 aapt 复验清单」。任一红 exit 1。
 */
const fs = require('fs');
const path = require('path');
const a = process.argv.slice(2);
const arg = (k) => { const i = a.indexOf('--' + k); return i >= 0 ? a[i + 1] : null; };
const dir = arg('dir') || '.';
const wantCode = arg('code') ? Number(arg('code')) : null;
const split = a.includes('--split');
// arm64 分包偏移（实测 --split-per-abi 给 arm64 产物 +2000）：--code 给装机期望值，base＝期望-偏移。
const ARM64_OFFSET = 2000;
let buildBase = wantCode;
if (split && wantCode) buildBase = wantCode - ARM64_OFFSET;
const fails = [];
const oks = [];
if (!wantCode) fails.push('必须给 --code（本次出包期望 versionCode，复测包＝60xx 编号）');

// 1) pubspec
let pubName = null, pubBuild = null;
try {
  const m = fs.readFileSync(path.join(dir, 'pubspec.yaml'), 'utf8')
    .match(/^version:\s*(\S+)\+(\d+)\s*$/m);
  if (!m) fails.push('pubspec.yaml 找不到 version: x.y.z+build 行');
  else { pubName = m[1]; pubBuild = Number(m[2]); }
} catch (e) { fails.push('读 pubspec 失败：' + e.message); }
const wantName = arg('name') || pubName;
if (wantName && pubName && pubName !== wantName)
  fails.push(`pubspec versionName=${pubName} ≠ 期望 ${wantName}`);
else if (pubName) oks.push(`pubspec versionName=${pubName}`);

// 2) local.properties 钉版
try {
  const lp = fs.readFileSync(path.join(dir, 'android', 'local.properties'), 'utf8');
  const c = lp.match(/^flutter\.versionCode=(\d+)$/m);
  const n = lp.match(/^flutter\.versionName=(\S+)$/m);
  if (c && wantCode && Number(c[1]) !== buildBase)
    fails.push(`local.properties 钉 flutter.versionCode=${c[1]} ≠ 构建 base ${buildBase}（期望装机 ${wantCode}${split ? '＝base+' + ARM64_OFFSET : ''}；构建会吃钉版值）`);
  if (n && wantName && n[1] !== wantName)
    fails.push(`local.properties 钉 flutter.versionName=${n[1]} ≠ 期望 ${wantName}`);
  oks.push(`local.properties 钉版：${c ? 'versionCode=' + c[1] : '未钉（走 pubspec/--build-number）'}`);
} catch (e) { fails.push('读 android/local.properties 失败：' + e.message); }

// 3) split-per-abi 偏移闸（2026-10-05 拍板改口径：复测包自换机装包起与机上包统一 arm64 分包）
//    --split 时 --code 必须＝**装机期望编号**（如 6067），实测偏移 +2000 → 构建 base＝code-2000；
//    钉版行与 --build-number 都用 base，aapt 复验用 code。形态纪律不变：**与机上包一致**。
// 复测包编号实测区间 60xx（6045~6099）；分包时若 --code 落在这段之外，多半是把 base 当期望传了。
const RETEST_MIN = 6000, RETEST_MAX = 6999;
if (split) {
  if (!wantCode || wantCode < RETEST_MIN || wantCode > RETEST_MAX)
    fails.push(`--split 时 --code 必须＝装机期望编号（复测包 60xx；实测 arm64 产物＝base+${ARM64_OFFSET}）；收到 ${wantCode} → 若你想传 base，请改传期望编号 ${wantCode ? wantCode + ARM64_OFFSET : ''}`);
  else
    oks.push(`分包口径：期望 arm64 versionCode=${wantCode} → 构建 base=${buildBase}（+${ARM64_OFFSET} 偏移）`);
} else {
  oks.push('universal 口径（机上仍是 universal 包期间照旧，勿赌分包）');
}

// pubspec build 与期望 code 的关系只提示不拦（正式发版会同步改 pubspec；复测包用 --build-number 不改 pubspec）
if (pubBuild && buildBase && pubBuild !== buildBase)
  oks.push(`提示：pubspec build=${pubBuild} ≠ 构建 base ${buildBase} → 构建命令必须带 --build-number ${buildBase}`);

console.log('── prebuild_check ──');
for (const o of oks) console.log('  ok  ' + o);
for (const f of fails) console.log('  ✗   ' + f);
if (fails.length) { console.log(`FAIL(${fails.length})`); process.exit(1); }
console.log('PASS · 构建后必做 aapt 复验：');
console.log(`  1) badging: versionCode=${wantCode} · versionName=${wantName}`);
console.log('  2) 主清单 INTERNET 权限（release 模板只放 debug 的坑）');
console.log('  3) lib/arm64-v8a 库集与上一枚已验包逐一对齐');
console.log('  4) APK mtime 晚于本次构建开始（防挂旧包）');
