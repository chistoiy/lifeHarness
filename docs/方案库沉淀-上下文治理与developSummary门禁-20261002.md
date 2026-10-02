# 方案库沉淀 · 上下文治理与 developSummary 索引门禁（2026-10-02 · **已双端推送**）

> 状态：本篇方案已按 `chistoiy/developSummary` 的 `TEMPLATE.md` 成文并**双端推送完成**，
> 三份文件（文章 + README + lint 工装）本地 / GitHub / Gitee **三方 blob sha 互验相同**：
>
> · `engineering/agent-context-governance-lazy-loading.md` · sha `ea05f661a8…`（git hash-object 全值见 developSummary `git ls-tree main`）
> · `README.md` · sha `da3114e404…`（§4 索引改为主题簇分组 + 口径补句 + 收录流程加 lint 步）
> · `developSummary/tools/lint.py` · sha `96b4c0dab0…`（developSummary 自家庭索引门禁：索引↔文件双向一致 + 行列数/场景列必填/目录列匹配）
> · Gitee 提交 `43a535d`；GitHub 经 `gh api -X PUT` base64 直传同内容。
>
> ⚠️ **developSummary 侧为权威版本**：今后改这套治理规则要改那边，再回灌本文件。
> 项目侧事实源：`docs/superpowers/specs/2026-10-02-context-governance-design.md`、
> `docs/superpowers/plans/2026-10-02-context-governance.md`、AGENTS.md「工单生命周期」节、`tools/doclint.py`。

## 本篇抽了什么

治理二轮沉淀出的通用方案：**Agent 协作项目的上下文治理**——三件套开场（入口/状态源/文档地图，
合计 ≤150 行）、工单出生-收口-归档生命周期、历史与现行分离（修订史搬家 + 体积守恒脚本）、
产物不入库、doclint 死链+漂移五检并接进全量门禁作硬触发点、变异校验自证、跨工具入口别名。
编号规则 R1~R11 + 9 条实测坑（含本轮新踩的：目录级 pathspec 卷走并行会话 M 文件、
`*` 行豁免误伤粗体假绿、`.json` 被截成 `.js`、GBK 控制台乱码误导文件名修复连错两次）。

## 顺带的 developSummary 小治理（用户批准的 1/2/4 项）

1. `developSummary/tools/lint.py`：索引门禁（本项目 doclint 思路反哺方案库自身）；变异校验 M1 漏登记/M2 死链/M3 场景列空 三连红过。
2. README §4 索引按主题簇分组（AI协作流程 / 守护门禁提速 / 发布交付产物 / 排障方法论 / 移动交互组件 / 协议服务端Web）。
3. §5 补「六段＝TEMPLATE 十一段的必备子集」口径句；§6 收录流程插入 lint 步。
4. 未做（留下一轮）：元信息「版本锚点」列、双端同步手法独立成篇。
