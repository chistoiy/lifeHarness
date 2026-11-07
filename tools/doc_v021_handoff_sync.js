// ② 发布 + ③ 真机复验轮的交接文档/工单收口行（命中断言 + 预检中止）
'use strict';
const fs = require('fs');
const path = require('path');
const R = path.resolve(__dirname, '..');
const HAND = path.join(R, 'docs/交接文档.md');
const TICKET = path.join(R, 'docs/日志覆盖工单-20260929.md');
const KICK = path.join(R, 'docs/交棒话术-20260929-r14轮.md');

const read = (f) => {
  const s = fs.readFileSync(f, 'utf8');
  return { s, crlf: s.includes('\r\n') };
};
const nl = (t, crlf) => (crlf ? t.replace(/\n/g, '\r\n') : t);

const ROW =
  '| 2026-09-29 | **v0.2.1-r14-fidelity-logs 双端发布 + 真机复验轮（R14-7/8/12/13/14 与 L3 日志复盘全过）** ' +
  '① 推送与发版：本会话 5 个提交（`4fcfcce` V1.54 / `c00f363` L3 / `bbee577` L4 / `4a88de6` L5 / `f1b6300` catch 守护）' +
  '+ 钉版 `5fc29b1`（0.2.1+4032，`pubspec.yaml` 与 gitignored 的 `android/local.properties` **两处同改**，后者会覆盖前者）。' +
  '**只推到自己的提交**（`git push <remote> 5fc29b1:refs/heads/feat/m0-skeleton`），把并行书源会话未收口的 `1d08eee` 留在本地由他自己发。' +
  'APK 从 `5fc29b1` 在 `lifeHarness-cg` worktree 构建（主工作区当时被 kits 会话在飞编辑污染、编译不过，不可出包）；' +
  'aapt 实测 `0.2.1/6032`·三包 mtime 一致；tag 双端 + Gitee `attach_files` 三包全 201 + GitHub prerelease 三资产齐。' +
  '② 真机复验（ea028260·adb 接管·取证见验收清单文末新节）：R14-7 设置族线性图标 / R14-8 块视图刻度读数 / ' +
  'R14-12 资料半屏弹层可写可存 / R14-13 三卡真数（0·3·14）/ R14-14 问候卡四数实算且 **force-stop 冷启动后照旧**（KV 落库成立）。' +
  '③ **L3 验收项达成**：`tools/make_bill_fixture.py` 造支付宝 GBK 账单 → 五步导入 → 日志页四条齐' +
  '（utf8→GBK 回落 warn · 解析汇总「有效 5 · 规则过滤 2 · 共 10 行」· 预览 · **落库含批次 2**），' +
  '同屏另见 `数据库打开：目标版本 28` 与 L2 通知排程链。④ 新登记 **R15-1**：完成页/toast 写「支持整批撤销」但 ' +
  '`undoImportBatch` 在 `lib/**` 零调用方（原型亦只有这句话没有这个钮）＝功能缺口+文案误导，需先过原型门。' +
  '⑤ 工装口径更正：**release 包内没有 `FlutterAccessibilityService` 组件**，旧命令写入被系统立刻清空，' +
  '须借本机真实存在的 `selecttospeak` 服务才建语义树（收尾还原 null/0）；`input text` 中文与字母被讯飞候选吞、数字直通；' +
  'SAF 里 `walk_tap.sh` 前台守护拒点是正确行为，改裸 tap。门禁：守护上线后 HEAD 干净 worktree 全量 1757/0。 | ' +
  'docs/真机逐屏验收清单-20260929.md, docs/交接文档.md, docs/日志覆盖工单-20260929.md, docs/开发计划书.md, ' +
  'tools/make_bill_fixture.py, tools/doc_v021_verify_sync.js, tools/doc_v021_handoff_sync.js, ' +
  'tools/release_body_v021.md, pubspec.yaml, test/catch_log_guard_test.dart |\n';

const ticketPairs = [
  [
    '「真机跑一次导入可复盘全过程」＝日志侧已备（预览/落库两条 key 行含批次 id），装机复盘并入下一轮真机走查',
    '「真机跑一次导入可复盘全过程」＝**已达成（2026-09-29 23:21·v0.2.1 包·ea028260）**：GBK 账单五步导入后日志页四条齐' +
      '（utf8→GBK 回落 warn / 解析汇总「有效 5 · 规则过滤 2 · 共 10 行」/ 预览 / 落库含**批次 2**），' +
      '取证见 `docs/真机逐屏验收清单-20260929.md` 文末新节',
  ],
];
const kickPairs = [
  [
    '② 真机走查时顺手用日志页复盘一次账单导入全过程（工单 L3 验收项）。',
    '② 用日志页复盘一次账单导入全过程（工单 L3 验收项）——**已达成（2026-09-29 23:21·v0.2.1 包·批次 2 四条日志）**，' +
      '取证与工装新坑见 `docs/真机逐屏验收清单-20260929.md` 文末新节。',
  ],
];

// 预检（幂等：已应用过的锚点跳过，不重复替换）
const applied = (s, crlf, o, n) => {
  if (s.includes(nl(o, crlf))) return false;
  if (s.includes(nl(n.slice(0, 40), crlf))) return true;
  throw new Error(`锚点既不在也无成果：${o.slice(0, 44)}`);
};
for (const [f, pairs] of [[TICKET, ticketPairs], [KICK, kickPairs]]) {
  const { s, crlf } = read(f);
  for (const [o] of pairs) {
    const n = s.split(nl(o, crlf)).length - 1;
    if (n > 1) {
      console.error(`预检失败 ${path.basename(f)}：命中 ${n}（需 ≤1）→ ${o.slice(0, 44)}`);
      process.exit(1);
    }
  }
}
{
  const { s } = read(HAND);
  const last = s.replace(/[\r\n]+$/, '').split(/\r?\n/).pop();
  if (!last.startsWith('| 2026-09-29 |')) {
    console.error('交接文档末行不是交付表行，中止：' + last.slice(0, 60));
    process.exit(1);
  }
}

for (const [f, pairs] of [[TICKET, ticketPairs], [KICK, kickPairs]]) {
  const { s, crlf } = read(f);
  let out = s;
  let skipped = 0;
  for (const [o, n] of pairs) {
    if (applied(out, crlf, o, n)) { skipped++; continue; }
    out = out.split(nl(o, crlf)).join(nl(n, crlf));
  }
  if (out === s) { console.log(`跳过 ${path.basename(f)}（已是应用后状态）`); continue; }
  const before = fs.statSync(f).size;
  fs.writeFileSync(f, out);
  console.log(`已更新 ${path.basename(f)} ${before} → ${Buffer.byteLength(out)}B${skipped ? '（含跳过 ' + skipped + ' 处）' : ''}`);
}
{
  const { s, crlf } = read(HAND);
  if (s.includes(ROW.slice(0, 46))) {
    console.log('跳过 交接文档.md（收口行已存在）');
  } else {
    // 只校验**自己这一行**：既有表行正文里本就带裸竖线（实测列数 2~5 不等），
    // 拿「全表必须 3 列」当闸会误伤——校验面要落在可负责的范围上。
    const mine = ROW.replace(/\n$/, '');
    const cols = mine.split('|').length - 2;
    const pipes = (mine.match(/\|/g) || []).length;
    if (cols !== 3 || pipes !== 4) {
      console.error(`本行列数不是 3（列 ${cols}·竖线 ${pipes}，应为 4），中止`);
      process.exit(1);
    }
    let out = s.replace(/[\r\n]+$/, '') + nl('\n' + ROW, crlf) + nl('\n', crlf);
    const bad = out.split(/\r?\n/).filter((l) => /^ +\|/.test(l));
    if (bad.length) {
      console.error('插行产生缩进残行 ' + bad.length + ' 条，中止：' + bad[0].slice(0, 60));
      process.exit(1);
    }
    const before = fs.statSync(HAND).size;
    fs.writeFileSync(HAND, out);
    console.log(`已追加 交接文档.md 收口行 ${before} → ${Buffer.byteLength(out)}B（本行列数=3 校验过）`);
  }
}
