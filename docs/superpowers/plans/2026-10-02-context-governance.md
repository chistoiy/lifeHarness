# LifeHarness 上下文与仓库治理（二轮）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> 用户已明示：计划落档后**直接执行**，不再逐项请示（推送/发版仍需单独同意）。

**Goal:** 把新会话开场必读从 ≈2700 行缩到 ≤200 行，过期文档出仓归档，截图与 attic 产物出仓，工单建立生命周期。

**Architecture:** 三层按需加载（AGENTS.md → STATUS.md → INDEX.md 路由）；docs/ 分「现行 / handoff(活工单) / archive(闭环)」三态；产物一律不再入库。

**Tech Stack:** Markdown、Git（局部提交 `git commit -- <路径>`）、Node/Python 批处理脚本（`D:\app_workplace\python3.11\python.exe` 或 node）、bash。

**Spec:** `docs/superpowers/specs/2026-10-02-context-governance-design.md`

## Global Constraints

- 工程真实路径 `D:/dev_workplace/flutter_te/lifeHarness`，分支 `feat/m0-skeleton`。
- **零 dart/test/lib 代码改动**；全量门禁不重跑（受影响仅文档路径注释，已核实无读取断言）。
- **禁碰未跟踪的并行会话文件**：`docs/阅读模块V5视觉设计说明-20261002.md`、`docs/阅读模块开场白-20261002.md`、`docs/阅读模块开发省token策略-20261002.md`、`docs/项目拆分重构调研报告-20261002.md`、`docs/健康管理模块开发计划-20260927.md`(??)、`prototype/reader-v4|reader-v5|reader/`、`prototype/index-bookshelf-reader.html`、`prototype/index-health.html`(M)、`docs/acceptance_20261001_xray/`、`docs/acceptance_20261002_xray2/`(未跟踪)、`docs/预研/legado…`、影音游计划(M)。每批提交前 `git status --porcelain` 复核只含自己路径。
- 提交一律 `git commit -m "…" -- <路径>`，**禁 git add -A**；禁 dart format；不写教学性文案。
- 批量改文件写成 `tools/` 脚本文件执行（勿 heredoc）：改前快照、命中断言、体积校验、按真实编码读写、锚点跟随目标文件行尾（先探测 CRLF/LF）。
- **原地不动清单**（被代码/活文档注释点名，路径保留）：`docs/UI组件规范.md`、`docs/X-Ray全书索引开发设计说明书-20260928.md`、`docs/X-Ray词条质量治理计划-20261002.md`、`docs/日志覆盖工单-20260929.md`、`docs/治理backlog行为改工单-20260929.md`、`docs/需求清单.md`、`docs/交接文档.md`、`docs/开发计划书.md`、`docs/高保真原型设计准则-20260925.md`、各模块《…开发计划-*.md》。
- 本轮**不推送**；结束后向用户汇报并请示。

---

### Task 1：结构层——AGENTS.md 入库 + STATUS.md + INDEX.md + 垃圾清理

**Files:**
- Create: `docs/STATUS.md`、`docs/INDEX.md`、`AGENTS.md`（工作区已有未跟踪正文，重写后入库）
- Modify: `.gitignore`（先只加工单流转相关规则，截图规则留到 Task 5 一起）
- Delete: `docs/SKILL.md`（Drift 错配）、`docs/A-D-B`（0 字节垃圾）；根 `!` 文件**未跟踪，只删磁盘不涉 git**——先 `git ls-files "!"` 确认为未跟踪后 `rm '!'`

- [ ] **Step 1: 写 STATUS.md（≤60 行）**，内容按当前事实（更新自交接文档头部 + 本会话新提交）：

```markdown
# STATUS（唯一状态源 · 最后更新 2026-10-02 治理二轮）
- 分支 feat/m0-skeleton；HEAD 见 `git log -1`（本文不钉 HEAD  sha，防漂移）；双端推送进度以文末说明为准：治理二轮提交未推送。
- 最新预发布 v0.2.9-reader-r3（钉版 79473f5＝0.2.9+4046）· DB DbSchema.version=34 · 全量基线 1786 绿/0 红（治理后零代码改动，基线不变）。
- 复测包 worktree：D:/dev_workplace/flutter_te/lh-r31（复用，reset --hard 到自己提交）；下一个 build-number 6047。
- 下一站：治理二轮（本计划执行中）→ 顺延批：F01-批C-R32 精修（规格 docs/handoff/交棒话术-20261002-下一版实现批-F01-批C-R32精修.md，Task 4 归档流转后以 INDEX 为准）。
- 并行互斥面（只读不写不提交不回退）：lib/features/read/** 与 V5 视觉线未跟踪文档/原型清单见本文件下方「互斥明细」行 + AGENTS.md。
- 环境/禁令/忽略清单：一律看 AGENTS.md；文档地图看 docs/INDEX.md；历史脉络看 docs/交接文档.md 文末变更日志。
```

（执行时按当次实际事实微调；行数硬上限 60。）

- [ ] **Step 2: 生成 INDEX.md**——脚本 `tools/gov2_mkindex.sh`：`git ls-files docs` 全量列出，逐行 `路径 | 类型 | 状态 | 何时读`。类型/状态人工判读填列（规格/工单/预研/手册/归档；活/闭环）。原始需求行写「已删除——考古用 `git log --diff-filter=D -- docs/原始需求-android-20260919.md`」。开发计划书/UI规范/准则等现行文档状态=活。
- [ ] **Step 3: 重写 AGENTS.md**：保留全部禁令/环境事实/忽略清单原文；「开工先读」四步改为三步——① STATUS.md ② 与任务类型对应的 INDEX 行 ③ 按需展开（UI 任务仍先读 UI组件规范+原型）。新增两条流程口径：
  - 新工单一律建在 `docs/handoff/`；批次收口 → 工单 `git mv` 入 `docs/archive/` → 更新 INDEX 一行。
  - 验收/取证截图不再入库（`docs/acceptance*`、`prototype/shots/` 已 gitignore），验收文档只写结论。
  - 三源冲突优先序改写：「需求修订史（docs/archive/需求修订史-*.md，Task 2 产出）> 原型 > 计划文档」。
- [ ] **Step 4: 删垃圾**：`git rm docs/SKILL.md docs/A-D-B`；`rm '!'`（磁盘）。
- [ ] **Step 5: 提交**：`git add AGENTS.md docs/STATUS.md docs/INDEX.md` 后 `git commit -m "docs(治理): 结构层——AGENTS 入库+STATUS/INDEX 三层按需加载；SKILL/A-D-B 清理" -- AGENTS.md docs/STATUS.md docs/INDEX.md docs/SKILL.md docs/A-D-B`；`git status --porcelain` 复核。

### Task 2：需求清单拆分（1077 → ≈450 行）

**Files:**
- Create: `docs/archive/需求修订史-V1.19~V1.59.md`（含自需求清单迁出的第十节 + 头部引用块长文，逐字保留）
- Modify: `docs/需求清单.md`（头部第 3 行巨型引用块 → 一行指针；第十节 → 一行指针）

- [ ] **Step 1: 探结构**：`grep -n '^## 十\|^## 九\|第九节\|修订记录' docs/需求清单.md` 确认第十节起止行号；探测行尾：`file docs/需求清单.md`。
- [ ] **Step 2: 快照**：`mkdir -p tmp && cp docs/需求清单.md tmp/需求清单.bak-20261002-gov2.md`（`tmp/` 已在 .gitignore，不涉 git）并记录原行数 `wc -l`。
- [ ] **Step 3: 写拆分脚本 `tools/gov2_split_req.py`**（全路径 python 执行）：按行抽取 ①头部引用块（第 3 行整行）②第十节全文（起止锚点=上一步实测行号），逐字写入修订史文件；第十节内容按「### V1.xx」已有标题保留结构，头部引用块内 `**V1.nn：…** **` 分隔的每条长文拆为独立段落（正则 `(?=\*\*V1\.\d+)` 处断行，逐字不删减）。需求清单原位替换为：`> 修订史（V1.19~V1.59 全部逐版记录，三源优先序第一位）：docs/archive/需求修订史-V1.19~V1.59.md`。
  护栏断言：迁移后 `修订史行数 + 需求清单行数 ≥ 原行数 - 4`（允许指针净亏）；需求清单中 grep 不再命中「V1.32：记账模块」等长文标志；两文件字节数打印比对。任一断言失败→exit 1 并回滚快照。
- [ ] **Step 4: 抽读校验**：人工 Read 修订史头/中/尾 3 段与需求清单新头部，确认无 UTF-8 乱码、无表格残行（本仓陷阱：Markdown 表格插行吞行首）。
- [ ] **Step 5: 提交**：`git commit -m "docs(治理): 需求清单瘦身——第十节与头部修订长文迁出为《需求修订史》，清单只留现行定义+指针" -- docs/需求清单.md docs/archive/`，status 复核。

### Task 3：交接文档头部瘦身（422 → ≈150 行）

**Files:**
- Modify: `docs/交接文档.md`

- [ ] **Step 1: 快照 + 实测头部边界**（`当前状态`/`历史时点·轮2`/`当前阶段` 三条超长行所在行号区间）。
- [ ] **Step 2: 脚本改写 `tools/gov2_slim_handover.py`**：头部三条超长行整块替换为 6~10 行短列表（当前状态指针→STATUS.md；轮2/轮3 每条压缩为 1 行「日期｜结论｜提交/发版」）；「0. 快速上手」首行改为指向 AGENTS/STATUS/INDEX 三件套；§2 当前状态、§3 下一步保留但每小节 ≤15 行，超出内容并入 §5 变更日志尾部（逐字搬家，不删信息）。断言：新文件行数 ∈ [120, 200]；`轮3`、`v0.2.9` 关键词仍在（防搬丢）；变更日志行数只增不减。
- [ ] **Step 3: 提交**：局部提交路径 `docs/交接文档.md`。

### Task 4：工单生命周期流转（27 份分类搬迁）

**Files:**
- Create: `docs/handoff/`、`docs/archive/`（archive 已在 Task 2 建）
- Modify: `docs/INDEX.md`（状态列）、`AGENTS.md`/`docs/STATUS.md` 内工单指针

- [ ] **Step 1: 分类判定**（脚本 `tools/gov2_classify.sh` 输出清单供人工确认，判据）：
  - **活**（留 `docs/handoff/`）：`交棒话术-20261002-下一版实现批-F01-批C-R32精修.md`（下一站规格）、`真机逐屏验收清单-20261002-xray词库与精化.md`（有未勾项）、`交棒话术-20260929-R15-1整批撤销.md`（V1.56 工单未实现，测试注释点名）、`真机逐屏验收清单-20260929.md`（逐屏验收积压在案）+ 逐份 grep「未验/待拍板/积压」复核。
  - **闭环**（→ `docs/archive/`）：其余全部交棒话术/验收清单/拍板记录（交接文档变更日志已登记交付者）。
  - **不动**：原地不动清单（Global Constraints）。
- [ ] **Step 2: 搬迁**：`git mv` 逐份执行（活→handoff，闭环→archive）；未跟踪文件零触碰。
- [ ] **Step 3: 更新指针**：AGENTS.md、STATUS.md、INDEX.md、交接文档中所有被搬工单的旧路径改为新路径（脚本批量替换 + 命中断言）；归档文档**互不重写**（历史路径在 archive 内部残留引用属正常，doclint 按 Task 7 的豁免规则跳过 archive）。
- [ ] **Step 4: 提交**：`git commit -- docs/ AGENTS.md` 路径限定（含全部 mv）。

### Task 5：产物出仓（截图 + attic + profile）

**Files:**
- Delete(git): `docs/acceptance*`（已跟踪 146）、`prototype/shots/`（已跟踪 147）、`tools/attic/`（已跟踪 156）
- Modify: `.gitignore`

- [ ] **Step 1: 出仓前留底（本机磁盘，不进 git）**：`mkdir -p /d/dev_workplace/lh-artifacts-keep && cp -r` 三批目录过去——防用户日后要原始取证图（可再生性差的是截图不是 profile）。
- [ ] **Step 2: git rm**：`git rm -r --quiet docs/acceptance-20260920 docs/acceptance-20260921 …（逐个枚举 git ls-files 前缀，勿用通配误删未跟踪）`、`git rm -r prototype/shots`、`git rm -r tools/attic`。核对 `git status` 删除清单只含已跟踪路径。
- [ ] **Step 3: .gitignore 追加**：

```
# 治理二轮：取证产物与快照坟场永不入库
docs/acceptance*
prototype/shots/
tools/attic/
tools/.f*probe/
tools/.xr-probe*/
tools/.*-profile/
```

（`tools/attic/` 忽略后仍可作本机快照落脚，与 Task 2 Step 2 一致。）
- [ ] **Step 4: 磁盘清理 profile**：`find tools -maxdepth 2 -type d -name '*profile*' -o -name '*.f01-probe' -o -name '.xr-probe-fresh' | xargs ls -ld --time-style=long-iso`；仅删 **mtime 早于 2026-09-25** 的浏览器 profile 目录；`.f01-probe`、`.xr-probe-fresh` 保留。打印实删清单与释放体积。
- [ ] **Step 5: 提交**：`git commit -- docs prototype tools/attic .gitignore`。

### Task 6：代码体积债务登记（只登记）

**Files:**
- Modify: `docs/治理backlog行为改工单-20260929.md`（文末追加一节）

- [ ] **Step 1:** 追加「## 体积债务登记（20261002 治理二轮）」：12 个 lib 超 1200 行文件 + `test/read_page_test.dart`(2383) 列行（路径｜行数｜归属功能｜拆分建议时机）；read 区 5 文件标注「⛔ V5 并行会话占用，解除前禁动」。
- [ ] **Step 2:** 提交 `-- docs/治理backlog行为改工单-20260929.md`。

### Task 7：doclint 收口 + 三件验证

**Files:**
- Create: `tools/doclint.sh`

- [ ] **Step 1: 写 doclint**：扫描 `AGENTS.md docs/*.md docs/handoff/*.md docs/STATUS.md`（**跳过 docs/archive/ 与 superpowers/**）中形如 `docs/…md`、`prototype/…html`、`tools/…` 的相对路径引用；引用目标不存在→红（豁免：明确标注「已删除/git log 找回」的行）。另断言 INDEX.md 每行路径可解析（archive 行除外可标 ⛔删除）。
- [ ] **Step 2: 跑 doclint** 至零红（补指针/改路径，属 Task 4 替换遗漏的修掉）。
- [ ] **Step 3: 新会话模拟**：只读 AGENTS.md + STATUS.md + INDEX.md（合计 ≤200 行），书面回答：当前 HEAD 链哪里看／下一站是什么／read 区为什么禁动——三问皆有答案即过。
- [ ] **Step 4: 归档可达性抽查**：任选 2 份 archive 工单，`git log --follow -1` 可追、INDEX 有行。
- [ ] **Step 5: 提交** doclint 收尾修正；汇总 `git log --oneline` 本轮全部提交 + 体积前后对比（docs/ 与工作区 MB、开场必读行数），向用户汇报并**请示推送**。

---

## 自审记录（writing-plans Self-Review）

- 规格覆盖：§1→T1，§2→T4，§3→T2/T3/T1(删除项)，§4→T5，§5→T6，§6→T7+Global。无缺口。
- 占位符：STATUS 初稿含「执行时微调」——属事实来源说明而非任务占位，内容清单已给全。
- 一致性：修订史文件名在 T2/T3/AGENTS 统一为 `docs/archive/需求修订史-V1.19~V1.59.md`；快照统一落 `tmp/`（gitignored），不写 `tools/attic/`（该目录 Task 5 才出仓，提前写入会污染仍跟踪目录）。
