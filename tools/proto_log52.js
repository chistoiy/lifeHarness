// R14-11 原型先行：日志行改单栏行内流 + 倒序（最新在上）+ 堆栈行折叠展开
// 用法：node tools/proto_log52.js      （命中断言 + 体积校验，改前自动快照）
const fs = require('fs');
const P = 'prototype/index.html';
const snap = 'tools/attic/proto_log52.bak.html';
let s = fs.readFileSync(P, 'utf8');
const before = s.length;
fs.writeFileSync(snap, s, 'utf8');

function rep(a, b, label) {
  const n = s.split(a).length - 1;
  if (n !== 1) { console.error(`ANCHOR ${label}: 命中 ${n} 次（需恰好 1）`); process.exit(1); }
  s = s.replace(a, b);
}

/* ---------- 1) CSS：去分栏，改行内流 ---------- */
rep(
  '  .logline{display:flex;gap:7px;font-family:ui-monospace,Consolas,Menlo,monospace;font-size:1em;line-height:1.8;padding:5px 12px;border-bottom:1px solid color-mix(in srgb,var(--card-bd) 60%,transparent)}',
  '  .logline{font-family:ui-monospace,Consolas,Menlo,monospace;font-size:1em;line-height:1.7;padding:5px 12px;border-bottom:1px solid color-mix(in srgb,var(--card-bd) 60%,transparent)}\n' +
  '  /* V1.53.4 R14-11：日志行不分栏（时间/级别/来源/正文同一段行内流，长内容不再被挤进右栏） */\n' +
  '  .logline>span{display:inline}',
  'CSS-logline');

rep('  .logline .lt{color:#94a3b8;flex-shrink:0}', '  .logline .lt{color:#94a3b8}', 'CSS-lt');
rep('  .logline .ll{flex-shrink:0;font-weight:800;width:3.4em;color:#0ea5e9}', '  .logline .ll{font-weight:800;color:#0ea5e9}', 'CSS-ll');
rep(
  '  .logline .ls{flex-shrink:0;align-self:flex-start;margin-top:2px;font-size:9px;font-weight:800;color:#64748b;background:color-mix(in srgb,var(--accent) 12%,transparent);border-radius:5px;padding:1px 5px}',
  '  .logline .ls{font-size:9px;font-weight:800;color:#64748b;background:color-mix(in srgb,var(--accent) 12%,transparent);border-radius:5px;padding:1px 5px}',
  'CSS-ls');
rep('  .logline .lm{flex:1;min-width:0;color:#0f172a;word-break:break-all}', '  .logline .lm{color:#0f172a}', 'CSS-lm');

/* 堆栈折叠件样式（挂在 ERROR 底色规则之后） */
rep(
  '  .logline.lv-ERROR{background:color-mix(in srgb,#ef4444 6%,transparent)}',
  '  .logline.lv-ERROR{background:color-mix(in srgb,#ef4444 6%,transparent)}\n' +
  '  /* V1.53.4 R14-11：回填堆栈行默认折一行，点开看全文（否则单条吃掉整屏，最新日志被顶出屏幕） */\n' +
  '  .logline .lstk{display:block;color:#94a3b8;word-break:break-all}\n' +
  '  .logline .lstk:not(.open){max-height:1.7em;overflow:hidden}\n' +
  '  .logline .lmore{display:inline-block;font-size:9px;font-weight:800;color:var(--accent);border:1px solid color-mix(in srgb,var(--accent) 30%,transparent);border-radius:5px;padding:0 5px;margin-top:2px;cursor:pointer}',
  'CSS-stk');

/* ---------- 2) 顶部说明条补「最新在上」 ---------- */
rep(
  '<span class="truncate">窗口 120 条 · 缓冲 300 · 落盘按天 · 单文件 5 MB</span>',
  '<span class="truncate">窗口 120 条 · 缓冲 300 · 落盘按天 · 单文件 5 MB · 最新在上</span>',
  'HDR');

/* ---------- 3) 日志行：倒序 + 新增堆栈样例 ---------- */
const first = '        <div class="logline lv-INFO"  data-lv="INFO" data-src="同步" oncontextmenu="event.preventDefault();copyLogLine(this)">\n          <span class="lt">09-27 08:29:58.412</span>';
const lastClose = '          <span class="lm">ISBN 未命中（9787108009821）· 已按书名《万历十五年》在豆瓣匹配补全</span>\n        </div>\n      </div>';
const i0 = s.indexOf(first);
const i1 = s.indexOf(lastClose);
if (i0 < 0 || i1 < 0 || i1 <= i0) { console.error('RANGE FAIL 日志行区间未定位'); process.exit(2); }

const L = (ts, lv, tag, src, msg) =>
  `        <div class="logline lv-${lv}" data-lv="${lv}" data-src="${src}" oncontextmenu="event.preventDefault();copyLogLine(this)">\n` +
  `          <span class="lt">${ts}</span> <span class="ll">${tag}</span> <span class="ls">${src}</span> <span class="lm">${msg}</span>\n` +
  `        </div>`;

const stk =
  `        <div class="logline lv-ERROR" data-lv="ERROR" data-src="异常" oncontextmenu="event.preventDefault();copyLogLine(this)">\n` +
  `          <span class="lt">09-27 08:32:10.874</span> <span class="ll">ERR </span> <span class="ls">异常</span>\n` +
  `          <span class="lm">‼️ FlutterError: 'package:flutter/src/widgets/navigator.dart': Failed assertion: line 4646: no route on initial route '/read/book/1'\n` +
  `            <span class="lstk" id="logStk1">#0 NavigatorState._routeNamed (navigator.dart:4646) | #1 NavigatorState.pushNamed (navigator.dart:4714) | #2 _ReaderPageState._openMoreSheet (reader_page.dart:579) | #3 showBrMoreSheet (reader_bottom_sheets.dart:292) | #4 RenderBinding.scheduleFrame (binding.dart:1188) | #5 WidgetTester.pumpWidget (widget_tester.dart:612)</span>\n` +
  `            <span class="lmore" onclick="logStkToggle(this)">展开堆栈</span></span>\n` +
  `        </div>`;

const lines = [
  L('09-27 08:31:04.007', 'WARN', 'WARN', '阅读', 'ISBN 未命中（9787108009821）· 已按书名《万历十五年》在豆瓣匹配补全'),
  L('09-27 08:31:03.418', 'INFO', 'INFO', 'AI', 'AI 调用成功（read.toc）· 13443ms · 入 173/出 4216 tokens'),
  L('09-27 08:31:03.155', 'INFO', 'INFO', '系统', 'FileLogSink 刷盘 logs/2026-09-24.log · 保留 14 天'),
  L('09-27 08:31:03.007', 'INFO', 'INFO', '同步', '同步摘要 · 上传 3 · 下载 2 · 272.2 MB · 结果成功 · 详情见日志窗口'),
  L('09-27 08:31:02.871', 'WARN', 'WARN', '备份', '台账残留判定：snapshot_20260918_075541.lhbak 仅云端 · 本机已删'),
  L('09-27 08:31:02.144', 'ERROR', 'ERR ', '同步', 'S3 GET /?list-type=2 失败 · 缤纷云 连接超时 30s · 已转失败清单'),
  stk,
  L('09-27 08:30:38.026', 'INFO', 'INFO', '同步', 'MKCOL /LifeHarness/sync/logs/ → 405 · 进程内记忆命中，跳过'),
  L('09-27 08:30:12.660', 'INFO', 'INFO', '备份', 'put snapshot_20260924_083000.lhbak 完成 · 128.4 MB · StreamedRequest'),
  L('09-27 08:30:04.219', 'WARN', 'WARN', '同步', '429 Too Many Requests · Retry-After: 8 · 退避重发 1/3 · 请求工厂重建'),
  L('09-27 08:30:01.771', 'INFO', 'INFO', '同步', '差异结果：仅本地 2 · 仅云端 2 · 已修改 1 · 一致 42 · 字节数档'),
  L('09-27 08:29:59.941', 'INFO', 'INFO', '同步', 'getUserInfo → 配额 3 GB · 已用 1.2 GB · 缓存 5min'),
  L('09-27 08:29:59.033', 'INFO', 'INFO', '同步', 'PROPFIND Depth:1 /LifeHarness/sync/ → 207 · 412ms · Authorization: 已脱敏'),
  L('09-27 08:29:58.412', 'INFO', 'INFO', '同步', '同步任务启动 · 坚果云 WebDAV · HttpGate 间隔 300ms'),
].join('\n');

s = s.slice(0, i0) + '        <!-- V1.53.4 R14-11：倒序（最新在上）· 单栏行内流 · 堆栈行默认折叠 -->\n'
  + lines + '\n      </div>' + s.slice(i1 + lastClose.length);

/* ---------- 4) JS：堆栈折叠开关 ---------- */
rep(
  'function copyAllLogs(){',
  'function logStkToggle(el){\n' +
  "  var box=el.parentElement.querySelector('.lstk');if(!box)return;\n" +
  "  var open=box.classList.toggle('open');\n" +
  "  el.textContent=open?'收起堆栈':'展开堆栈';\n" +
  '}\n' +
  'function copyAllLogs(){',
  'JS-toggle');

/* ---------- 5) 体积与结构校验 ---------- */
const after = s.length;
if (after < before * 0.9) { console.error(`SIZE GUARD: ${before} -> ${after} 体积异常收缩`); process.exit(3); }
const cnt = (re) => (s.match(re) || []).length;
console.log('logline 行数 =', cnt(/class="logline/g), '（期望 14）');
console.log('折叠堆栈 =', cnt(/lstk/g), '· 展开钮 =', cnt(/logStkToggle/g), '（期望 4/2）');
console.log('残留分栏 CSS =', cnt(/\.logline \.(lt|ll|ls|lm)\{[^}]*flex-shrink/g), '（期望 0）');
console.log(`体积 ${before} -> ${after}`);
if (cnt(/class="logline/g) !== 14) { console.error('COUNT FAIL'); process.exit(4); }
fs.writeFileSync(P, s, 'utf8');
console.log('OK 写入', P, '· 备份', snap);
