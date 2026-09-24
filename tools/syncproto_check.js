// tools/syncproto_check.js — index-sync.html 数据与同步专版原型校验（V1.41 批次 Task 2）
// 断言：逐屏 id 存在 / 钉死文案存在 / provider 切 S3 后表单标签映射含 Access Key·Secret Key /
//       教学句式 0 命中 / emoji 码点 0 命中 / 处理器与 id 接线完整。
// 优先 jsdom 真 DOM 断言，jsdom 不可用退化为正则断言。用法：node tools/syncproto_check.js [文件路径]
const fs = require('fs');
const F = process.argv[2] || 'prototype/index-sync.html';
const s = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
let bad = 0;
const ok = (cond, label) => { console.log((cond ? 'PASS ' : 'FAIL ') + label); if (!cond) bad++; };

/* ---------- 0) 单文件约束：无外部资源 ---------- */
ok(!/<link[^>]+href="http|<script[^>]+src=/.test(s), '无外部资源引用（link http / script src）');

/* ---------- 1) 逐屏 id 存在 ---------- */
const SCREENS = ['p-sync', 'p-log', 'p-synchist'];
const SHEETS = ['s-svc-edit', 's-svc-verify', 's-diff', 's-syncprog', 's-backup', 's-throttle'];
for (const id of SCREENS) ok(new RegExp('<section id="' + id + '" class="page').test(s), '屏 id 存在: ' + id);
for (const id of SHEETS) ok(new RegExp('<div class="sheet" id="' + id + '"').test(s), '弹层 id 存在: ' + id);

/* ---------- 2) 钉死文案 ---------- */
const TEXTS = [
  ['坚果云 · WebDAV', '服务卡默认 坚果云 · WebDAV'],
  ['缤纷云 · S3', '切换示例 缤纷云 · S3'],
  ['已用 1.2 GB / 共 3 GB', 'WebDAV 有配额进度条文案'],
  ['已用 22.6 KB', 'S3 仅有已用量文案'],
  ['桶级求和 · 无配额概念', '缤纷云条目 桶级求和/无配额概念 注线'],
  ['42 条', '一致组折叠计数 42 条'],
  [/\d{2}:\d{2}:\d{2}\.\d{3}/, '日志时间戳含毫秒 HH:mm:ss.SSS'],
  ['badge-s3', 'S3 协议徽标样式'],
  ['staleHint', '残留提示样式 staleHint'],
  ['仅本地', '差异态 仅本地'],
  ['仅云端', '差异态 仅云端'],
  ['已修改', '差异态 已修改'],
  ['一致', '差异态 一致（折叠计数）'],
  [/上传 \d+ · 下载 \d+ · 共 [\d.]+ MB/, '差异底部合计「上传 n · 下载 m · 共 xx MB」'],
  ['下载', '「仅云端」行下载按钮'],
  ['被限流，等待 8s', '进度行被限流示例态'],
  ['取消', '进度半屏取消钮'],
  ['复制全部（300）', '日志复制全量按钮'],
  ['窗口 · 最近 120 条', '日志顶部窗口示意'],
  ['data-flt="all"', '级别 chip 全部'],
  ['data-flt="warn"', '级别 chip 警告+'],
  ['data-flt="error"', '级别 chip 错误'],
  ['保留天数', '保留天数设置'],
  [/witem[^>]*>7 天/, '保留天数滚轮档 7'],
  [/witem on[^>]*>14 天/, '保留天数滚轮默认 14'],
  [/witem[^>]*>30 天/, '保留天数滚轮档 30'],
  ['仅存本机加密区', '凭据行加密区状态点'],
  [/150ms[\s\S]{0,160}300ms[\s\S]{0,160}800ms/, '节流三档 150/300/800ms'],
  [/seg-btn on[^>]*>300ms/, '节流默认选中 300ms'],
  [/witem on[^>]*>5 份/, '快照份数 N 滚轮默认 5'],
  ['仅 Wi-Fi 自动同步', '仅 Wi-Fi 开关行'],
  [/class="toggle" id="tglWifi"/, '仅 Wi-Fi 开关默认关'],
  ['立即同步', 'P1 立即同步入口'],
  ['差异对比', 'P1 差异对比入口'],
  ['备份导出/导入', 'P1 备份导出/导入入口'],
  ['控流', 'P1 控流入入口'],
  ['同步历史', 'P1 同步历史入口'],
  ['切换服务', 'P1 切换服务列表'],
  ['PROPFIND Depth:0', 'S2 WebDAV 探针'],
  ['list-type=2&max-keys=1', 'S2 S3 探针'],
  [/\['凭据错误'/, 'S2 凭据错误态'],
  [/\['网络失败'/, 'S2 网络失败态'],
  ['目标位置', 's-backup 导出目标位置选择行（V1.41 增补）'],
  ['另存到…', 's-backup 目标位置「另存到…」态'],
  ['保存为', 'SAF「保存为」静态 mock 弹层标题'],
  [/id="safMock"[\s\S]{0,220}保存为/, 'mock 弹层容器 #safMock 含「保存为」标题']
];
for (const [t, label] of TEXTS) ok(typeof t === 'string' ? s.includes(t) : t.test(s), '文案: ' + label);

/* ---------- 2b) s-backup 目标位置两态（V1.41 增补） ---------- */
ok(s.indexOf('<label>目标位置</label>') < s.indexOf('口令 · 可选'), '目标位置行位于「口令」区之前');
ok(/class="seg-btn on" onclick="pickBakDest\(this,'app'\)">应用目录（默认）<\/button>/.test(s), '目标位置默认态选中「应用目录（默认）」');
ok(/class="seg-btn" onclick="pickBakDest\(this,'saf'\)">另存到…<\/button>/.test(s), '目标位置第二态「另存到…」未选中');

/* ---------- 3) provider 切 S3 表单标签静态映射 ---------- */
const formMap = s.match(/var PROVIDER_FORMS = \{[\s\S]*?\n\};/);
ok(!!formMap, 'PROVIDER_FORMS 映射数据存在');
if (formMap) {
  const m = formMap[0];
  const s3 = m.slice(m.indexOf('s3:'));
  ok(/label:'Access Key'/.test(s3), "S3 字段标签含 'Access Key'");
  ok(/label:'Secret Key'/.test(s3), "S3 字段标签含 'Secret Key'");
  ok(/label:'Endpoint'/.test(s3) && /https:\/\/s3\.bitiful\.net/.test(s3) && /cn-east-1/.test(s3), 'S3 写死 endpoint/region');
  const wd = m.slice(m.indexOf('webdav:'), m.indexOf('s3:'));
  ok(/label:'地址'/.test(wd) && /label:'账户'/.test(wd) && /label:'应用密码'/.test(wd), 'WebDAV 字段=地址/账户/应用密码');
}
const capMap = s.match(/var PROVIDERS = \{[\s\S]*?\n\};/);
ok(!!capMap && /cap:'quota'/.test(capMap[0]) && /cap:'usedOnly'/.test(capMap[0]) && /cap:'none'/.test(capMap[0]), '容量三态 quota/usedOnly/none 映射齐全');

/* ---------- 4) 教学句式 0 命中 ---------- */
for (const p of ['你可以', '提示：', '首先']) {
  const n = (s.match(new RegExp(p, 'g')) || []).length;
  ok(n === 0, '教学句式「' + p + '」0 命中' + (n ? '（实际 ' + n + '）' : ''));
}

/* ---------- 5) emoji 码点 0 命中 ---------- */
const EM = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{1F1E6}-\u{1F1FF}]/gu;
const hits = [...new Set(s.match(EM) || [])];
ok(hits.length === 0, 'emoji 码点 0 命中' + (hits.length ? '：' + hits.join(' ') : ''));

/* ---------- 6) 处理器与 id 接线（ledgercheck 同思路） ---------- */
const decl = new Set();
for (const m of s.matchAll(/function\s+([A-Za-z_$][\w$]*)/g)) decl.add(m[1]);
for (const m of s.matchAll(/var\s+([A-Za-z_$][\w$]*)\s*=/g)) decl.add(m[1]);
const builtin = new Set(['if', 'for', 'while', 'switch', 'return', 'typeof', 'event', 'this', 'window', 'document', 'Math', 'Number', 'String', 'Array', 'Object', 'JSON', 'Date', 'setTimeout', 'clearTimeout', 'parseInt', 'parseFloat', 'isNaN', 'console', 'Set', 'Map']);
const undef = new Map();
for (const m of s.matchAll(/\bon(?:click|input|change)=\\?["'`]([^"'`]+)/g)) {
  for (const c of m[1].matchAll(/(^|[^.\w$])([A-Za-z_$][\w$]*)\s*\(/g)) {
    if (!builtin.has(c[2]) && !decl.has(c[2])) undef.set(c[2], (undef.get(c[2]) || 0) + 1);
  }
}
ok(undef.size === 0, '内联处理器函数全部已定义' + (undef.size ? '：缺 ' + [...undef.keys()].join(' ') : ''));
const miss = new Set();
for (const m of s.matchAll(/\$\('#([\w-]+)'\)/g)) {
  if (!new RegExp('id="' + m[1] + '"').test(s)) miss.add(m[1]);
}
ok(miss.size === 0, '$() 字面量目标 id 全部存在' + (miss.size ? '：缺 ' + [...miss].join(' ') : ''));

/* ---------- 7) jsdom 增强（可用则跑，不可用退化为以上正则断言） ---------- */
try {
  const { JSDOM } = require('jsdom');
  const dom = new JSDOM(s.replace(/<script>[\s\S]*?<\/script>/g, ''), { url: 'file:///原型' });
  const d = dom.window.document;
  for (const id of SCREENS.concat(SHEETS)) ok(!!d.getElementById(id), 'jsdom DOM id: ' + id);
  ok(d.querySelectorAll('#s-diff .d-row [data-dir="up"]').length >= 2 && d.querySelectorAll('#s-diff .d-row [data-dir="down"]').length >= 2, 'jsdom 差异四态示例条目充足');
  var destBtns = Array.prototype.slice.call(d.querySelectorAll('#s-backup #segBakDest .seg-btn'));
  ok(destBtns.length === 2 && destBtns[0].classList.contains('on') && /应用目录/.test(destBtns[0].textContent), 'jsdom 目标位置两态单选且默认选中应用目录');
  ok(!!d.getElementById('safMock') && /保存为/.test(d.getElementById('safMock').textContent), 'jsdom #safMock「保存为」弹层存在');
  console.log('jsdom: 已启用真 DOM 断言');
} catch (e) {
  console.log('jsdom 不可用（' + e.code + '），已退化为正则断言');
}

console.log(bad ? 'RESULT: ISSUES ' + bad : 'RESULT: PASS');
process.exit(bad ? 1 : 0);
