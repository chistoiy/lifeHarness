#!/usr/bin/env node
/* 出包预检闸（真机反馈轮4 拍板 2026-10-04）：构建**前**核版本三件套，避免构建完 aapt 才发现不对二次构建。
 * 用法：node tools/prebuild_check.js --code 6051 [--name 0.2.10] [--split] [--dir <构建目录=worktree>]
 * 检查项：
 *  1) pubspec version 的 versionName 与 --name（缺省取 pubspec 现值）一致；
 *  2) android/local.properties 钉版行：存在 flutter.versionCode/versionName 时必须与期望值一致
 *     （本机教训：pubspec 改了还要核 local.properties 钉版）；
 *  3) --split（--split-per-abi）：红——复测包口径＝universal 单包；实测 split 会给 arm64 versionCode
 *     加 +2000 偏移（6051→8051），装机和 aapt 核销全被打乱。确需分包必须显式 --split 并把期望值改为 base+偏移。
 * 通过后打印「构建后 aapt 复验清单」。任一红 exit 1。
 */
const fs = require('fs');
const path = require('path');
const a = process.argv.slice(2);
const arg = (k) => { const i = a.indexOf('--' + k); return i >= 0 ? a[i + 1] : null; };
const dir = arg('dir') || '.';
const wantCode = arg('code') ? Number(arg('code')) : null;
const split = a.includes('--split');
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
  if (c && wantCode && Number(c[1]) !== wantCode)
    fails.push(`local.properties 钉 flutter.versionCode=${c[1]} ≠ 期望 ${wantCode}（构建会吃钉版值）`);
  if (n && wantName && n[1] !== wantName)
    fails.push(`local.properties 钉 flutter.versionName=${n[1]} ≠ 期望 ${wantName}`);
  oks.push(`local.properties 钉版：${c ? 'versionCode=' + c[1] : '未钉（走 pubspec/--build-number）'}`);
} catch (e) { fails.push('读 android/local.properties 失败：' + e.message); }

// 3) split-per-abi 偏移闸
if (split)
  fails.push('复测包禁 --split-per-abi：实测 split 使 arm64 versionCode=base+2000（如 6051→8051）；'
    + '请打 universal 单包，或确需分包时把 --code 期望改为 base+偏移并在此说明');

// pubspec build 与期望 code 的关系只提示不拦（正式发版会同步改 pubspec；复测包用 --build-number 不改 pubspec）
if (pubBuild && wantCode && pubBuild !== wantCode && !split)
  oks.push(`提示：pubspec build=${pubBuild} ≠ 期望 ${wantCode} → 构建命令必须带 --build-number ${wantCode}`);

console.log('── prebuild_check ──');
for (const o of oks) console.log('  ok  ' + o);
for (const f of fails) console.log('  ✗   ' + f);
if (fails.length) { console.log(`FAIL(${fails.length})`); process.exit(1); }
console.log('PASS · 构建后必做 aapt 复验：');
console.log(`  1) badging: versionCode=${wantCode} · versionName=${wantName}`);
console.log('  2) 主清单 INTERNET 权限（release 模板只放 debug 的坑）');
console.log('  3) lib/arm64-v8a 库集与上一枚已验包逐一对齐');
console.log('  4) APK mtime 晚于本次构建开始（防挂旧包）');
