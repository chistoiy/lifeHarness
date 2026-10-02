# STATUS（唯一状态源 · 最后更新 2026-10-02 治理二轮）

> 状态变化只改本文件；历史时点沉 `docs/交接文档.md` 文末变更日志。本文不钉具体 HEAD sha（防漂移），看 `git log --oneline -3`。

- 分支 `feat/m0-skeleton`；远端进度：**链上至 `32f3470` 双端对齐；本地另有 3 提交未推**（批二 R3-3 明细 `7cb6b81` + F01 §1 拍板 `7e566c0` + 本批真机/文档收口）。
- 最新预发布仍为 **`v0.2.10-underline`**（钉版 `f04e248`＝`0.2.10+4047`·三包双端挂齐·Gitee 配额腾挪工装 `tools/gitee_free_quota.py`）· DB `DbSchema.version=34`（批二**零迁移**）· 全量门禁基线 **1786 绿**（未重跑）· 批二批内 **77 绿**（refine 20＋ui 9＋panel 23＋dao/arch/catch/size 回归），变异四刀全红自证。
- 复测包：**6047 已装 ea028260**（覆盖安装·数据未清·`versionName 0.2.10`）；真机轮4① 划线复验 **①②③ 过**（只涂所选字／重进仍精确／书摘行落库含章页色类，④旧整段行未单验＝用例已覆盖），取证截图落仓库外 `tmp/device/`；下一编号 6048。
- 下一站：**批一 LH-F01 与批三 原书样式保真仍锁在 V5 视觉线定稿之后**（V5 现状＝「待产品逐屏确认·未进 Flutter」，见 `docs/阅读模块V5视觉设计说明-20261002.md` 头部）；不撞面的可开工项＝`docs/handoff/交棒话术-20261003-XRay中心三段同页.md`（先要 §2 三项拍板：AI 段的书归属）。批三前置缺口：《資治通鑑 特殊標點版》样包**取不到**——release 私有目录 adb `Permission denied`、`/sdcard` 全盘零 epub → 只能由产品把 .epub 拷到 PC（原「重连后 adb 拉回」这条已证伪）。
- 并行互斥面（只读不写不提交不回退）：`docs/阅读模块V5视觉设计说明-20261002.md`、`docs/阅读模块开场白-20261002.md`、`docs/阅读模块开发省token策略-20261002.md`、`docs/项目拆分重构调研报告-20261002.md`、`prototype/reader-v4|v5|reader/`、`prototype/index-bookshelf-reader.html`、`prototype/index-health.html`、`docs/acceptance_20261001_xray/`、`docs/acceptance_20261002_xray2/`。与本批同打 `lib/features/read/**`——V5 线写权先后归用户裁定。治理后口径：文档路由看 INDEX，状态只看本文，死链体检 `python tools/doclint.py`（批次收口随跑）。
- 并行互斥面（只读不写不提交不回退）：`docs/阅读模块V5视觉设计说明-20261002.md`、`docs/阅读模块开场白-20261002.md`、`docs/阅读模块开发省token策略-20261002.md`、`docs/项目拆分重构调研报告-20261002.md`、`prototype/reader-v4|v5|reader/`、`prototype/index-bookshelf-reader.html`、`prototype/index-health.html`、`docs/acceptance_20261001_xray/`、`docs/acceptance_20261002_xray2/`。与本批同打 `lib/features/read/**`——V5 线写权先后归用户裁定。
- 环境/禁令/忽略清单/工单生命周期：一律看 `AGENTS.md`；文档地图看 `docs/INDEX.md`。
