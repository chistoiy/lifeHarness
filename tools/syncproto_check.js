// tools/syncproto_check.js — index-sync.html 数据与同步专版原型校验（V1.41 批次 Task 2）
// 断言：逐屏 id 存在 / 钉死文案存在 / provider 切 S3 后表单标签映射含 Access Key·Secret Key /
//       教学句式 0 命中 / emoji 码点 0 命中 / 处理器与 id 接线完整。
// 优先 jsdom 真 DOM 断言，jsdom 不可用退化为正则断言。用法：node tools/syncproto_check.js [文件路径]
//
// 【2026-10-16 批 2 修订（高保真体量整改 · 合并式收口）——每处都标了依据，勿再当「闸坏了」】
//   依据＝工单 docs/handoff/交棒话术-20261015-高保真体量整改.md §3 批 2 ＋ 本会话产品六条裁定。
//   ① 屏表：p-log 退役（被 index.html 侧迁入的 p-logs 取代，Q1 合并式收口）；
//      新增批 2 迁入 5 屏（p-sub-data / p-sub-backup / p-sub-dbstats / p-logs / p-sub-mediaclean）
//      ＋迁入 5 弹层（sheetSyncDiff / sheetExport / sheetBkDel / sheetLogSettings / sheetMcDel）。
//      注：迁入弹层是 index.html 写法（class 在前、id 在后），与专版旧弹层（id 在前）不同 → 分开断言。
//   ② 外部资源：Q3「作用域隔离」需 Tailwind CDN（专版原有 3 屏靠 preflight:false 保观感）。
//      故从「零外部资源」改为「只许 Tailwind CDN」；**Google Fonts 明令禁止**——实测引 Inter 会改
//      本版原有屏的文字折行（p-sync 卡 150→135px、「最近同步」行两行变一行）＝违反铁律⑥ 只搬不改。
//   ③ 日志文案：8 条原属已退役的 p-log（复制全部（300）/ 窗口·最近 120 条 / data-flt 三 chip /
//      保留天数滚轮）。活日志屏改为迁入的 p-logs，断言按其真实结构重写（见下）。
//   ④ emoji：专版自有区仍零命中；迁入区按 index.html 源屏口径（`✓ ⬇ ⬆ ️` 是壳层既有字形，
//      铁律⑥ 只搬不改 ⇒ 不许在本批就地清）。迁入区逐字同源由注册表 hash 相等自证。
//   ⑤ `$()` 目标：pfMcCnt 现属「跨文件入口行」——行留在 index.html 的 p-profile（家未迁），
//      更新方 mcRender() 随 p-sub-mediaclean 迁入本版 ⇒ 本版取不到该节点（代码已 `if(pf)` 守卫，
//      且静态值「6 个」＝MC_FILES.length，观感无差）。属既定过渡态，白名单豁免并记于此。
const fs = require('fs');
const F = process.argv[2] || 'prototype/index-sync.html';
const s = fs.readFileSync(F, 'utf8').replace(/\r\n/g, '\n');
let bad = 0;
const ok = (cond, label) => { console.log((cond ? 'PASS ' : 'FAIL ') + label); if (!cond) bad++; };

/* ---------- 0) 单文件约束：只许 Tailwind CDN（批 2 Q3）；禁 Google Fonts（见头注释 ②） ---------- */
{
  const externals = [...s.matchAll(/<link[^>]+href="(https?:[^"]+)"|<script[^>]+src="(https?:[^"]+)"/g)]
    .map(m => m[1] || m[2]);
  ok(externals.length === 1 && /^https:\/\/cdn\.tailwindcss\.com\/?$/.test(externals[0]),
    '外部资源只许 Tailwind CDN' + (externals.length ? '（实际 ' + externals.join(' ') + '）' : ''));
  ok(!/fonts\.googleapis\.com|fonts\.gstatic\.com/.test(s), '禁 Google Fonts（引它会改原有屏折行）');
}

/* ---------- 1) 逐屏 id 存在 ---------- */
/* 专版自有（原 p-log 已退役，见头注释 ①） */
const SCREENS = ['p-sync', 'p-synchist'];
/* 批 2 迁入屏（家＝本专版） */
const SCREENS_B2 = ['p-sub-data', 'p-sub-backup', 'p-sub-dbstats', 'p-logs', 'p-sub-mediaclean'];
const SHEETS = ['s-svc-edit', 's-svc-verify', 's-diff', 's-syncprog', 's-backup', 's-throttle'];
/* 批 2 迁入弹层（index.html 写法：class 在前 id 在后） */
const SHEETS_B2 = ['sheetSyncDiff', 'sheetExport', 'sheetBkDel', 'sheetLogSettings', 'sheetMcDel'];
for (const id of SCREENS) ok(new RegExp('<section id="' + id + '" class="page').test(s), '屏 id 存在: ' + id);
for (const id of SCREENS_B2) ok(new RegExp('<section id="' + id + '" class="page').test(s), '批2 迁入屏 id 存在: ' + id);
for (const id of SHEETS) ok(new RegExp('<div class="sheet" id="' + id + '"').test(s), '弹层 id 存在: ' + id);
for (const id of SHEETS_B2) ok(new RegExp('<div id="' + id + '" class="sheet[^"]*"').test(s), '批2 迁入弹层 id 存在: ' + id);

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
  /* —— 日志屏：批2 起断言活屏 p-logs（迁入件）；原 p-log 的 8 条随屏退役（头注释 ③） —— */
  ['复制全部', '日志复制全量按钮（p-logs）'],
  ['窗口 120 条 · 缓冲 300 · 落盘按天 · 单文件 5 MB · 最新在上', '日志顶部窗口示意（p-logs）'],
  [/id="logLvAll"[\s\S]{0,200}logLvSet\('all'[\s\S]{0,600}logLvSet\('warn'[\s\S]{0,400}logLvSet\('error'/, '级别三档 全部/警告+/错误（p-logs）'],
  [/data-lv="WARN"/, '日志行级别标 WARN（p-logs）'],
  [/data-lv="ERROR"/, '日志行级别标 ERROR（p-logs）'],
  [/落盘日志保留[\s\S]{0,240}id="logKeep"/, '保留天数设置（p-logs）'],
  [/id="logKeepVal"[^>]*>14 天/, '保留天数默认 14 天（p-logs）'],
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
  ['导出备份', 's-backup 导出动作钮'],
  ['另存到…', 's-backup 另存动作钮（R6 一步到位）'],
  ['保存为', 'SAF「保存为」静态 mock 弹层标题'],
  [/id="safMock"[\s\S]{0,220}保存为/, 'mock 弹层容器 #safMock 含「保存为」标题']
];
for (const [t, label] of TEXTS) ok(typeof t === 'string' ? s.includes(t) : t.test(s), '文案: ' + label);

/* ---------- 2b) s-backup R6 一步动作钮（导出备份 / 另存到… 并列） ---------- */
ok(s.indexOf('id="segBakDest"') < 0, 'R6 目标位置两态选择行已删除');
ok(/onclick="openSafMock\(\)">另存到…<\/button>/.test(s), 'R6「另存到…」钮直连 openSafMock（点即弹系统保存层）');
ok(s.indexOf('>导出备份</button>') < s.indexOf('>另存到…</button>'), 'R6 导出备份在左、另存到…在右并列');

/* ---------- 2c) R2⑤：s-svc-edit 眼睛钮+协议锁定 / p-sync 常驻添加服务 ---------- */
ok(/\.pill\.locked\{opacity:\.45;cursor:not-allowed\}/.test(s), 'R2⑤b pill 置灰锁定样式 .pill.locked 存在');
ok(/class="pill on locked" data-prov="webdav"/.test(s) && /class="pill locked" data-prov="s3"/.test(s), 'R2⑤b s-svc-edit 默认编辑态：两协议 pill 初始置灰');
ok(/id="svcProvLockNote"[^>]*>编辑已建服务 · 协议已锁定/.test(s), 'R2⑤b 编辑态协议锁定提示行');
ok(/onclick="openSvcEdit\('edit'\)">编辑配置/.test(s), 'R2⑤b 编辑配置入口走 openSvcEdit(edit)');
ok(/onclick="openSvcEdit\('add'\)"/.test(s), 'R2⑤c 添加服务入口走 openSvcEdit(add)（解锁协议可切）');
ok(/function openSvcEdit\(mode\)/.test(s) && /svcEditMode === 'edit'/.test(s) && /协议已锁定 · 请走「添加服务」/.test(s), 'R2⑤b editProvider 编辑态守卫+toast');
ok(/id="rowAddSvc"/.test(s) && s.includes('添加服务'), 'R2⑤c p-sync 切换服务区常驻「添加服务」行 #rowAddSvc');
ok(/class="eye-btn" type="button" onclick="toggleSecret\(this\)"/.test(s), 'R2⑤a SK 行尾眼睛钮（线性 SVG 双态）');
ok(/function toggleSecret\(b\)[\s\S]{0,220}type = show \? 'text' : 'password'/.test(s), 'R2⑤a toggleSecret 切 password/text 显隐');
ok(/if\(f\.type === 'password'\) inp = '<div class="inwrap">'/.test(s), 'R2⑤a password 字段带 inwrap+眼睛钮渲染');
ok(/label:'应用密码',\s*value:'demo-apppw-7f2c',\s*type:'password'/.test(s) && /label:'Secret Key',\s*value:'demo-sk-4a71c0f2',\s*type:'password'/.test(s), 'R2⑤a 编辑态 SK 回填示意（假演示值，掩码下藏可显真值）');

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

/* ---------- 5) emoji 码点 0 命中（只查专版自有区；批2 迁入区按源屏口径，见头注释 ④） ---------- */
const EM = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{1F1E6}-\u{1F1FF}]/gu;
/* 迁入区＝`<div id="shl">` 到其配平闭合（标记 `</div><!-- /shl -->`）；只对区外做零命中断言 */
const SHL_START = s.indexOf('<div id="shl">');
const SHL_END = s.indexOf('<!-- /shl -->');
const shlOk = SHL_START >= 0 && SHL_END > SHL_START;
ok(shlOk, '批2 迁入区 #shl 边界可识别');
const outside = shlOk ? (s.slice(0, SHL_START) + s.slice(SHL_END)) : s;
const hits = [...new Set(outside.match(EM) || [])];
ok(hits.length === 0, '专版自有区 emoji 码点 0 命中' + (hits.length ? '：' + hits.join(' ') : ''));

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
/* 跨文件入口行白名单（批2）：节点家不在本文件、由入口行的目标屏消费；见头注释 ⑤ */
const CROSS_FILE = new Set(['pfMcCnt']);
const miss = new Set();
for (const m of s.matchAll(/\$\('#([\w-]+)'\)/g)) {
  if (!new RegExp('id="' + m[1] + '"').test(s) && !CROSS_FILE.has(m[1])) miss.add(m[1]);
}
ok(miss.size === 0, '$() 字面量目标 id 全部存在（跨文件白名单 ' + [...CROSS_FILE].join(' ') + '）' + (miss.size ? '：缺 ' + [...miss].join(' ') : ''));

/* ---------- 7) jsdom 增强（可用则跑，不可用退化为以上正则断言） ---------- */
try {
  const { JSDOM } = require('jsdom');
  const dom = new JSDOM(s.replace(/<script>[\s\S]*?<\/script>/g, ''), { url: 'file:///原型' });
  const d = dom.window.document;
  for (const id of SCREENS.concat(SHEETS)) ok(!!d.getElementById(id), 'jsdom DOM id: ' + id);
  ok(d.querySelectorAll('#s-diff .d-row [data-dir="up"]').length >= 2 && d.querySelectorAll('#s-diff .d-row [data-dir="down"]').length >= 2, 'jsdom 差异四态示例条目充足');
  var bakBtns = Array.prototype.slice.call(d.querySelectorAll('#s-backup button'))
      .filter(function (b) { return /导出备份|另存到…/.test(b.textContent); });
  ok(bakBtns.length === 2 && /openSafMock/.test(bakBtns[1].getAttribute('onclick') || ''),
      'jsdom R6 导出/另存两动作钮存在且另存钮接 openSafMock');
  ok(!!d.getElementById('safMock') && /保存为/.test(d.getElementById('safMock').textContent), 'jsdom #safMock「保存为」弹层存在');
  var addRow = d.getElementById('rowAddSvc');
  ok(!!addRow && !!d.querySelector('#p-sync #rowAddSvc') && /添加服务/.test(addRow.textContent), 'jsdom 常驻「添加服务」行位于 #p-sync');
  ok(d.querySelectorAll('#s-svc-edit .pill.locked').length === 2, 'jsdom s-svc-edit 初始编辑态两协议 pill 均置灰');
  ok(!!d.getElementById('svcProvLockNote') && /协议已锁定/.test(d.getElementById('svcProvLockNote').textContent), 'jsdom 编辑态协议锁定提示存在');
  console.log('jsdom: 已启用真 DOM 断言');
} catch (e) {
  console.log('jsdom 不可用（' + e.code + '），已退化为正则断言');
}

console.log(bad ? 'RESULT: ISSUES ' + bad : 'RESULT: PASS');
process.exit(bad ? 1 : 0);
