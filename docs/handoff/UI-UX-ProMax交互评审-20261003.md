# UI-UX-Pro-Max 交互评审 · 20261003（只出报告，零文件改动）

> 方法：用 ui-ux-pro-max skill 的规则库（quick reference §1~§10 ＋ `--domain ux` 检索）对**热区**做抽查＝批三刚落地的阅读器（`prototype/index-bookshelf.html`＋`lib/features/read/presentation/reader/*`），宏观扫壳层共用引擎段。
> 按「外部 AI 方案逐条识别」规矩，全部结论分三档：**已覆盖（项目早于 skill 拍板，不换）／可考虑（证据在案，需原型先行）／不适用（被更高原则推翻）**。本轮不改任何 UI 文件。

## 一、已覆盖（skill 默认建议已被项目既有决策吸收，勿据此回炉）

| skill 规则 | 项目现状 | 判定依据 |
|---|---|---|
| toast 3–5s 自动消失 | 原型/Flutter 提示条 2.2s，且带 action 的 SnackBar 永挂已修（clearToasts 测试基建） | 全局口径一致即可，2.2s 属可接受的偏短档 |
| undo-support | 记账导入「整批撤销」已落 `ledger_import_batches_sheet.dart`（R15-1 闭环） | grep 在案 |
| deep-linking / state-preservation | 深链体系（`#p-xxx`/`?r32=` 系）＋ enteredFromToday 返回守护＋逐书阅读位置记忆 | AGENTS＋工单多条 |
| progressive-loading（>1s 给骨架） | 批3.5「整本预载封面进度秒进」已在设计内 | 拍板记录 |
| no-emoji-icons | AGENTS 禁令＋emoji 守护扫描（bookshelf-check 逐段跑） | 见下文二④的残留例外 |
| 弹层可退出（modal-escape/escape-routes） | 遮罩点击可关＋返回守护（R6）；等待弹层必须给取消出口已是立规 | flutter-dialog-navigator 记忆 |
| 底部导航 ≤5 | 壳为宫格入口直达专版（屏单一归属拍板），非 tab 模型 | 治理批收口 |
| 沉浸阅读横向翻页=gesture-conflicts | 翻页是产品核心手势，热区祖先分派已定式；Android predictive back 冲突由「返回先回主页」口径吸收 | 拍板在案，勿按 skill 默认改竖滚 |

## 二、可考虑（按严重度排；全部**需原型先行＋产品拍板**，本批未动）

① **草稿丢弃无防误触**（sheet-dismiss-confirm / undo-support）
证据：外观弹层「取消」直接 `closeSheet＋toast('已丢弃')`（`index-bookshelf.html:1783`；Flutter 侧 `reader_appearance_sheet.dart:16` 同款口径）。改了字号行距后误触＝无路找回。
建议两选一（**倾向后者**，与项目「撤销优于确认」口径一致）：a) 草稿≠现值时取消转轻确认；b) 直接丢弃＋提示条带「撤销」恢复草稿。

② **热区尺寸低于 44/48 线**（touch-target-size，skill 列为 CRITICAL）
证据：阅读器底栏工具钮 `.br-ibtn` 46×42（`:1095`）；Flutter 顶栏 IconButton 多处 `visualDensity:compact`＋icon 17px（`reader_chrome.dart:92,104,153`、`reader_appearance_subs.dart:34`、`reader_toc_drawer.dart:212`）。
缓释因素：这些是 tap 唤出的 chrome 上的钮，非常驻；项目密度优先是有意的。
建议：不动视觉尺寸，**扩 hit area（padding/SizedBox 到 ≥44）**；先真机走查记一次误触率再决定是否成批改（L1 级，跨屏不阻塞）。

③ **次要小字系统性低对比**（color-accessible-pairs / readable-font-size）
证据：`text-[9px] text-slate-400` 组合在书架专版出现 **65 次**（8px 另有 9 处）；slate-400 on 白约 2.9:1，低于 skill 4.5:1/3:1 线。户外光照场景可读性最差的是这批「当前选择/秒数/角标说明」字。
建议：不动结构，做一档**全局令牌微调**试验（9px→10px、slate-400→slate-500），在外观弹层或二级说明这类「必须被读到」的子集先试；纯装饰性角注可保留现状。

④ **emoji 守护存在扫描缝**（no-emoji-icons 的执行面）
证据：`index-bookshelf.html:2516` 日程卡标题带 `🔘 ` 前缀（共用引擎段残留）；bookshelf-check 的 emoji 分段只覆盖书架页/弹层/JS 三段，未扫引擎段。
建议：属守护工装补缝——把 emoji 正则对**整文件**跑一遍并入必跑闸（符合「规则必须机器强制」）；文案侧删 `🔘` 前缀即可，随下个动该屏的批次带。

⑤ **触感反馈空白**（haptic-feedback，Low）
证据：习惯打卡成功、删除成功、划线落库等关键确认无 HapticFeedback 调用（lib 内 grep 零命中）。
建议：只在「成功确认」一帧加 light impact，勿做成动画式滥用；优先级低，可并入任一真机反馈批。

## 三、不适用（沉没判断，勿再议）

- **body 16px 基线**：移动端正文 19px 起步（阅读器可调），壳层密度模型是本产品立意，非缺陷。
- **keyboard-nav / focus-visible / skip-links**：Android 触屏产品，无键盘主路径；TalkBack 语义已由 R14-10 semanticLabel 批覆盖入口钮，正文 Text 天然可读。
- **hover 态补强**：原型 hover 仅供走查，真机无 hover。
- **图表类规则（§10）**：账本四档已有立规（图例/数值直标在案），通鉴五层色＝内容语义（原书声明），不适用「color-only 反模式」判废——批三总原则压过该条。

## 四、建议落法（不自动执行）

①②③ 若拍板 → 先改 `prototype/index-bookshelf.html`（②④的 Flutter 面在实现批同步）→ r32stylecheck/bookshelf-check 补断言 → 真机抽查误触率；④⑤ 各可挂到最近的顺路批。本评审不动 `lib/**` 与任何原型。

## 五、合并去向（2026-10-03·产品将删原审查会话，两件均由本会话接管）

本件的五条「可考虑」已并入《交互整改开发计划-20261003》：**①→T14、②→并入 T6（补阅读器两例）、③→T15、④→并入 T13（扩量改守护化，全仓实测 lib 69 文件/352 枚，含注释级与"原型同款"内容级两档需分拣——扫描工装 `tools/emoji_inv.js`）、⑤→挂账（触感反馈）**。排批新增第 5 条：read 面整改（T4/T6/T13 触点）让位批三实现批收口后。本件继续留作原型热区视角附件，条目以整改计划为准。
