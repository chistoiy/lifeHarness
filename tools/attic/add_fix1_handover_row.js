// 一次性：往交接文档变更记录插入 v0.1.31-ai-fix1 收口行（已执行过会因锚点缺失报错）。
// 用脚本文件而不是 bash 内联命令：行文本里有大量反引号，内联会被 shell 当命令替换执行。
const fs = require('fs');
const p = 'docs/交接文档.md';
const lines = fs.readFileSync(p, 'utf8').split('\n');
const B = '`';
const row = [
  '| 2026-09-28 | **预发布 v0.1.31-ai-fix1 双端挂齐三包（AI 两批真机走查四条修正）** |',
  ' ① **真机走查抓到四条并修掉**（提交 ' + B + '2a08503' + B + '，机型 23127PN0CC / Android 16）：'
  + '展开行里 ' + B + 'SelectableText(maxLines:12)' + B + ' 按行数预留高度，System/User/输出 三段之间出现大片空白；'
  + '顶部统计行被三个动作钮挤到截成「未成…」；入口卡 tokens 值多了 ' + B + 'p' + B + ' 后缀；'
  + '底部与空态写了教学文案（违反既定 UI 规则）。同时加断言「展开区任何 SelectableText 的 maxLines 必须为 null」防回退。'
  + ' ② **版本** ' + B + '0.1.31+4030' + B + '（4029→4030 让装过 v0.1.31-ai 的真机能覆盖升级；'
  + '本机 ' + B + 'android/local.properties' + B + ' 钉版同步改，该文件 gitignored 不入仓），'
  + 'tag ' + B + 'v0.1.31-ai-fix1' + B + ' 打在 ' + B + 'eecd831' + B + '，分支与 tag 双端已推。'
  + ' ③ **出包仍从自己的提交在独立 worktree**（' + B + 'lh-rel0131f1' + B + '）：'
  + 'aapt 核 ' + B + 'versionName=0.1.31' + B + '、versionCode 按 ABI 分流 6030/5030/8030、release 清单含 INTERNET；'
  + 'Gitee release id=1172612（列表接口 ' + B + 'assets' + B + ' 5 个＝三包+两个自动源包），'
  + 'GitHub prerelease 三包字节与本地一致（36874610/33891300/39496045）。'
  + ' ④ **收口脚本已修一处坑**：' + B + 'tools/check_gitee_assets.js' + B + ' 读 stdin，'
  + '必须 ' + B + 'gitee api "repos/…/releases?per_page=100" | node tools/check_gitee_assets.js <tag>' + B
  + '，直跑会报 Unexpected end of JSON input；' + B + 'tools/release_v0131f1.sh' + B + ' 已按管道写法留仓复用。'
  + ' ⑤ **一条待拍板的安全建议**：API Key 明文态截屏会把 Key 一起带走（走查中已确认），'
  + '建议该输入框聚焦期间给窗口加 ' + B + 'FLAG_SECURE' + B + ' 禁截屏/禁录屏。'
  + ' ⑥ **操作事故登记**：本行首次尝试用 bash 内联 ' + B + 'node -e' + B + ' 写入，文本里的反引号被 shell 当命令替换执行，'
  + '误跑了一次发布脚本；因 Gitee 返回 400「该标签已经存在发行版」+ ' + B + 'set -e' + B + ' 立即退出，'
  + '**未产生重复 release、未重挂附件**（已核对两端各 5 资产）。教训：含反引号的中文长文本一律走脚本文件。'
  + ' | pubspec.yaml, lib/features/settings/presentation/ai_usage_page.dart, lib/features/settings/presentation/ai_page.dart, test/ai_usage_v153_test.dart, tools/release_v0131f1.sh, tools/release_body_v0131f1.md |',
].join('');

const i = lines.findIndex((l) => l.startsWith('| 2026-09-28 | **预发布 v0.1.31-ai 双端挂齐三包'));
if (i < 0) throw new Error('找不到锚行（可能已插入，勿重跑）');
if (lines.some((l) => l.startsWith('| 2026-09-28 | **预发布 v0.1.31-ai-fix1'))) throw new Error('已存在 fix1 行');
lines.splice(i, 0, row);
const out = lines.join('\n');
const orphans = lines.filter((l) => l.startsWith(' |') || l.startsWith(' ① '));
if (orphans.length) throw new Error('出现残行 ' + orphans.length);
if (!out.includes('v0.1.31-ai-fix1 双端挂齐三包')) throw new Error('插入未生效');
fs.writeFileSync(p, out, 'utf8');
console.log('OK 已插入 fix1 收口行');
