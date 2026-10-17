# LifeHarness 上下文与仓库治理（二轮）设计

日期：2026-10-02 · 状态：已获用户整体放行（跳过逐节复审）
前置：一轮治理＝`docs/架构与原型治理评估-20260928.md`（G0~收口批已发布 v0.2.0-governance）。
本轮动因：新会话开场必读超载（4 份 ≈2700 行，其中大半为过期脉络）、一次性工单在 docs/ 顶层无生命周期堆积（27 份）、史前巨料在库（原始需求 63,532 行）、产物入库（截图 293 个、tools/attic 156 文件 86MB）。

## 0. 范围裁定（用户已拍板）

- 范围＝文档 + 脚本 + 产物；**代码大文件只登记不拆分**（read 区被并行 V5 会话占用，禁动）。
- 过期历史文档＝仓库内删除（git rm）+ `docs/archive/` 目录归档双轨。
- 截图类产物不再入库：已跟踪者 git rm，未跟踪者（并行取证会话产物）只加忽略规则不删文件。
- 交接文档头部状态拆为独立 `docs/STATUS.md`（≤60 行，唯一状态源）。
- `.git` 历史不重写（已双端推送）；本轮收益是磁盘、worktree 速度与会话上下文，不含 .git 体积（297MB 维持）。

## 1. 新会话加载模型——三层按需

开场必读从「agents.md + 交接文档 + 需求清单 + 开发计划书(+UI规范)」缩为：

| 文件 | 内容 | 上限 |
|---|---|---|
| `AGENTS.md`（**补入库**，当前 untracked） | 禁令、环境事实、忽略清单、指针 | ≤80 行 |
| `docs/STATUS.md`（新） | HEAD/分支、最新预发布+钉版、DB 版本、门禁基线、下一站工单指针、并行互斥面 | ≤60 行 |
| `docs/INDEX.md`（新） | 文档地图：每份一行 `路径 \| 类型 \| 活/归档 \| 何时才需要读` | 按量 |

约定：状态变化**只改 STATUS.md**；历史时点沉交接文档文末。agents.md「开工先读」改写为：
STATUS → 与任务类型对应的 INDEX 行 → 按需展开。任务口径（交棒话术=唯一规格等）不变。

## 2. 文档生命周期与目录结构

- `docs/`：现行规格（需求清单、UI组件规范、开发计划书、高保真原型设计准则、STATUS、INDEX、各模块现行开发计划）。
- `docs/handoff/`：活工单（交棒话术 / 真机逐屏验收清单 / 拍板记录）。今后新工单**直接建在这里**。
- `docs/archive/`：闭环归档，只进不出。闭环判据：交接文档变更日志已登记该批交付，或需求已作废（如小工具、legado）。
- 收口流程落 agents.md：批次收口 → 对应工单 `git mv` 入 archive → 更新 INDEX 一行。
- 现状 27 份工单逐一分类：活（F01-批C-R32 规格、xray词库与精化验收清单、其余交接文档明示未闭环者）留 handoff/；已闭环移 archive/；执行时以交接文档变更日志与 git log 为准逐份核对，拿不准的**从宽保留在 handoff/**。

## 3. 大文档瘦身

- **需求清单**（1077 → 目标 ≈450 行）：第十节修订记录 + 头部引用块 V1.30~V1.49 单行千字长文整体迁 `docs/archive/需求修订史-20260919-20261002.md`（每版本拆多行短段，内容逐字保留不删减）；需求清单头部只留一行指针。三源优先序「需求清单修订记录 > 原型 > 计划文档」**不改语义**，agents.md 指针同步改指修订史文件。
- **交接文档**（422 → 目标 ≈150 行）：头部三条超长行中「当前状态」拆入 STATUS.md；「历史时点·轮2」「当前阶段」两条超长行压缩为每轮 2~3 行短条目；变更日志保留在文末。
- **删除**：`docs/原始需求-android-20260919.md`（63,532 行 git rm，INDEX 留考古指针「git log 可找回」）；`docs/SKILL.md`（Drift 技术栈错配）；根目录 `!`、`docs/A-D-B` 垃圾文件。

## 4. 产物卫生

- git rm：`docs/acceptance*` 已跟踪 146 文件、`prototype/shots/` 已跟踪 147 文件。
- .gitignore 新增：`docs/acceptance*`、`prototype/shots/`；今后验收/取证产物一律仓库外或 gitignored 目录，验收文档只写结论不挂图。
- tools/：有引用价值的校验脚本先 `git mv` 回 `tools/`（执行时逐个 grep 引用判定），其余 `git rm -r tools/attic`（156 文件 86MB 一次性补丁坟场）。
- 磁盘（不涉 git）：删除 7 天内未更新的无头浏览器 profile（`tools/.xray-profile`、`tools/.br57-profile`、`tools/reader/.bsrd-profile` 等，约 300MB 可再生）；保留 `.f01-probe`、`tools/.xr-probe-fresh`（后续批次在用）。删前 `ls -la --time-style` 复核 mtime。
- 不碰：任何未跟踪的并行会话文件（阅读模块 V5 三文档、`prototype/reader*`、`index-bookshelf-reader.html`、`index-health.html`、影音游/legado 相关、acceptance_20261001/1002 目录）。

## 5. 代码大文件登记（不拆）

在 `docs/治理backlog行为改工单-20260929.md` 追加「体积债务登记（20261002）」节：lib 超 1200 行 12 文件（read×5、ledger×2、habit×2、calendar、journal、reader_page）＋ `test/read_page_test.dart` 2383 行；各标归属功能批次，read 区标「V5 并行占用解除前禁动」。本轮零 dart 改动。

## 6. 执行护栏与验证

- 只动**已跟踪且非并行会话**文件；未跟踪一律不碰。
- 批量操作用 `tools/` 脚本文件：命中断言 + 体积校验 + 按真实编码读写 + 锚点跟随行尾；禁 heredoc。
- 局部提交 `git commit -- <路径>`，每批提交前 `git status` 复核未卷走他人暂存。
- 死链治理：新建 `tools/doclint.sh`——扫描全部入库 markdown 中的 `docs/…`/`prototype/…`/`tools/…` 相对引用与 INDEX 表，路径不存在即红；每批迁移后复跑，收口必须零红。
- 分批提交序：①AGENTS/STATUS/INDEX 结构层 → ②需求清单拆分 → ③工单归档 → ④截图与 tools 清理 → ⑤doclint 收口。
- 收口验证三件：doclint 零红；新会话模拟（只读三文件能答出 HEAD/下一站/互斥面）；抽查 2 份归档工单 git 可达。
- 门禁：本轮不触 lib/test 代码，全量门禁不重跑；受影响的是文档引用类守护（若有测试 grep docs/ 路径，执行中先 `grep -rl 'docs/' test/` 排查并跑对应测试文件）。
- 推送需另行请示（发版纪律不变）。
