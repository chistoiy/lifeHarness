// v0.2.1 真机复验轮结果落档（命中断言 + 体积打印 + 预检中止）
'use strict';
const fs = require('fs');
const path = require('path');
const R = path.resolve(__dirname, '..');
const F = path.join(R, 'docs/真机逐屏验收清单-20260929.md');

const s0 = fs.readFileSync(F, 'utf8');
const crlf = s0.includes('\r\n');
const nl = (t) => (crlf ? t.replace(/\n/g, '\r\n') : t);

const SECTION = `
## V1.54 + L3 真机复验轮（2026-09-29 22:57~23:25 · 包 v0.2.1-r14-fidelity-logs）

**装包核对**：APK 从 5fc29b1 在 \`lifeHarness-cg\` worktree 构建（主工作区当时被并行 kits 会话的
在飞编辑污染、编译不过，不可用于出包）；aapt 实测 \`versionName=0.2.1 / versionCode=6032\`（arm64 分包形态），
与机上 \`lastUpdateTime=2026-09-29 22:57:26\` 对齐后才开始取证（防「跑在旧包上」）。

| 条号 | 结论 | 取证 |
|---|---|---|
| R14-7 设置族去 emoji | **过** | 我的页 6 个入口行图标语义树里不再是 emoji 码点，截图为线性图标（云/日志本/图片/铃）；\`.walkthrough/shots/v021_mine.png\` |
| R14-8 块视图刻度读数 | **过** | 顶部已是「1 格 = 15 分 · 全天 0-24」+「粒度 15 分钟」，右列标题「分类」，教学句与 👋 均已摘；\`v021_blockview.png\` |
| R14-12 资料可编辑 | **过** | 「编辑」→ 半屏弹层「编辑资料」两枚 EditText（0/12·0/20 字数位）→ 写入昵称/签名 → 保存 → 资料区与头像首字同步更新 |
| R14-13 三卡联动 | **过** | 「0 完成任务 / 3 连续记录天 / 14 在册书籍」＝本机真数（原写死 128/55/17） |
| R14-14 问候卡实算 | **过** | 「晚上好，Q24 · 今天有 0 个待办 · 8 场安排 · 本周 100% 精力在「重要」象限 · 今日待办 0% 0/0 · 今日持有成本 ¥12.08/天 · 2 件物品计费中」；**冷启动 force-stop 重启后昵称与四数照旧**（走设置项 KV 落库成立，非仅内存态） |

**L3 验收项「用日志页复盘一次账单导入」＝达成**。素材 \`tools/make_bill_fixture.py\`（支付宝表头·10 行·
埋 2 条应被规则过滤的流水）→ 推 \`/sdcard/Download/\` → 记账›更多›账单导入 五步走 GBK 那份。日志页四条：

- \`23:21:33 WARN 记账\` 账单 CSV utf8 解码失败，改按 GBK 重试：\`FormatException: Unexpected extension byte (at offset 2)\`
- \`23:21:33 INFO 记账\` 账单解析：平台 支付宝 · **有效 5 条 · 规则过滤 2 条（共 10 行）** ← 与脚本内离线预期一字不差
- \`23:21:33 INFO 记账\` 账单导入预览：文件 bill_ali_demo_gbk.csv · 平台 支付宝 · 5 条（重复命中 0）· 付款方式 4 组
- \`23:22:41 INFO 记账\` **账单导入落库：批次 2** · 平台 支付宝 · 写入 5/5 条 · 新建账户 4 个（bill_ali_demo_gbk.csv）

顺带在同屏看到 \`数据库打开：目标版本 28\` 与 L2 的通知排程链，说明 L1/L2 留痕在真机同样生效。
解析页另证两件事：GBK 回落链可用，且「招商银行信用卡(8663)&遇财神立减」按 & 取主账户未裂成两个账户。

### 本轮新登记缺陷

- **R15-1「支持整批撤销」有承诺无入口**：完成页与 toast 都写「支持整批撤销本批导入」，
  但 \`LedgerRepository.undoImportBatch(batchId)\` 在 \`lib/**\` **零调用方**（\`ledger_import_page.dart:252\` 注释亦自陈
  「页面没有撤销本批入口（原型无该行）」）——原型 \`index.html\`/\`index-ledger.html\` 同样只有这句话、没有这个钮。
  属**功能缺口 + 文案误导**双料，按 §3.1 需先补原型再落实现。
- **本机账本已被写进 5 笔演示流水 + 4 个账户**（就是上面那次导入），而撤销入口正是上一条缺的东西——
  自食其果一次。清理途径待 R15-1 落地后走「撤销批次 2」，或手工在账本里逐笔删。
- 资料区昵称现为 \`Q24\`、签名 \`2026\`（取证所留）。**恢复不了原状**：昵称必填非空、原值本是空→显示「本地用户」，
  且这台机只有讯飞输入法、\`input text\` 打不进中文，release 包也没有 \`run-as\` 可改 KV。请在应用内自行改回。

### 走查工装三条新坑（覆盖旧口径）

1. **release 包里根本没有 \`io.flutter.app.FlutterAccessibilityService\` 这个组件**（aapt 核过清单，
   只有 5 个第三方 service）。所以旧口径那条 \`settings put secure enabled_accessibility_services <pkg>/io.flutter.app…\`
   写进去会被系统**立刻清空**（读回 null），语义树也不会建立——正解是**借一个本机真实存在且会遍历窗口树的服务**：
   \`com.google.android.marvin.talkback/com.google.android.accessibility.selecttospeak.SelectToSpeakService\`
   + \`accessibility_enabled 1\`，之后 uiautomator 每个 Flutter 节点都带 content-desc 与精确 bounds。
   可用服务清单：\`adb shell cmd package query-services --components -a android.accessibilityservice.AccessibilityService\`。
   **走查收尾必须两项都还原**（本轮已还原为 null/0）。
2. **\`adb input text\` 的中文与字母会被讯飞候选吞掉**：实测 "Qoder" 只落进 1 个字符、"oder" 全丢，而数字 "24" 直通
   ——真机取证要写文本请用**数字/ASCII 短串**，或先切输入法。
3. **SAF/系统选择器里 \`tools/walk_tap.sh\` 会拒绝点按**（前台守护只认 lifeharness，打印 FOREGROUND-FAIL 退出 3）——
   这是**正确行为**（防误触点到自己会话端），在系统文件选择器里改用裸 \`adb shell input tap\`，回 app 内再换回工装。
   另记 MIUI 文件选择器：文件夹与文件混排且**按修改时间排序**，刚 push 的 csv 排在列表底部，需先滑到最底。
`;

const jobs = [
  [
    '- [ ] 设备：修复机 `ea028260`；开 **FlutterAccessibilityService** 才有语义热区；坐标按截图 PNG 原始像素算；走查工装 `tools/walk_{shot,tap,nodes,go}`。',
    '- [x] 设备：修复机 `ea028260`；语义热区口径**已更正**——release 包里无 `FlutterAccessibilityService` 组件，须借 `selecttospeak` 这类真实服务（详见文末「走查工装三条新坑」）；坐标按截图 PNG 原始像素算；走查工装 `tools/walk_{shot,tap,nodes,go}`。',
    1,
  ],
  [
    '- [ ] 装包：`v0.2.0-governance`（tag 基线 `e143ebc`，走查同款构建树，含 v0.1.33-reader-fix 与时间模块 fix1）arm64 分 abi 包；核对 mtime + aapt versionName 再装（防挂错包）。',
    '- [x] 装包：`v0.2.0-governance`（tag 基线 `e143ebc`）首轮 + `v0.2.1-r14-fidelity-logs`（5fc29b1 worktree 出包·aapt 实测 0.2.1/6032）复验轮；均核对 mtime + aapt versionName + 机上 lastUpdateTime 再取证（防挂错包/跑旧包）。',
    1,
  ],
];
for (const [o, , w] of jobs) {
  const n = s0.split(nl(o)).length - 1;
  if (n !== w) {
    console.error(`预检失败：锚点命中 ${n}（需 ${w}）→ ${o.slice(0, 46)}`);
    process.exit(1);
  }
}
const markerHits = (s0.match(/原型已确认 · Flutter 已落地 · 待真机复验/g) || []).length;
if (markerHits !== 5) {
  console.error(`预检失败：R14 状态标记 ${markerHits} 处（需 5）`);
  process.exit(1);
}

let out = s0;
for (const [o, n] of jobs) out = out.split(nl(o)).join(nl(n));
out = out.split(nl('原型已确认 · Flutter 已落地 · 待真机复验')).join(nl('原型已确认 · Flutter 已落地 · **真机复验过**'));
out = out.replace(/\s*$/, '\n') + nl(SECTION);

const before = fs.statSync(F).size;
fs.writeFileSync(F, out);
console.log(
  `已更新 真机逐屏验收清单 ${before} → ${Buffer.byteLength(out)}B (CRLF=${crlf})·R14 五条标记已翻·新节已追加`
);
