// 治理G7d② 一次性脚本：sync_sheets.dart 按 S 段整块外提为 part 文件（天然按类分段，无需 extension）
// 用法：node tools/g7d2_sync_split.js --groups mini,s1   （加 --dry 只看统计）
// 护栏：锚点唯一命中 + 块尾形态 + 成员「恰好出现一次」双向断言 + 体积校验 + 改前快照 .bak。
const fs = require('fs');
const path = require('path');

const DIR = 'lib/features/settings/presentation/widgets';
const SRC = path.join(DIR, 'sync_sheets.dart');
const DRY = process.argv.includes('--dry');
const gIdx = process.argv.indexOf('--groups');
const wanted = (gIdx >= 0 ? process.argv[gIdx + 1] : '').split(',').filter(Boolean);
if (!wanted.length) {
  console.error('USAGE: --groups mini,s1,s2,s3,s4,s6,s7');
  process.exit(1);
}

const hdr = (t) => (l) => l.trim() === `// ============================ ${t} ============================`;
const S = (t) => `// ============================ ${t} ============================`;

const lines = fs.readFileSync(SRC, 'utf8').replace(/\r\n/g, '\n').split('\n');
const origLen = lines.length;

function findOnce(src, pred, label) {
  const hits = [];
  for (let i = 0; i < src.length; i++) if (pred(src[i], i)) hits.push(i);
  if (hits.length !== 1) {
    console.error(`ANCHOR-FAIL [${label}] hits=${hits.length} -> ${hits.join(',')}`);
    process.exit(1);
  }
  return hits[0];
}

const lastIdx = (() => {
  for (let i = lines.length - 1; i >= 0; i--) if (lines[i].trim() !== '') return i;
  return -1;
})();

const ALL = {
  mini: {
    out: 'sync_mini_widgets.dart',
    start: hdr('公共小件'),
    end: hdr('S1 · 服务配置编辑'),
    header: [
      "part of 'sync_sheets.dart';",
      '',
      '// 治理G7d②：公共小件群自 sync_sheets 整块外提（行为零改动）。',
      '// 字节/时间/服务名格式化 + 徽标·锁点·目录标签·分段钮·区头 + 单列滚轮 NumberWheel（T6 同源）。',
    ],
    members: [
      'String formatBytes(int bytes) {',
      'String formatHistoryTime(int ms) {',
      'String serviceDisplayName(ServiceConfig c) {',
      'class _ProtoBadge extends StatelessWidget {',
      'class _LockDot extends StatelessWidget {',
      'class _DirTag extends StatelessWidget {',
      'class _SegBtn extends StatelessWidget {',
      'class _SecTitle extends StatelessWidget {',
      'class NumberWheel extends StatefulWidget {',
      'class _NumberWheelState extends State<NumberWheel> {',
    ],
  },
  s1: {
    out: 'sync_service_edit_sheet.dart',
    start: hdr('S1 · 服务配置编辑'),
    end: hdr('S2 · 连接验证'),
    header: [
      "part of 'sync_sheets.dart';",
      '',
      '// 治理G7d②：S1 服务配置编辑弹层自 sync_sheets 整块外提（行为零改动）。',
      '// 缺省端点常量 + showServiceEditSheet + _ServiceEditSheet(State)；凭据只经 CredentialVault 写入（R11）。',
    ],
    members: [
      'const String _kWebDavDefaultUrl',
      'const String _kS3DefaultUrl',
      'Future<Object?> showServiceEditSheet(',
      'class _ServiceEditSheet extends ConsumerStatefulWidget {',
      'class _ServiceEditSheetState extends ConsumerState<_ServiceEditSheet> {',
    ],
  },
  s2: {
    out: 'sync_verify_sheet.dart',
    start: hdr('S2 · 连接验证'),
    end: hdr('S3 · 差异半屏'),
    header: [
      "part of 'sync_sheets.dart';",
      '',
      '// 治理G7d②：S2 连接验证弹层自 sync_sheets 整块外提（行为零改动）。',
      '// 三态＝连接通过/凭据错误/网络失败（S2 口径）；凭据缺失时本地预检直出、不发请求。',
    ],
    members: [
      'Future<void> showVerifySheet(',
      'enum _VerifyKind { running, ok, cred, net }',
      'class _VerifySheet extends ConsumerStatefulWidget {',
      'class _VerifySheetState extends ConsumerState<_VerifySheet> {',
    ],
  },
  s3: {
    out: 'sync_diff_sheet.dart',
    start: hdr('S3 · 差异半屏'),
    end: hdr('S4 · 同步进度半屏'),
    header: [
      "part of 'sync_sheets.dart';",
      '',
      '// 治理G7d②：S3 差异半屏自 sync_sheets 整块外提（行为零改动）。',
      '// 四态分组 + 一致组折叠 + 逐条勾选 + 合计行；仅云端行带「下载」；含 _MiniBtn 与 DiffRunRequest。',
    ],
    members: [
      'class DiffRunRequest {',
      'Future<DiffRunRequest?> showDiffSheet(',
      'class _DiffSheet extends ConsumerStatefulWidget {',
      'class _DiffSheetState extends ConsumerState<_DiffSheet> {',
      'class _MiniBtn extends StatelessWidget {',
    ],
  },
  s4: {
    out: 'sync_progress_sheet.dart',
    start: hdr('S4 · 同步进度半屏'),
    end: hdr('S6 · 控流弹层'),
    header: [
      "part of 'sync_sheets.dart';",
      '',
      '// 治理G7d②：S4 同步进度半屏自 sync_sheets 整块外提（行为零改动）。',
      '// 订阅 SyncOrchestrator.state（current/done/total + 取消钮）。',
    ],
    members: [
      'Future<void> showSyncProgressSheet(',
      'class _ProgressSheet extends ConsumerStatefulWidget {',
      'class _ProgressSheetState extends ConsumerState<_ProgressSheet> {',
    ],
  },
  s6: {
    out: 'sync_throttle_sheet.dart',
    start: hdr('S6 · 控流弹层'),
    end: (l) => l.trim() === '/// R5d：云端孤儿附件清理半屏（S7）。',
    header: [
      "part of 'sync_sheets.dart';",
      '',
      '// 治理G7d②：S6 控流弹层自 sync_sheets 整块外提（行为零改动）。',
      '// 档位常量 + 快照份数滚轮 + 仅Wi-Fi 开关（prefs sync_wifiOnly · T19 消费）。',
    ],
    members: [
      'const List<int> _kThrottleTiers = [150, 300, 800];',
      'const List<int> _kKeepOptions = [3, 5, 10, 20];',
      'Future<void> showThrottleSheet(',
      'class _ThrottleSheet extends ConsumerStatefulWidget {',
      'class _ThrottleSheetState extends ConsumerState<_ThrottleSheet> {',
    ],
  },
  s7: {
    out: 'sync_cloud_clean_sheet.dart',
    start: (l) => l.trim() === '/// R5d：云端孤儿附件清理半屏（S7）。',
    end: null, // EOF
    header: [
      "part of 'sync_sheets.dart';",
      '',
      '// 治理G7d②：S7 云端孤儿附件清理半屏自 sync_sheets 整块外提（行为零改动）。',
      '// 打开即 force 拉云端清单算孤儿；「归档」move 到 media_archive/（默认·可回退），「彻底删除」需二次确认。',
    ],
    members: [
      'Future<void> showCloudCleanSheet(',
      'class _CloudCleanSheet extends ConsumerStatefulWidget {',
      'class _CloudCleanSheetState extends ConsumerState<_CloudCleanSheet> {',
    ],
  },
};

const groups = wanted.map((k) => ({ key: k, ...ALL[k] }));
for (const g of groups) {
  if (!g.out) {
    console.error('UNKNOWN-GROUP ' + g.key);
    process.exit(1);
  }
  g.s = findOnce(lines, g.start, `${g.key}.start`);
  g.e = g.end === null ? lastIdx + 1 : findOnce(lines, g.end, `${g.key}.end`);
}
const sorted = groups.slice().sort((a, b) => a.s - b.s);
for (let i = 0; i < sorted.length; i++) {
  if (!(sorted[i].s < sorted[i].e)) {
    console.error('ORDER-FAIL', sorted[i].key);
    process.exit(1);
  }
  if (i + 1 < sorted.length && !(sorted[i].e <= sorted[i + 1].s)) {
    console.error('OVERLAP-FAIL', sorted[i].key, sorted[i + 1].key);
    process.exit(1);
  }
}

function block(src, start, endExclusive) {
  const b = src.slice(start, endExclusive);
  while (b.length && b[b.length - 1].trim() === '') b.pop();
  if (!b.length || !/[};]$/.test(b[b.length - 1].trim())) {
    console.error('END-FAIL', JSON.stringify(b[b.length - 1]));
    process.exit(1);
  }
  return b;
}

const keep = lines.slice();
for (const g of sorted.slice().reverse()) {
  g.body = block(keep, g.s, g.e);
  for (let i = g.s + g.body.length - 1; i >= g.s; i--) keep.splice(i, 1);
  while (keep[g.s] !== undefined && keep[g.s].trim() === '') keep.splice(g.s, 1);
  keep.splice(g.s, 0, '');
}

// part 指令插入点：已有 part 块末尾顺序追加；无 part 块时插到末条 import 之后并补分隔空行
let insAt = -1;
let hadParts = false;
for (let i = 0; i < keep.length; i++)
  if (keep[i].startsWith("part '")) {
    insAt = i;
    hadParts = true;
  }
if (!hadParts) {
  insAt = findOnce(
    keep,
    (l) => l.startsWith("import '../../../../shared/widgets/ui_kit.dart';"),
    'last.import',
  );
  keep.splice(insAt + 1, 0, '');
  insAt += 1;
}
keep.splice(insAt + 1, 0, ...groups.map((g) => `part '${g.out}';`));
while (keep.length && keep[keep.length - 1].trim() === '') keep.pop();
keep.push('');

const keptText = keep.join('\n');
const bad = [];
const partTexts = {};
for (const g of groups) {
  const t = [...g.header, ...g.body, ''].join('\n');
  partTexts[g.out] = t;
  for (const m of g.members) {
    const inPart = t.split('\n').filter((l) => l.trim().startsWith(m)).length;
    const inKeep = keptText.split('\n').filter((l) => l.trim().startsWith(m)).length;
    if (inPart !== 1 || inKeep !== 0) bad.push({ out: g.out, m, inPart, inKeep });
  }
  if (t.split('\n')[0] !== "part of 'sync_sheets.dart';") bad.push({ out: g.out, m: '首行 part of' });
}
// 主文件必须仍是完整库入口：prefs 键与文档头未被卷走
{
  const n = keptText
    .split('\n')
    .filter((l) => l.trim().startsWith("const String kSyncWifiOnlyKey")).length;
  if (n !== 1) bad.push({ m: 'keep 侧 kSyncWifiOnlyKey', got: n });
  if (!keptText.includes('V1.41 Task 18 · /sync 弹层家族'))
    bad.push({ m: 'keep 侧库文档头' });
}

const moved = groups.reduce((s, g) => s + g.body.length, 0);
const after = keep.length;
const volumeOk =
  origLen - after >= moved - 2 * groups.length - 2 &&
  origLen - after <= moved + 2 * groups.length + 2 &&
  after > 20;

console.log(
  JSON.stringify(
    { groups: wanted, moved, parts: groups.map((g) => `${g.out}:${g.body.length}`), syncSheets: `${origLen} -> ${after}`, volumeOk, bad, DRY },
    null,
    2,
  ),
);
if (bad.length || !volumeOk) process.exit(1);
if (DRY) process.exit(0);

fs.writeFileSync(SRC + '.bak', lines.join('\n'));
for (const g of groups) fs.writeFileSync(path.join(DIR, g.out), partTexts[g.out]);
fs.writeFileSync(SRC, keptText);
console.log('WRITTEN');
