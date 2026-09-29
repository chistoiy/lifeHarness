// 「catch 必带日志」守护上线的文档同步（命中断言 + 体积打印 + 预检中止）
'use strict';
const fs = require('fs');
const path = require('path');
const R = path.resolve(__dirname, '..');
const F = {
  ticket: path.join(R, 'docs/日志覆盖工单-20260929.md'),
  plan: path.join(R, 'docs/开发计划书.md'),
  hand: path.join(R, 'docs/交接文档.md'),
  kick: path.join(R, 'docs/交棒话术-20260929-r14轮.md'),
};

function read(f) {
  const s = fs.readFileSync(f, 'utf8');
  return { s, crlf: s.includes('\r\n') };
}
function nl(t, crlf) {
  return crlf ? t.replace(/\n/g, '\r\n') : t;
}

// 预检：所有锚点先验命中数，任一不符整批不改。
const jobs = [];
function planEdit(key, pairs) {
  jobs.push({ key, pairs });
}

const GUARD_ROW =
  '| 2026-09-29 | **架构守护「catch 必带日志」上线（工单 §五-2 收口）** L1~L5 铺完后按拍板启用。' +
  '新钉 `test/catch_log_guard_test.dart` 两例：① 登记式棘轮——`lib/**` 每个异常处置块（`catch(…){…}` **和**不带 catch 的 `on X {…}` 回落）' +
  '必须「有交代」：块内 `AppLog.add/addKey/addStack/reportError`、或 `rethrow`/`throw` 上交、或 `catch-ok: 理由` 批准注释，' +
  '否则必须进 baseline 登记（上线实测存量 **108 处 / 51 文件**，其中 read 42·kits 5 属并行会话写区由各自批次消项），此后只许减不许增、' +
  '清零请删项；`core/logging/**` 为基建豁免面（记自己会递归）。② 守护自证——合成样本钉四类合规与三类静默，' +
  '并钉 `extension G on BuildContext {` 不被误判成异常块（首版就栽在这里）；另有「扫描面骤减即红」防空转、' +
  '`CATCH_GUARD_DUMP=1` 可重生成登记面。**上线即实测拦红一次**（临时静默 catch 文件 → 红 → 撤除 → 绿）。零 lib 行为改动。' +
  '全量 run_gate（HEAD 干净 worktree）1757/0，零 lib 行为改动。 | test/catch_log_guard_test.dart, docs/日志覆盖工单-20260929.md, docs/开发计划书.md, docs/交接文档.md, docs/交棒话术-20260929-r14轮.md |\n';

planEdit('ticket', [
  [
    '> 状态：**已拍板（2026-09-29）· L1~L5 全部交付（本单收口）**；§五-2 挂起的「catch 必带日志」架构守护**现已具备启动条件**（四档决定见 §五）。',
    '> 状态：**已拍板（2026-09-29）· L1~L5 全部交付（本单收口）· §五-2「catch 必带日志」架构守护已上线**' +
      '（`test/catch_log_guard_test.dart` · 登记式棘轮 · 存量 108 处/51 文件在册只许减）。',
  ],
  [
    '2. **架构守护「catch 必带日志」暂不上**，等 L2~L5 铺完再上；过渡期沿用软约束（本单 + 计划书 §2.3 + PR 自查「新增 catch 是否记了日志」）。',
    '2. **架构守护「catch 必带日志」暂不上**，等 L2~L5 铺完再上；过渡期沿用软约束（本单 + 计划书 §2.3 + PR 自查「新增 catch 是否记了日志」）。\n' +
      '   - **已上线（2026-09-29 · L1~L5 收口后）**：`test/catch_log_guard_test.dart`。判定面四条——' +
      '①块内 `AppLog.add/addKey/addStack/reportError`；②`rethrow`/`throw` 上交（全局兜底已统一记）；' +
      '③同前行或上一行有 `catch-ok: 理由` 注释（`//` 与 `/* */` 都认）；④`core/logging/**` 基建豁免（记自己会递归）。' +
      '其余＝静默吞噬，必须进 baseline 登记（登记值＝该文件当时违规数），**只许减不许增**，清零请删项。' +
      '覆盖面含**不带 catch 的 `on X { … }` 回落**（这类最容易静默）；`extension X on Y {` / `mixin M on Y {` 靠「`on` 必须紧跟 `}`」排除——' +
      '首版没这条时把 4 个 extension 误判成了异常块，登记面虚增到 142 处，正对照样本把它照了出来。' +
      '上线实测存量 **108 处 / 51 文件**（read 42·kits 5 属并行会话写区，由各自留痕批次消项）；' +
      '`CATCH_GUARD_DUMP=1 flutter test test/catch_log_guard_test.dart` 可重生成登记面；' +
      '「扫描面骤减即红」+ 合成样本正对照两条防守护空转。',
  ],
]);

planEdit('plan', [
  [
    '**不记**：UI 层交互（点击/切页/动画）、周期计时器每 tick、可推导的高频量。',
    '**不记**：UI 层交互（点击/切页/动画）、周期计时器每 tick、可推导的高频量。\n\n' +
      '**守护（§2.3 的硬拦面）**：`test/catch_log_guard_test.dart` 逐个检查 `lib/**` 的异常处置块（`catch` 与 `on X {…}` 两种形态）' +
      '是否「有交代」——记日志 / 上交重抛 / `catch-ok: 理由` 批准注释三者之一，' +
      '新增静默吞噬直接红；存量走登记式棘轮（只许减不许增，清零删项）。写完 catch 不必等评审，跑这一条用例即自证。',
  ],
]);

planEdit('kick', [
  [
    '- 架构守护「catch 必带日志」：**暂不上**，等 L2~L5 铺完再上（工单 §五已记）。',
    '- 架构守护「catch 必带日志」：**暂不上**，等 L2~L5 铺完再上（工单 §五已记）。' +
      '**→ 已上线（2026-09-29 续批）**：`test/catch_log_guard_test.dart` 登记式棘轮（存量 108 处/51 文件在册只许减），' +
      '口径与豁免面见工单 §五-2。',
  ],
]);

const pre = [];
for (const j of jobs) {
  const { s, crlf } = read(F[j.key]);
  for (const [old_] of j.pairs) {
    const o = nl(old_, crlf);
    const n = s.split(o).length - 1;
    pre.push([j.key, old_.slice(0, 26), n]);
    if (n !== 1) {
      console.error(`预检失败 ${j.key}：锚点命中 ${n} 次（需 1）→ ${old_.slice(0, 40)}`);
      process.exit(1);
    }
  }
}
console.log('预检通过：' + pre.map((p) => `${p[0]}[${p[1]}…]=${p[2]}`).join(' '));

for (const j of jobs) {
  const { s, crlf } = read(F[j.key]);
  let out = s;
  for (const [old_, neu] of j.pairs) {
    out = out.split(nl(old_, crlf)).join(nl(neu, crlf));
  }
  const before = fs.statSync(F[j.key]).size;
  fs.writeFileSync(F[j.key], out);
  console.log(
    `已更新 ${path.basename(F[j.key])} ${before} → ${Buffer.byteLength(out)}B${crlf ? ' (CRLF)' : ''}`
  );
}

// 交接文档：① 修掉 L4/L5 两行里未展开的 `${GATE}` 模板残符；② 表尾追加交付行
// （插完断言无「空格开头残行」）
{
  const { s, crlf } = read(F.hand);
  let out = s;
  const repairs = [
    ['两条相反陷阱（预删反而制造 8 个假红）。${GATE}。', '两条相反陷阱（预删反而制造 8 个假红）。全量 run_gate 1754/0。'],
    ['FakeAsync 不排空就判「A Timer is still pending」）。${GATE}。', 'FakeAsync 不排空就判「A Timer is still pending」）。全量 run_gate 1734/1（唯一红属并行 kits 会话）。'],
  ];
  for (const [o, n] of repairs) {
    const c = out.split(nl(o, crlf)).length - 1;
    if (c !== 1) {
      console.error('交接文档残符修复锚点命中 ' + c + '：' + o.slice(0, 30));
      process.exit(1);
    }
    out = out.split(nl(o, crlf)).join(nl(n, crlf));
  }
  const last = out.replace(/\r?\n$/, '').split(/\r?\n/).pop();
  if (!last.startsWith('| 2026-09-29 |')) {
    console.error('交接文档末行不是交付表行，中止：' + last.slice(0, 60));
    process.exit(1);
  }
  out = out.replace(/\r?\n$/, '') + nl('\n' + GUARD_ROW, crlf) + nl('\n', crlf);
  const bad = out.split(/\r?\n/).filter((l) => /^ +\|/.test(l));
  if (bad.length) {
    console.error('插行产生缩进残行 ' + bad.length + ' 条，中止：' + bad[0].slice(0, 60));
    process.exit(1);
  }
  const before = fs.statSync(F.hand).size;
  fs.writeFileSync(F.hand, out);
  console.log(`已追加 交接文档.md 交付行 ${before} → ${Buffer.byteLength(out)}B`);
}
